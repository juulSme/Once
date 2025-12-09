defmodule Once.Shared do
  @moduledoc false

  # paddingless url64 en/decoding
  def encode64(value), do: Base.url_encode64(value, padding: false)
  def decode64(value), do: Base.url_decode64(value, padding: false)

  # hex en/decoding
  def encode16(value), do: Base.encode16(value, case: :lower)
  def decode16(value), do: Base.decode16(value, case: :mixed)

  def do_to_format!(format_result, input)
  def do_to_format!({:ok, value}, _input), do: value

  def do_to_format!(_, input) do
    raise ArgumentError, "value could not be parsed: #{inspect(input)}"
  end
end
