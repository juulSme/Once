defmodule Once.Pad do
  @moduledoc false

  @doc """
  Formats an integer with leading zeros. The width is a minimum for the digits;
  a negative sign is prepended separately.

      iex> Once.Pad.zero_lpad_int(0, 2)
      "00"
      iex> for width <- 1..6, do: Once.Pad.zero_lpad_int(42, width)
      ["42", "42", "042", "0042", "00042", "000042"]
      iex> for width <- 1..6, do: Once.Pad.zero_lpad_int(-42, width)
      ["-42", "-42", "-042", "-0042", "-00042", "-000042"]
  """
  def zero_lpad_int(value, width) when value >= 0 do
    value = Integer.to_string(value)

    # we can get away with byte_size for a numeric string, which only contains ASCII characters
    case width - byte_size(value) do
      n when n > 3 -> :binary.copy("0", n) <> value
      3 -> "000" <> value
      2 -> "00" <> value
      1 -> "0" <> value
      _ -> value
    end
  end

  def zero_lpad_int(value, width), do: "-" <> (value |> abs() |> zero_lpad_int(width))
end
