defmodule GRPC.Client.Adapters.Mint.ConnectionProcess.State do
  @moduledoc false

  @type t :: %{
          conn: Mint.HTTP.t(),
          requests: map(),
          parent: pid()
        }

  def new(conn, parent) do
    %{conn: conn, request_stream_queue: :queue.new(), parent: parent, requests: %{}}
  end

  def update_conn(state, conn) do
    %{state | conn: conn}
  end

  def update_request_stream_queue(state, queue) do
    %{state | request_stream_queue: queue}
  end

  def put_empty_ref_state(state, ref, response_pid) do
    put_in(state, [:requests, ref], %{
      response_pid: response_pid,
      from: nil
    })
  end

  def response_pid(state, ref) do
    %{requests: %{^ref => %{response_pid: response_pid}}} = state
    response_pid
  end

  def pop_ref(state, ref) do
    pop_in(state, [:requests, ref])
  end

  def put_from(state, ref, from) do
    put_in(state, [:requests, ref, :from], from)
  end
end
