defmodule Protohackers.EchoServerTest do
  use ExUnit.Case, async: true

  @host ~c"localhost"
  @port 5001
  @kilobytes 1024
  @seconds 1000

  describe "echo server" do
    test "echoes binary text back" do
      {:ok, socket} = :gen_tcp.connect(@host, @port, mode: :binary, active: false)
      assert :gen_tcp.send(socket, "yolo") == :ok
      assert :gen_tcp.send(socket, "swag") == :ok

      :gen_tcp.shutdown(socket, :write)

      assert :gen_tcp.recv(socket, 0, 5 * @seconds) == {:ok, "yoloswag"}
    end

    test "errors when input size limit exceeded" do
      {:ok, socket} = :gen_tcp.connect(@host, @port, mode: :binary, active: false)

      # Write 1 bit over the limit
      assert :gen_tcp.send(socket, :binary.copy(".", 100 * @kilobytes + 1)) == :ok

      assert :gen_tcp.recv(socket, 0) == {:error, :closed}
    end

    test "handles multiple concurrent connections" do
      tasks =
        for n <- 1..4 do
          Task.async(fn ->
            {:ok, socket} = :gen_tcp.connect(@host, @port, mode: :binary, active: false)

            assert :gen_tcp.send(socket, "yolo#{n}") == :ok
            assert :gen_tcp.send(socket, "swag#{n}") == :ok

            :gen_tcp.shutdown(socket, :write)

            assert :gen_tcp.recv(socket, 0, 5 * @seconds) == {:ok, "yolo#{n}swag#{n}"}
          end)
        end

      Enum.each(tasks, &Task.await/1)
    end
  end
end
