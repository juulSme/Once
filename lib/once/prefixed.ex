defmodule Once.Prefixed do
  @moduledoc """
  A Once with a prefix, for example "prfx_AV7m9gAAAAU". The prefix is not persisted and only exists in Elixir, so that the stored ID size is still 64 bits and can still be an integer.


  """
  use Ecto.ParameterizedType
  import Once.Shared

  @type opt :: Once.opt() | {:prefix, binary()} | {:persist_prefix, boolean()}
  @type opts :: [opt()]

  @default_opts %{persist_prefix: false}

  #######################
  # Type implementation #
  #######################

  @impl true
  defdelegate type(params), to: Once

  @impl true
  def init(opts \\ []) do
    opts = opts |> Once.init() |> Enum.into(@default_opts)

    if not is_binary(opts[:prefix]) do
      raise ArgumentError, "option :prefix is required"
    end

    if opts.persist_prefix and opts.db_format in [:signed, :unsigned] do
      raise ArgumentError, "option :persist_prefix requires db_format :raw, :hex or :url64"
    end

    opts
  end

  @impl true
  def cast(nil, _), do: {:ok, nil}

  def cast(value, params = %{prefix: prefix}) do
    with {:ok, stripped} <- strip(value, prefix),
         {:ok, casted} <- Once.cast(stripped, params) do
      prefixed = if stripped == casted, do: value, else: prefix(casted, prefix)
      {:ok, prefixed}
    end
  end

  @impl true
  def load(nil, _, _), do: {:ok, nil}

  def load(value, _, params = %{prefix: prefix}) do
    with {:ok, stripped} <- maybe_strip(value, prefix, params),
         {:ok, loaded} <- Once.load(stripped, nil, params) do
      {:ok, prefix(loaded, prefix)}
    end
  end

  @impl true
  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, _, params = %{prefix: prefix}) do
    case strip(value, prefix) do
      {:ok, value} -> Once.dump(value, nil, params) |> maybe_prefix(prefix, params)
      error -> error
    end
  end

  @impl true
  def autogenerate(params), do: params |> Once.autogenerate() |> prefix(params.prefix)

  def to_format(value, prefix, format, opts \\ []) do
    with {:ok, stripped} <- strip(value, prefix),
         {:ok, converted} <- Once.to_format(stripped, format, opts) do
      prefixed = if stripped == converted, do: value, else: prefix(converted, prefix)
      {:ok, prefixed}
    else
      _ -> :error
    end
  end

  def to_format!(value, prefix, format, opts \\ []) do
    to_format(value, prefix, format, opts) |> do_to_format!(value)
  end

  ###########
  # Private #
  ###########

  defp prefix(nonce, prefix) when is_binary(nonce), do: <<prefix::binary, nonce::binary>>
  defp prefix(nonce, prefix), do: nonce |> Integer.to_string() |> prefix(prefix)

  # defp prefix(original, stripped, casted, prefix)
  # defp prefix(original, stripped, casted, _) when stripped == casted, do: original
  # defp prefix(_, _stripped, casted, prefix), do: prefix(casted, prefix)

  defp maybe_prefix(<<nonce::binary>>, prefix, %{persist_prefix: true}), do: prefix(nonce, prefix)
  defp maybe_prefix({:ok, nonce}, prefix, params), do: {:ok, maybe_prefix(nonce, prefix, params)}
  defp maybe_prefix(nonce, _, _), do: nonce

  defp strip(prefixed, prefix) do
    case prefixed do
      ^prefix <> value -> {:ok, value}
      _ -> :error
    end
  end

  defp maybe_strip(<<nonce::binary>>, prefix, %{persist_prefix: true}), do: strip(nonce, prefix)
  defp maybe_strip(nonce, _, _), do: {:ok, nonce}
end
