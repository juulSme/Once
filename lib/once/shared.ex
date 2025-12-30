defmodule Once.Shared do
  @moduledoc false

  # paddingless url64 en/decoding
  def encode64(value), do: Base.url_encode64(value, padding: false)
  def decode64(value), do: Base.url_decode64(value, padding: false)

  # hex en/decoding
  def encode16(value), do: Base.encode16(value, case: :lower)
  def decode16(value), do: Base.decode16(value, case: :mixed)

  def encode32(value), do: Base.hex_encode32(value, case: :lower, padding: false)
  def decode32(value), do: Base.hex_decode32(value, case: :mixed, padding: false)

  def do_to_format!(format_result, input)
  def do_to_format!({:ok, value}, _input), do: value

  def do_to_format!(_, input) do
    raise ArgumentError, "value could not be parsed: #{inspect(input)}"
  end

  if function_exported?(Base, :url_valid64?, 2) do
    def valid64?(bin), do: Base.url_valid64?(bin, padding: false)
    def valid16?(bin), do: Base.valid16?(bin, case: :mixed)
    def valid32?(bin), do: Base.hex_valid32?(bin, case: :mixed, padding: false)
  else
    def valid64?(bin), do: match?({:ok, _}, decode64(bin))
    def valid16?(bin), do: match?({:ok, _}, decode16(bin))
    def valid32?(bin), do: match?({:ok, _}, decode32(bin))
  end
end
