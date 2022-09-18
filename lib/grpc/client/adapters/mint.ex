defmodule GRPC.Client.Adapters.Mint do
  @moduledoc """
  A client adapter using mint
  """

  alias GRPC.{Channel, Credential}
  alias GRPC.Client.Adapters.Mint.{ConnectionProcess, StreamResponseProcess}

  @behaviour GRPC.Client.Adapter

  @default_connect_opts [protocols: [:http2]]
  @default_transport_opts [timeout: :infinity]

  @impl true
  def connect(%{host: host, port: port} = channel, opts \\ []) do
    opts = Keyword.merge(@default_connect_opts, connect_opts(channel, opts))

    channel
    |> mint_scheme()
    |> ConnectionProcess.start_link(host, port, opts)
    |> case do
      {:ok, pid} -> {:ok, %{channel | adapter_payload: %{conn_pid: pid}}}
      # TODO add proper error handling
      error -> raise "An error happened while trying to opening the connection: #{inspect(error)}"
    end
  end

  @impl true
  def disconnect(%{adapter_payload: %{conn_pid: pid}} = channel)
      when is_pid(pid) do
    :ok = ConnectionProcess.disconnect(pid)
    {:ok, %{channel | adapter_payload: nil}}
  end

  def disconnect(%{adapter_payload: nil} = channel) do
    {:ok, channel}
  end

  @impl true
  def send_request(%{channel: %{adapter_payload: nil}}, _message, _opts),
      do: raise "Can't perform a request without a connection process"

  def send_request(
        %{channel: %{adapter_payload: %{conn_pid: pid}}, path: path} = stream,
        message,
        opts
      )
      when is_pid(pid) do
    headers = GRPC.Transport.HTTP2.client_headers_without_reserved(stream, opts)
    {:ok, data, _} = GRPC.Message.to_data(message, opts)

    {:ok, stream_response_pid} =
      StreamResponseProcess.start_link(stream, opts[:return_headers] || false)

    response =
      ConnectionProcess.request(pid, "POST", path, headers, data,
        stream_response_pid: stream_response_pid
      )

    stream
    |> GRPC.Client.Stream.put_payload(:response, response)
    |> GRPC.Client.Stream.put_payload(:stream_response_pid, stream_response_pid)
  end

  @impl true
  def receive_data(
        %{server_stream: true, payload: %{response: response, stream_response_pid: pid}},
        opts
      ) do
    with {:ok, headers} <- response do
      stream = StreamResponseProcess.build_stream(pid)

      case opts[:return_headers] do
        true -> {:ok, stream, headers}
        _any -> {:ok, stream}
      end
    end
  end

  # for streamed requests
  def receive_data(
        %{payload: %{response: {:ok, %{request_ref: _ref}}, stream_response_pid: pid}},
        opts
      ) do
    with stream <- StreamResponseProcess.build_stream(pid),
         responses <- Enum.to_list(stream),
         :ok <- check_for_error(responses) do
      {:ok, data} = Enum.find(responses, fn {status, _data} -> status == :ok end)

      case opts[:return_headers] do
        true -> {:ok, data, get_headers(responses) |> append_trailers(responses)}
        _any -> {:ok, data}
      end
    end
  end

  def receive_data(%{payload: %{response: response, stream_response_pid: pid}}, opts) do
    with {:ok, %{headers: headers}} <- response,
         stream <- StreamResponseProcess.build_stream(pid),
         responses <- Enum.into(stream, []),
         :ok <- check_for_error(responses) do
      {:ok, data} = Enum.find(responses, fn {status, _data} -> status == :ok end)

      case opts[:return_headers] do
        true -> {:ok, data, append_trailers(headers, responses)}
        _any -> {:ok, data}
      end
    end
  end

  @impl true
  def send_headers(%{channel: %{adapter_payload: nil}}, _opts),
      do: raise "Can't start a client stream without a connection process"

  def send_headers(%{channel: %{adapter_payload: %{conn_pid: pid}}, path: path} = stream, opts) do
    headers = GRPC.Transport.HTTP2.client_headers_without_reserved(stream, opts)

    {:ok, stream_response_pid} =
      StreamResponseProcess.start_link(stream, opts[:return_headers] || false)

    response =
      ConnectionProcess.request(pid, "POST", path, headers, :stream,
        stream_response_pid: stream_response_pid
      )

    stream
    |> GRPC.Client.Stream.put_payload(:response, response)
    |> GRPC.Client.Stream.put_payload(:stream_response_pid, stream_response_pid)
  end

  @impl true
  def send_data(
        %{
          channel: %{adapter_payload: %{conn_pid: pid}},
          payload: %{response: {:ok, %{request_ref: request_ref}}}
        } = stream,
        message,
        opts
      ) do
    {:ok, data, _} = GRPC.Message.to_data(message, opts)
    :ok = ConnectionProcess.stream_request_body(pid, request_ref, data)
    # TODO: check for trailer headers to be sent here
    if opts[:send_end_stream], do: ConnectionProcess.stream_request_body(pid, request_ref, :eof)
    stream
  end

  defp connect_opts(%Channel{scheme: "https"} = channel, opts) do
    %Credential{ssl: ssl} = Map.get(channel, :cred, %Credential{})

    transport_opts =
      opts
      |> Keyword.get(:transport_opts, [])
      |> Keyword.merge(ssl)

    [transport_opts: Keyword.merge(@default_transport_opts, transport_opts)]
  end

  defp connect_opts(_channel, opts) do
    transport_opts = Keyword.get(opts, :transport_opts, [])
    [transport_opts: Keyword.merge(@default_transport_opts, transport_opts)]
  end

  defp mint_scheme(%Channel{scheme: "https"} = _channel), do: :https
  defp mint_scheme(_channel), do: :http

  def check_for_error(responses) do
    error = Enum.find(responses, fn {status, _data} -> status == :error end)
    if error == nil, do: :ok, else: error
  end

  defp append_trailers(headers, responses) do
    responses
    |> Enum.find(fn {status, _data} -> status == :trailers end)
    |> case do
      nil -> %{headers: headers}
      {:trailers, trailers} -> %{headers: headers, trailers: trailers}
    end
  end

  defp get_headers(responses) do
    responses
    |> Enum.find(fn {status, _data} -> status == :headers end)
    |> case do
      nil -> nil
      {:headers, headers} -> headers
    end
  end
end
