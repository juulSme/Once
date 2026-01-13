defmodule Once.Prefix do
  @moduledoc false
  alias Once.Type

  @doc """
  If params.persist_prefix, returns the prefix, else `nil`.
  """
  @spec if_persistent(Type.prefix(), map()) :: Type.prefix()
  def if_persistent(prefix, params) when params.persist_prefix, do: prefix
  def if_persistent(_, _), do: nil

  @doc """
  Prefix the id. If id is an integer, convert it to a numeric string first.
  """
  @spec put(Type.id(), Type.prefix()) :: Type.id()
  def put(id, _prefix = nil), do: id
  def put(id, prefix) when is_binary(id), do: <<prefix::binary, id::binary>>
  def put(id, prefix), do: <<prefix::binary, Integer.to_string(id)::binary>>

  @doc """
  Strip the prefix from the id if both are a binary. The prefix must match.
  """
  @spec strip(Type.id(), Type.prefix()) :: {:ok, Type.id()} | :error
  def strip(id, prefix) when is_binary(id) and is_binary(prefix) do
    case id do
      ^prefix <> value -> {:ok, value}
      _ -> :error
    end
  end

  def strip(id, _), do: {:ok, id}

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
