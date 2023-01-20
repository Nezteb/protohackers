defmodule Protohackers.EchoServer do
  @moduledoc false
  use GenServer
  require Logger

  defstruct [:listen_socket, :supervisor]

  @port 5001
  @kilobytes 1024
  @limit 100 * @kilobytes

  def start_link([] = _args) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(nil) do
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      # Receives data as binaries (instead of lists)
      mode: :binary,
      # Allow host/port reuse the listener crashes
      reuseaddr: true,
      # Require explicit calls to recv
      active: false,
      # "Option {exit_on_close, false} is useful if the peer has done a shutdown on the write side."
      exit_on_close: false
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Starting echo server on port #{@port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  ## Helpers

  defp handle_connection(socket) do
    case recv_until_closed(socket, _buffer = "", _buffered_size = 0) do
      {:ok, data} -> :gen_tcp.send(socket, data)
      {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  defp recv_until_closed(socket, buffer, buffered_size) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} when buffered_size + byte_size(data) > @limit -> {:error, :buffer_overflow}
      {:ok, data} -> recv_until_closed(socket, [buffer, data], buffered_size + byte_size(data))
      {:error, :closed} -> {:ok, buffer}
      {:error, reason} -> {:error, reason}
    end
  end
end
