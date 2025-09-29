defmodule Once.Shared do
  @moduledoc false

  # paddingless url64 en/decoding
  def encode64(value), do: Base.url_encode64(value, padding: false)
  def decode64(value), do: Base.url_decode64(value, padding: false)

  # hex en/decoding
  def encode16(value), do: Base.encode16(value, case: :lower)
  def decode16(value), do: Base.decode16(value, case: :mixed)

  def encode32(value), do: Base.encode32(value, case: :lower, padding: false)
  def decode32(value), do: Base.decode32(value, case: :mixed, padding: false)
end
