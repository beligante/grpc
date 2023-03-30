defmodule GRPC.Client.Adapters.Mint.ConnectionProcessV2 do
  @moduledoc false

  @behaviour :gen_statem

  @connection_closed_error "the connection is closed"

  alias Mint.HTTP2

  alias GRPC.Client.Adapters.Mint.ResponseProcess
  alias GRPC.Client.Adapters.Mint.RequestStream

  require Logger

  @impl true
  def callback_mode(), do: [:state_functions, :state_enter]

  @doc """
  Starts and link connection process
  """
  @spec start_link(Mint.Types.scheme(), Mint.Types.address(), :inet.port_number(), keyword()) ::
          GenServer.on_start()
  def start_link(scheme, host, port, opts \\ []) do
    opts = Keyword.put(opts, :parent, self())
    :gen_statem.start_link(__MODULE__, {scheme, host, port, opts}, [])
  end

  @doc """
  Sends a request to the connected server.

  ## Options

    * :response_pid (required) - the process to where send the responses coming from the connection will be sent to be processed
  """
  @spec request(
          pid :: pid(),
          path :: String.t(),
          Mint.Types.headers(),
          body :: iodata() | nil | :stream,
          opts :: keyword()
        ) :: {:ok, %{request_ref: Mint.Types.request_ref()}} | {:error, Mint.Types.error()}
  def request(pid, path, headers, body, opts \\ []) do
    :gen_statem.call(pid, {:request, path, headers, body, opts})
  end

  @doc """
  Closes the given connection.
  """
  @spec disconnect(pid :: pid()) :: :ok
  def disconnect(pid) do
    :gen_statem.call(pid, :disconnect)
  end

  @doc """
  Streams a chunk of the request body on the connection or signals the end of the body.
  """
  @spec stream_request_body(
          pid(),
          Mint.Types.request_ref(),
          iodata() | :eof | {:eof, trailing_headers :: Mint.Types.headers()}
        ) :: :ok | {:error, Mint.Types.error()}
  def stream_request_body(pid, request_ref, body) do
    :gen_statem.call(pid, {:stream_body, request_ref, body}, 30_000)
  end

  @doc """
  cancels an open request request
  """
  @spec cancel(pid(), Mint.Types.request_ref()) :: :ok | {:error, Mint.Types.error()}
  def cancel(pid, request_ref) do
    :gen_statem.call(pid, {:cancel_request, request_ref})
  end


  @impl true
  def init({scheme, host, port, opts}) do
    case Mint.HTTP.connect(scheme, host, port, opts) do
      {:ok, conn} ->
        data = %{conn: conn, parent: opts[:parent], requests: %{}}
        {:ok, :connected, data}

      {:error, reason} ->
        Logger.error("unable to establish a connection. reason: #{inspect(reason)}")
        {:stop, reason}
    end
  catch
    :exit, reason ->
      Logger.error("unable to establish a connection. reason: #{inspect(reason)}")
      {:stop, reason}
  end

  @doc false
  def disconnected(event, content, data)

  def disconnected(:enter, :disconnected, _data) do
    :keep_state_and_data
  end

  # When entering a disconnected state we need to fail all of the pending
  # requests
  def disconnected(:enter, :connected, data) do
    :ok = close_all_pending_requests(data.requests)
    {:keep_state, %{data| requests: %{}, conn: nil}}
  end

  # Its possible that we can receive an info message telling us that a socket
  # has been closed. This happens after we enter a disconnected state from a
  # read_only state but we don't have any requests that are open. We've already
  # closed the connection and thrown it away at this point so we can just retain
  # our current state.
  def disconnected(:info, _message, _data) do
    :keep_state_and_data
  end

  # Immediately fail a request if we're disconnected
  def disconnected({:call, from}, {:stream_body, _request_ref, _body}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, "the connection is closed"}}}
  end

  def disconnected({:call, from}, {:request, _path, _headers, _body, _opts}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, "the connection is closed"}}}
  end

  # Ignore cancel requests if we are disconnected
  def disconnected({:call, _from}, {:cancel, _ref}, _data) do
    :keep_state_and_data
  end

  # stops simply stop the process when disconnect is received
  def disconnect({:call, from}, :disconnect, data) do
    {:stop_and_reply, :normal, data, {:reply, from, :ok}}
  end

  @doc false
  def connected(event, content, data)

  def connected(:enter, _old_state, _data) do
    :keep_state_and_data
  end

  # Issue request to the upstream server. We store a ref to the request so we
  # know who to respond to when we've completed everything
  def connected({:call, from}, {:request, path, headers, body, opts}, data) do
    request = RequestStream.new(body, opts[:response_pid])
    with {:ok, data, ref} <- request(data, path, headers),
         data = put_in(data.requests[ref], request),
         {:ok, data} <- continue_request(data, ref) do
      {:keep_state, data, {:reply, from, {:ok, %{request_ref: ref}}}}
    else
      {:error, data, error} ->
        actions = [{:reply, from, {:error, error}}]

        if HTTP2.open?(data.conn) do
          {:keep_state, data, actions}
        else
          {:next_state, :disconnected, data, actions}
        end
    end
  end

  def connected({:call, from}, {:stream_body, request_ref, body}, data) do
    if match?(%{requests: %{^request_ref => _}}, data) do
      %{requests: %{^request_ref => request_state}} = data
       new_request_state =
        case body do
          :eof -> RequestStream.eof(request_state)
          _other -> RequestStream.append(request_state, body)
        end

      data = put_in(data.requests[request_ref], new_request_state)
      case continue_request(data, request_ref) do
        {:ok, data} -> {:keep_state, data, {:reply, from, :ok}}
        {:error, data, reason} -> {:keep_state, data, {:reply, from, {:error, reason}}}
      end
    else
      {:keep_state, data, {:reply, from, :ok}}
    end
  end

  def connected({:call, from}, {:cancel_request, request_ref}, data) do
    if match?(%{requests: %{^request_ref => _}}, data) do
      ResponseProcess.done(data.requests[request_ref].response_pid)
      {_from, data} = pop_in(data.requests[request_ref])

      case HTTP2.cancel_request(data.conn, request_ref) do
        {:ok, conn} -> {:keep_state, %{data| conn: conn}, {:reply, from, :ok}}
        {:error, conn, error} -> {:keep_state, %{data| conn: conn}, {:reply, from, {:error, error}}}
      end
    else
      # request might have been ended by the server and requester doesn't know about that yet.
      {:keep_state, data, {:reply, from, :ok}}
    end
  end

  def connected(:info, message, data) do
    case HTTP2.stream(data.conn, message) do
      {:ok, conn, responses} ->

        data = %{data| conn: conn} |> handle_responses(responses)

        if HTTP2.open?(conn) do
          {:keep_state, continue_requests(data)}
        else
          {:next_state, :disconnected, data}
        end

      {:error, conn, error, responses} ->
        Logger.error([
          "Received error from server",
          Exception.message(error)
        ])

        data = %{data| conn: conn} |> handle_responses(responses)

        if HTTP2.open?(conn) do
          {:keep_state, continue_requests(data)}
        else
          {:next_state, :disconnected, data}
        end

      :unknown ->
        Logger.warn(["Received unknown message: ", inspect(message)])
        :keep_state_and_data
    end
  end

  # a wrapper around Mint.HTTP2.request/5
  # wrapping allows us to more easily encapsulate the conn within `data`
  defp request(data, path, headers) do
    case HTTP2.request(data.conn, "POST", path, headers, :stream) do
      {:ok, conn, ref} -> {:ok, %{data| conn: conn}, ref}
      {:error, conn, reason} -> {:error, %{data| conn: conn}, reason}
    end
  end

  # this is also a wrapper (Mint.HTTP2.stream_request_body/3)
  defp do_stream_request_body(data, ref, body) do
    case HTTP2.stream_request_body(data.conn, ref, body) do
      {:ok, conn} -> {:ok, %{data| conn: conn}}
      {:error, conn, reason} -> {:error, %{data| conn: conn}, reason}
    end
  end

  defp continue_requests(data) do
    Enum.reduce(data.requests, data, fn {ref, request}, data_acc ->
      case continue_request(data_acc, ref) do
        {:ok, data} ->
          data
        {:error, data, reason} ->
          ResponseProcess.consume(request.response_pid, :error, reason)
          data
      end
    end)
  end

  defp continue_request(data, ref) do
    request = data.requests[ref]

    if RequestStream.streaming?(request) do
      window = smallest_window(data.conn, ref)
      {new_request, chunks} = RequestStream.next_chunk(request, window)
      data = put_in(data.requests[ref], new_request)
      reducer = fn
        chunk, {:ok, data} -> do_stream_request_body(data, ref, chunk)
        _chunk, error -> error
      end
      Enum.reduce(chunks, {:ok, data}, reducer)
    else
      {:ok, data}
    end
  end

  defp smallest_window(conn, ref) do
    min(
      HTTP2.get_window_size(conn, :connection),
      HTTP2.get_window_size(conn, {:request, ref})
    )
  end

  defp close_all_pending_requests(requests) do
    Enum.each(requests, fn {_ref, %{response_pid: response}} ->
      ResponseProcess.consume(response, :error, @connection_closed_error)
      ResponseProcess.done(response)
    end)
  end

  def handle_responses(data, [] = _responses), do: data
  def handle_responses(data, responses) do
    responses
    |> Enum.group_by(fn
      {_kind, ref, _content} -> ref
      {_kind, ref} -> ref
    end)
    |> Enum.reduce(data, fn {request_ref, responses}, data_acc ->
      %{requests: %{^request_ref => request_state}} = data_acc

      ResponseProcess.consume(request_state.response_pid, :responses, responses)

      if Enum.any?(responses, &match?({:done, _}, &1)) do
        {_req_state, data} = pop_in(data_acc.requests[request_ref])
        data
      else
        data_acc
      end
    end)
  end
end