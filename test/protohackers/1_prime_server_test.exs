defmodule Protohackers.PrimeServerTest do
  use ExUnit.Case, async: true

  @host ~c"localhost"
  @port 5002
  @seconds 1000

  describe "prime server" do
    test "echoes back JSON only if number is prime" do
      {:ok, socket} = :gen_tcp.connect(@host, @port, mode: :binary, active: false)

      assert :gen_tcp.send(socket, Jason.encode!(%{"method" => "isPrime", "number" => 7}) <> "\n") ==
               :ok

      {:ok, data} = :gen_tcp.recv(socket, 0, 5 * @seconds)
      assert String.ends_with?(data, "\n")
      assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => true}

      assert :gen_tcp.send(
               socket,
               Jason.encode!(%{"method" => "isPrime", "number" => 10}) <> "\n"
             ) == :ok

      {:ok, data} = :gen_tcp.recv(socket, 0, 5 * @seconds)
      assert String.ends_with?(data, "\n")
      assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => false}
    end
  end
end
