defmodule Once.Prefixed do
  @deprecated "Use Once with options :prefix and :persist_prefix instead"

  @moduledoc """
  > #### DEPRECATED! Use `Once` directly {: .warning}
  >
  > This module exists for backward compatibility. New code should use `Once` directly with the `:prefix` option instead. All functionality is identical.

  A wrapper for `Once` that adds a prefix to IDs. This module is soft-deprecated in favor of using `Once` with the `:prefix` option.

  For complete documentation on prefixed IDs, including prefix persistence, format conversion, and examples, see the [Prefixed IDs section](`m:Once#module-prefixed-ids`) in the `Once` module documentation.

  ## Usage

  **Recommended approach** - use `Once` directly:

      schema "users" do
        field :id, Once, prefix: "usr_", autogenerate: true
        field :external_id, Once, prefix: "usr_"
      end

  Legacy approach (for backward compatibility only):

      schema "users" do
        field :id, Prefixed, prefix: "usr_", autogenerate: true
        field :external_id, Prefixed, prefix: "usr_"
      end
  """
  use Ecto.ParameterizedType

  #######################
  # Type implementation #
  #######################

  @impl true
  defdelegate type(params), to: Once

  @impl true
  @spec init([Once.init_opt()]) :: map()
  @deprecated "Use Once with options :prefix and :persist_prefix instead"
  defdelegate init(opts \\ []), to: Once

  @impl true
  @deprecated "Use Once with options :prefix and :persist_prefix instead"
  defdelegate cast(value, params), to: Once

  @impl true
  @deprecated "Use Once with options :prefix and :persist_prefix instead"
  defdelegate load(value, something, params), to: Once

  @impl true
  @deprecated "Use Once with options :prefix and :persist_prefix instead"
  defdelegate dump(value, something, params), to: Once

  @impl true
  @deprecated "Use Once with options :prefix and :persist_prefix instead"
  defdelegate autogenerate(params), to: Once

  @doc """
  Transform a prefixed ID between different formats while preserving the prefix.

  This works like `Once.to_format/3` but handles the prefix automatically. The prefix must match the second argument.

  Note that this function does not return integers when converting to `:signed` or `:unsigned`, but only numeric strings like "prfx_123".

  ## Options

  #{Once.to_format_opts_docs()}

  ## Examples

      iex> id = "prfx_18446744073709551615"
      iex> {:ok, "prfx___________8" = id}                    = Prefixed.to_format(id, "prfx_", :url64, parse_int: true)
      iex> {:ok, <<"prfx_", 18446744073709551615::64>> = id} = Prefixed.to_format(id, "prfx_", :raw)
      iex> {:ok, "prfx_-1" = id}                             = Prefixed.to_format(id, "prfx_", :signed)
      iex> {:ok, "prfx_ffffffffffffffff" = id}               = Prefixed.to_format(id, "prfx_", :hex, parse_int: true)
      iex> {:ok, "prfx_vvvvvvvvvvvvu" = id}                  = Prefixed.to_format(id, "prfx_", :hex32)
      iex> {:ok, "prfx_18446744073709551615"}                = Prefixed.to_format(id, "prfx_", :unsigned)

      iex> Prefixed.to_format("wrong_AAAAAAAAAAA", "usr_", :unsigned)
      :error
      iex> Prefixed.to_format("AAAAAAAAAAA", "usr_", :unsigned)
      :error
  """
  @spec to_format(binary(), binary(), Once.format(), [Once.to_format_opt()]) ::
          {:ok, binary()} | :error
  @deprecated "Use Once.to_format/3 with option :prefix instead"
  def to_format(value, prefix, format, opts \\ []) do
    Once.to_format(value, format, Keyword.put(opts, :prefix, prefix))
  end

  @doc """
  Same as `to_format/4` but raises on error.

  ## Examples

      iex> "usr_AAAAAAAAAAA"
      ...> |> Prefixed.to_format!("usr_", :unsigned)
      ...> |> Prefixed.to_format!("usr_", :hex, parse_int: true)
      ...> |> Prefixed.to_format!("usr_", :signed)
      ...> |> Prefixed.to_format!("usr_", :raw, parse_int: true)
      ...> |> Prefixed.to_format!("usr_", :hex32)
      ...> |> Prefixed.to_format!("usr_", :url64)
      "usr_AAAAAAAAAAA"

      iex> Prefixed.to_format!("usr_AAAAAAAAAAA", "wrong_", :signed)
      ** (ArgumentError) value could not be parsed: "usr_AAAAAAAAAAA"

      iex> Prefixed.to_format!("AAAAAAAAAAA", "usr_", :signed)
      ** (ArgumentError) value could not be parsed: "AAAAAAAAAAA"
  """
  @deprecated "Use Once.to_format!/3 with option :prefix instead"
  @spec to_format!(binary(), binary(), Once.format(), [Once.to_format_opt()]) :: binary()
  def to_format!(value, prefix, format, opts \\ []) do
    Once.to_format!(value, format, Keyword.put(opts, :prefix, prefix))
  end
end
