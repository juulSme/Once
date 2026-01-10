defmodule Once.Encode do
  @moduledoc false

  # paddingless url64 en/decoding
  @spec encode64(binary()) :: binary()
  def encode64(value), do: Base.url_encode64(value, padding: false)
  @spec decode64(binary()) :: {:ok, binary()} | :error
  def decode64(value), do: Base.url_decode64(value, padding: false)

  # hex en/decoding
  @spec encode16(binary()) :: binary()
  def encode16(value), do: Base.encode16(value, case: :lower)
  @spec decode16(binary()) :: {:ok, binary()} | :error
  def decode16(value), do: Base.decode16(value, case: :mixed)

  @spec encode32(binary()) :: binary()
  def encode32(value), do: Base.hex_encode32(value, case: :lower, padding: false)
  @spec decode32(binary()) :: {:ok, binary()} | :error
  def decode32(value), do: Base.hex_decode32(value, case: :mixed, padding: false)

  if function_exported?(Base, :url_valid64?, 2) do
    @spec valid64?(binary()) :: boolean()
    def valid64?(bin), do: Base.url_valid64?(bin, padding: false)

    @spec valid16?(binary()) :: boolean()
    def valid16?(bin), do: Base.valid16?(bin, case: :mixed)

    @spec valid32?(binary()) :: boolean()
    def valid32?(bin), do: Base.hex_valid32?(bin, case: :mixed, padding: false)
  else
    @spec valid64?(binary()) :: boolean()
    def valid64?(bin), do: match?({:ok, _}, decode64(bin))

    @spec valid16?(binary()) :: boolean()
    def valid16?(bin), do: match?({:ok, _}, decode16(bin))

    @spec valid32?(binary()) :: boolean()
    def valid32?(bin), do: match?({:ok, _}, decode32(bin))
  end
end
