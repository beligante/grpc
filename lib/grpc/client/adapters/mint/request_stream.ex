defmodule GRPC.Client.Adapters.Mint.RequestStream do
  @moduledoc false

  defstruct [:status, :buffer, :response_pid]

  def new(body, response_pid) do
    buffer = if body == :stream, do: <<>>, else: body
    status = if body == :stream, do: :streaming, else: :eof
    %__MODULE__{
      status: status,
      buffer: buffer,
      response_pid: response_pid
    }
  end

  def streaming?(%{status: status}), do: status in [:streaming, :eof]

  def eof(request) do
    %{request| status: :eof}
  end

  def append(%{buffer: current_buffer} = request, buffer) do
    %{request| buffer: current_buffer <> buffer}
  end

  # gets the next chunk of data that will fit into the given window size
  def next_chunk(request, window)

  # when the buffer is empty and status is done, send eof. otherwise wait for more buffer
  def next_chunk(%__MODULE__{buffer: <<>>, status: status} = request, _window) do
    if status == :eof, do: {%{request|status: :done}, [:eof]}, else: {request, []}
  end

  def next_chunk(%__MODULE__{buffer: buffer, status: status} = request, window) when window > 0 do
    case buffer do
      <<bytes_to_send::binary-size(window), rest::binary>> ->
        # when the buffer contains more bytes than a window, send as much of the
        # buffer as we can
        {%{request| buffer: rest}, [bytes_to_send]}

      _ ->
        if status == :eof do
          {%{request| buffer: <<>>, status: :done}, [buffer, :eof]}
        else
          {%{request| buffer: <<>>}, [buffer]}
        end
    end
  end

  def next_chunk(request, _window), do: {request, []}
end