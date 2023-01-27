defmodule Protohackers.PrimeServer do
  @moduledoc false
  use GenServer
  require Logger

  defstruct [:listen_socket, :supervisor]

  @port 5002
  @kilobytes 1024

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
      exit_on_close: false,
      # gen_tcp will only return one line at a time
      packet: :line,
      buffer: 100 * @kilobytes
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Starting #{__MODULE__} on port #{@port}")
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
    case echo_lines_until_closed(socket) do
      :ok -> :ok
      {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  defp echo_lines_until_closed(socket) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"method" => "isPrime", "number" => number}} when is_number(number) ->
            Logger.info("Checking if number is prime: #{number}")

            response = %{"method" => "isPrime", "prime" => prime?(number)}

            # Re-add the expected newline (as IOData)
            :gen_tcp.send(socket, [Jason.encode!(response), ?\n])
            echo_lines_until_closed(socket)

          other ->
            Logger.warn("Bad request: #{inspect(other)}")
            :gen_tcp.send(socket, "Bad request\n")
            {:error, :bad_request}
        end

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def prime?(number) when is_float(number), do: false
  def prime?(number) when number <= 1, do: false
  def prime?(number) when number in [2, 3], do: true

  def prime?(number) do
    sqrt = trunc(:math.sqrt(number))
    divisible_by_another_number = Enum.any?(2..sqrt, fn n -> rem(number, n) == 0 end)
    not divisible_by_another_number
  end
end
