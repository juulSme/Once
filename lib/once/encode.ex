defmodule Once.Encode do
  @moduledoc false

  # paddingless url64 en/decoding
  @spec encode64(binary()) :: binary()
  def encode64(value), do: Base.url_encode64(value, padding: false)

  # Rejects values with non-zero trailing bits: 11 chars hold 66 bits for 64 bits of data.
  @spec decode64(binary()) :: {:ok, binary()} | :error
  def decode64(value) do
    if canonical64?(value), do: Base.url_decode64(value, padding: false), else: :error
  end

  defp canonical64?(<<_::binary-10, last>>), do: last in ~c"AEIMQUYcgkosw048"
  defp canonical64?(_), do: false

  # hex en/decoding, lowercase only
  @spec encode16(binary()) :: binary()
  def encode16(value), do: Base.encode16(value, case: :lower)
  @spec decode16(binary()) :: {:ok, binary()} | :error
  def decode16(value), do: Base.decode16(value, case: :lower)

  @spec encode32(binary()) :: binary()
  def encode32(value), do: Base.hex_encode32(value, case: :lower, padding: false)

  # Rejects values with a non-zero trailing bit: 13 chars hold 65 bits for 64 bits of data.
  @spec decode32(binary()) :: {:ok, binary()} | :error
  def decode32(value) do
    if canonical32?(value) do
      Base.hex_decode32(value, case: :lower, padding: false)
    else
      :error
    end
  end

  defp canonical32?(<<_::binary-12, last>>), do: last in ~c"02468acegikmoqsu"
  defp canonical32?(_), do: false

  if function_exported?(Base, :url_valid64?, 2) do
    @spec valid64?(binary()) :: boolean()
    def valid64?(bin), do: canonical64?(bin) and Base.url_valid64?(bin, padding: false)

    @spec valid16?(binary()) :: boolean()
    def valid16?(bin), do: Base.valid16?(bin, case: :lower)

    @spec valid32?(binary()) :: boolean()
    def valid32?(bin) do
      canonical32?(bin) and Base.hex_valid32?(bin, case: :lower, padding: false)
    end
  else
    @spec valid64?(binary()) :: boolean()
    def valid64?(bin), do: match?({:ok, _}, decode64(bin))

    @spec valid16?(binary()) :: boolean()
    def valid16?(bin), do: match?({:ok, _}, decode16(bin))

    @spec valid32?(binary()) :: boolean()
    def valid32?(bin), do: match?({:ok, _}, decode32(bin))
  end
end
