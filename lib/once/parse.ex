defmodule Once.Parse do
  @moduledoc false
  use Once.Constants
  import Once.Encode

  @type id :: Once.Prefix.id()

  @doc """
  Convert a value from format_in to format_out.
  If they are the same format, the format is validated.
  """
  @spec maybe_convert(id(), Once.format(), Once.format()) :: :error | {:ok, id()}
  def maybe_convert(value, format_in, format_out)
  def maybe_convert(value, :raw, :raw), do: {:ok, value}

  def maybe_convert(value, :url64, :url64) do
    if valid64?(value), do: {:ok, value}, else: :error
  end

  def maybe_convert(value, :hex, :hex) do
    if valid16?(value), do: {:ok, value}, else: :error
  end

  def maybe_convert(value, :hex32, :hex32) do
    if valid32?(value), do: {:ok, value}, else: :error
  end

  def maybe_convert(value, format_in, format_out)
      when format_in in @int_formats and format_out in @int_formats do
    convert_int(value, format_out)
  end

  def maybe_convert(value, format_in, format_out) do
    value
    |> to_raw(format_in)
    |> case do
      {:ok, raw} -> {:ok, from_raw(raw, format_out)}
      _ -> :error
    end
  end

  @doc """
  Identify the value's format. All ints are grouped together for convert_int/2 to deal with.
  """
  @spec identify_format(id()) :: Once.format()
  def identify_format(value)
  def identify_format(<<_::88>>), do: :url64
  def identify_format(<<_::64>>), do: :raw
  def identify_format(<<_::128>>), do: :hex
  def identify_format(<<_::104>>), do: :hex32
  def identify_format(int) when is_integer(int), do: :unsigned
  def identify_format(_), do: :error

  @doc """
  Parse value as a numeric string if the second arg is true.
  """
  @spec maybe_parse_num_str(id(), boolean()) :: id()
  def maybe_parse_num_str(value, parse_int_opt)
  def maybe_parse_num_str(value, true) when is_binary(value), do: parse_num_str(value)
  def maybe_parse_num_str(value, _), do: value

  @doc """
  Convert from a raw 8-byte binary to any format.
  """
  @spec from_raw(<<_::64>>, Once.format()) :: id()
  def from_raw(raw, to_format)
  def from_raw(raw, :raw), do: raw
  def from_raw(raw, :url64), do: encode64(raw)
  def from_raw(raw, :hex), do: encode16(raw)
  def from_raw(raw, :hex32), do: encode32(raw)
  def from_raw(<<int::signed-64>>, :signed), do: int
  def from_raw(<<int::unsigned-64>>, :unsigned), do: int

  @doc """
  Convert from any format to a raw 8-byte binary.
  """
  @spec to_raw(id(), Once.format()) :: :error | {:ok, id()}
  def to_raw(value, from_format)
  def to_raw(value, :raw), do: {:ok, value}
  def to_raw(value, :url64), do: decode64(value)
  def to_raw(value, :hex), do: decode16(value)
  def to_raw(value, :hex32), do: decode32(value)

  def to_raw(value, int_format) when int_format in @int_formats do
    case convert_int(value, :unsigned) do
      {:ok, int} -> {:ok, <<int::64>>}
      _ -> :error
    end
  end

  def to_raw(_, :error), do: :error

  ###########
  # Private #
  ###########

  # convert a signed to unsigned int and back
  defp convert_int(int, format)
  defp convert_int(int, _) when int < @signed_min, do: :error
  defp convert_int(int, _) when int > @unsigned_max, do: :error

  defp convert_int(int, :signed) when int > @signed_max, do: {:ok, int - @bigint_size}
  defp convert_int(int, :unsigned) when int < @unsigned_min, do: {:ok, int + @bigint_size}

  defp convert_int(int, _), do: {:ok, int}

  defp parse_num_str(value) do
    try do
      String.to_integer(value)
    rescue
      _ -> :error
    end
  end
end
