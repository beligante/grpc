{options, _, _} = OptionParser.parse(System.argv(), strict: [rounds: :integer, concurrency: :integer, port: :integer, level: :string])
rounds = Keyword.get(options, :rounds) || 10
max_concurrency = System.schedulers_online()
concurrency = Keyword.get(options, :concurrency) || max_concurrency
port = Keyword.get(options, :port) || 0
level = Keyword.get(options, :level) || "warning"
level = String.to_existing_atom(level)

require Logger

Logger.configure(level: level)

Logger.info("Rounds: #{rounds}; concurrency: #{concurrency}; port: #{port}")

alias GRPC.Client.Adapters.Gun
alias GRPC.Client.Adapters.Mint
alias Interop.Client

{:ok, _pid, port} = GRPC.Server.start_endpoint(Interop.Endpoint, port)

defmodule InteropTestRunner do
  def run(_cli, adapter, port, rounds, adapter_opts) do
    opts = [interceptors: [GRPC.Client.Interceptors.Logger], adapter: adapter, adapter_opts: adapter_opts]
    ch = Client.connect("127.0.0.1", port, opts)

    for _ <- 1..rounds do
      Client.empty_unary!(ch)
      Client.cacheable_unary!(ch)
      Client.large_unary!(ch)
      Client.large_unary2!(ch)
      Client.client_compressed_unary!(ch)
      Client.server_compressed_unary!(ch)
      Client.client_streaming!(ch)
      Client.client_compressed_streaming!(ch)
      Client.server_streaming!(ch)
      Client.server_compressed_streaming!(ch)
      Client.ping_pong!(ch)
      Client.empty_stream!(ch)
      Client.custom_metadata!(ch)
      Client.status_code_and_message!(ch)
      Client.unimplemented_service!(ch)
      Client.cancel_after_begin!(ch)
      Client.cancel_after_first_response!(ch)
      Client.timeout_on_sleeping_server!(ch)
    end
    :ok
  end
end

mint_no_config = fn  ->
  Logger.info("Starting run for adapter: #{Mint}")
  adapter_opts = []
  args = [Mint, port, rounds, adapter_opts]
  stream_opts = [max_concurrency: concurrency, ordered: false, timeout: :infinity]
  1..concurrency
  |> Task.async_stream(InteropTestRunner, :run, args, stream_opts)
  |> Enum.to_list()
end


mint_with_config_change = fn  ->
  Logger.info("Starting run for adapter: #{Mint}")
  adapter_opts = [
    client_settings: [
      initial_window_size: 8_000_000,
      max_frame_size: 8_000_000,
    ]
  ]
  args = [Mint, port, rounds, adapter_opts]
  stream_opts = [max_concurrency: concurrency, ordered: false, timeout: :infinity]
  1..concurrency
  |> Task.async_stream(InteropTestRunner, :run, args, stream_opts)
  |> Enum.to_list()
end


gun_no_config_change = fn  ->
  Logger.info("Starting run for adapter: #{Gun}")
  adapter_opts = []
  args = [Gun, port, rounds, adapter_opts]
  stream_opts = [max_concurrency: concurrency, ordered: false, timeout: :infinity]
  1..concurrency
  |> Task.async_stream(InteropTestRunner, :run, args, stream_opts)
  |> Enum.to_list()
end



Benchee.run(
  %{
    "Mint (with config change)" => mint_with_config_change,
    "Mint (with NO config change)" => mint_no_config,
    "Gun (with NO config change)" => gun_no_config_change,
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
      file: "comparison.md",
      description: """
      This benchmark compares the performance of Mint introducing a new config for window size and frame size.
      """
    }
  ]
)