defmodule Once.Prefixed do
  use Ecto.ParameterizedType
  import Once.Shared

  @type format :: :url64 | :hex

  @type opts :: [
          prefix: binary(),
          no_noncense: module(),
          format: format(),
          get_key: (-> <<_::24>>),
          nonce_type: Once.nonce_type()
        ]

  @default_opts %{no_noncense: Once, nonce_type: :counter, format: :url64}

  #######################
  # Type implementation #
  #######################

  @impl true
  def type(_), do: :string

  @impl true
  @spec init(opts()) :: map()
  def init(opts \\ []) do
    opts |> Enum.into(@default_opts) |> Once.check_nonce_type_option() |> require_prefix()
  end

  @impl true
  def cast(nil, _), do: {:ok, nil}
  def cast(value, params), do: match_prefix(value, params)

  @impl true
  def load(nil, _, _), do: {:ok, nil}
  def load(value, _, params), do: match_prefix(value, params)

  @impl true
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, params), do: match_prefix(value, params)

  @impl true
  def autogenerate(params = %{nonce_type: :counter}) do
    NoNoncense.nonce(params.no_noncense, 64)
    |> to_format(params.format)
    |> prefix(params.prefix)
  end

  def autogenerate(params = %{nonce_type: :sortable}) do
    NoNoncense.sortable_nonce(params.no_noncense, 64)
    |> to_format(params.format)
    |> prefix(params.prefix)
  end

  def autogenerate(params) do
    NoNoncense.encrypted_nonce(params.no_noncense, 64, params.get_key.())
    |> to_format(params.format)
    |> prefix(params.prefix)
  end

  ###########
  # Private #
  ###########

  defp match_prefix(value, %{prefix: prefix}) do
    case value do
      <<^prefix::binary, _::binary>> -> {:ok, value}
      _ -> :error
    end
  end

  defp prefix(nonce, prefix), do: <<prefix::binary, nonce::binary>>

  defp to_format(value, :url64), do: encode64(value)
  defp to_format(value, :hex), do: encode16(value)

  defp require_prefix(params) when is_binary(params.prefix), do: params
  defp require_prefix(_), do: raise(ArgumentError, "prefix required")
end
