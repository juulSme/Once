defmodule Once.Prefix do
  @moduledoc false

  @type id :: binary() | integer()
  @type prefix :: binary() | nil

  @spec if_persistent(prefix(), map()) :: prefix()
  def if_persistent(prefix, params) when params.persist_prefix, do: prefix
  def if_persistent(_, _), do: nil

  @spec put(id(), prefix) :: id()
  def put(id, _prefix = nil), do: id
  def put(id, prefix) when is_binary(id), do: <<prefix::binary, id::binary>>
  def put(id, prefix), do: <<prefix::binary, Integer.to_string(id)::binary>>

  @spec strip(id(), prefix()) :: :error | {:ok, id()}
  def strip(prefixed_id, prefix) when is_binary(prefixed_id) and is_binary(prefix) do
    case prefixed_id do
      ^prefix <> value -> {:ok, value}
      _ -> :error
    end
  end

  def strip(prefixed_id, _), do: {:ok, prefixed_id}

  @doc """
  This macro strips a non-nil prefix from value, processes it and puts a non-nil prefix back. The stripped value is unhygenically made available to block code as `stripped`.
  """
  defmacro map_prefixed(value, strip_prefix, put_prefix, do: process) do
    quote do
      with {:ok, var!(stripped)} <-
             unquote(__MODULE__).strip(unquote(value), unquote(strip_prefix)),
           {:ok, processed} <- unquote(process) do
        {:ok, unquote(__MODULE__).put(processed, unquote(put_prefix))}
      end
    end
  end
end
