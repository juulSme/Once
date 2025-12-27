defmodule Once.Prefixed do
  @moduledoc """
  A Once with a prefix, for example "prfx_AV7m9gAAAAU". The prefix is not persisted and only exists in Elixir, so that the stored ID size is still 64 bits and can still be an integer.


  """
  use Ecto.ParameterizedType
  import Once.Shared

  @type opt :: {:prefix, binary()}
  @type opts :: [Once.opt() | opt()]

  #######################
  # Type implementation #
  #######################

  @impl true
  defdelegate type(params), to: Once

  @impl true
  def init(opts \\ []), do: opts |> Once.init() |> require_prefix()

  @impl true
  def cast(nil, _), do: {:ok, nil}

  def cast(value, params) do
    case defix(value, params.prefix) do
      {:ok, value} -> Once.cast(value, params)
      error -> error
    end
  end

  @impl true
  def load(nil, _, _), do: {:ok, nil}

  def load(value, _, params) do
    case Once.load(value, nil, params) do
      {:ok, value} -> prefix(value, params.prefix)
      error -> error
    end
  end

  @impl true
  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, _, params) do
    case defix(value, params.prefix) do
      {:ok, value} -> Once.dump(value, nil, params)
      error -> error
    end
  end

  @impl true
  def autogenerate(params), do: params |> Once.autogenerate() |> prefix(params.prefix)

  def to_format(value, format, opts \\ []) do
    with prefix <- Keyword.fetch!(opts, :prefix),
         {:ok, defixed} <- defix(value, prefix),
         {:ok, converted} <- Once.to_format(defixed, format, opts) do
      {:ok, prefix(converted, prefix)}
    else
      _ -> :error
    end
  end

  def to_format!(value, format, opts \\ []) do
    to_format(value, format, opts) |> do_to_format!(value)
  end

  ###########
  # Private #
  ###########

  defp prefix(nonce, prefix) when is_integer(nonce) do
    <<prefix::binary, Integer.to_string(nonce)::binary>>
  end

  defp prefix(nonce, prefix), do: <<prefix::binary, nonce::binary>>

  defp defix(prefixed, prefix) do
    case prefixed do
      ^prefix <> value -> {:ok, value}
      _ -> :error
    end
  end

  defp require_prefix(params) when is_binary(params.prefix), do: params
  defp require_prefix(_), do: raise(ArgumentError, "you must provide :prefix")
end
