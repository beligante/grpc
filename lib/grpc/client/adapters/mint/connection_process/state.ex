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
      stream_response_pid: response_pid,
      done: false,
      response: %{},
      from: nil
    })
  end

  def update_response_status(state, ref, status) do
    put_in(state, [:requests, ref, :response, :status], status)
  end

  def update_response_headers(state, ref, headers) do
    put_in(state.requests[ref].response[:headers], headers)
  end

  def empty_headers?(state, ref) do
    is_nil(state.requests[ref].response[:headers])
  end

  def stream_response_pid(state, ref) do
    %{requests: %{^ref => %{stream_response_pid: response_pid}}} = state
    response_pid
  end

  def pop_ref(state, ref) do
    pop_in(state.requests[ref])
  end

  def put_from(state, ref, from) do
    put_in(state, [:requests, ref, :from], from)
  end
end
