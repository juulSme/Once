defmodule Once.Mask do
  @moduledoc false
  alias Once.{Type, Parse}

  @doc """
  Convert an unmasked value to a masked format.
  """
  @spec to_masked_format(Type.id(), module(), Once.format(), boolean()) ::
          {:ok, Type.id()} | :error
  def to_masked_format(value, no_noncense, format_out, parse_num?),
    do: do_format(value, no_noncense, format_out, parse_num?, true)

  @doc """
  Convert a masked value to an unmasked format.
  """
  @spec to_unmasked_format(Type.id(), module(), Once.format(), boolean()) ::
          {:ok, Type.id()} | :error
  def to_unmasked_format(value, no_noncense, format_out, parse_num?),
    do: do_format(value, no_noncense, format_out, parse_num?, false)

  ###########
  # Private #
  ###########

  defp do_format(value, no_noncense, format_out, parse_num?, mask?) do
    with {:ok, parsed} <- Parse.maybe_parse_num_str(value, parse_num?),
         {:ok, format_in} <- Parse.identify_format(parsed),
         {:ok, raw} <- Parse.to_raw(parsed, format_in) do
      {:ok, mask(raw, no_noncense, mask?) |> Parse.from_raw(format_out)}
    end
  end

  @compile {:inline, mask: 3}
  defp mask(value, no_noncense, mask?)
  defp mask(value, no_noncense, true), do: NoNoncense.encrypt(no_noncense, value)
  defp mask(value, no_noncense, _), do: NoNoncense.decrypt(no_noncense, value)
end
