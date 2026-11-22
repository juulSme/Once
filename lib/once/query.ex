defmodule Once.Query do
  @moduledoc """
  Ecto query expression macros for the generation time of sortable Once IDs.

  ## Default epoch

  Import `Once.Query` to use the NoNoncense default epoch, 2025-01-01 00:00:00 UTC:

      import Ecto.Query
      import Once.Query
      from p in Post, where: gte(p.id, ^start_time) and lt(p.id, ^end_time)
      from p in Post, where: eq(p.id, ^timestamp)

  ## Custom epoch

  If your instance uses a different epoch, define and import a query module:

      defmodule MyApp.IDQuery do
        use Once.Query, epoch: ~U[2020-01-01 00:00:00Z]
      end

      import MyApp.IDQuery
      from p in Post, where: gte(p.id, ^start_time)

  The epoch can be Unix milliseconds or a millisecond-precision `DateTime`.

  The macros accept `DateTime` values or integer Unix milliseconds interpolated
  with Ecto's `^` syntax. DateTimes must not have a sub-millisecond component.

  These macros also work with joined schema bindings. The field must be a `Once`
  or `Once.CreatedAt` type configured with `nonce_type: :sortable`; masked IDs
  are supported. For `Once.CreatedAt` the field's epoch must match the query
  module's epoch. The database format must be `:signed`, `:unsigned`, `:raw`, `:hex`, or `:hex32`,
  and text and binary columns must use bytewise ordering. Signed IDs must remain
  in the first half of their timestamp range. All IDs in the field must use the
  configured epoch, which is not inferred or checked against the generator.

  A timestamp requiring a boundary outside the supported nonce range is rejected,
  including the upper boundary of the last representable millisecond.
  """

  use Once.Constants

  @lt_doc "Matches IDs generated strictly before the timestamp: `id-created-at < timestamp`."
  @gte_doc "Matches IDs generated at or after the timestamp: `id-created-at >= timestamp`."
  @gt_doc "Matches IDs generated strictly after the timestamp: `id-created-at > timestamp`."
  @lte_doc "Matches IDs generated at or before the timestamp: `id-created-at <= timestamp`."
  @eq_doc """
  Matches IDs generated in the timestamp's millisecond: `id-created-at == timestamp`.

  The interpolated timestamp is used for both bounds of the range, so it must be a
  variable, literal, module attribute, or field access on a variable; any other
  expression is rejected at compile time. Bind it to a variable first:

      now = DateTime.utc_now()
      where(query, [r], eq(r.id, ^now))
  """

  @doc @lt_doc
  defmacro lt(field, timestamp), do: build(:lt, field, timestamp, @default_epoch)

  @doc @gte_doc
  defmacro gte(field, timestamp), do: build(:gte, field, timestamp, @default_epoch)

  @doc @gt_doc
  defmacro gt(field, timestamp), do: build(:gt, field, timestamp, @default_epoch)

  @doc @lte_doc
  defmacro lte(field, timestamp), do: build(:lte, field, timestamp, @default_epoch)

  @doc @eq_doc
  defmacro eq(field, timestamp), do: build(:eq, field, timestamp, @default_epoch)

  defmacro __using__(opts) do
    epoch = Keyword.get(opts, :epoch, @default_epoch)

    quote do
      @once_query_epoch Once.Query.Boundary.to_unix_ms!(unquote(epoch), "epoch")

      @doc unquote(@lt_doc)
      defmacro lt(field, timestamp) do
        Once.Query.build(:lt, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@gte_doc)
      defmacro gte(field, timestamp) do
        Once.Query.build(:gte, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@gt_doc)
      defmacro gt(field, timestamp) do
        Once.Query.build(:gt, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@lte_doc)
      defmacro lte(field, timestamp) do
        Once.Query.build(:lte, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@eq_doc)
      defmacro eq(field, timestamp) do
        Once.Query.build(:eq, field, timestamp, @once_query_epoch)
      end
    end
  end

  @doc false
  def build(operation, field, {:^, _, [timestamp]}, epoch) do
    if operation == :eq and not simple?(timestamp) do
      raise ArgumentError,
            "eq/2 interpolates the timestamp twice, so it must be a variable, literal, " <>
              "module attribute or field access; bind other expressions to a variable first"
    end

    lower = boundary_ast(timestamp, epoch, 0)
    upper = boundary_ast(timestamp, epoch, 1)

    case operation do
      :lt -> quote do: unquote(field) < unquote(lower)
      :gte -> quote do: unquote(field) >= unquote(lower)
      :gt -> quote do: unquote(field) >= unquote(upper)
      :lte -> quote do: unquote(field) < unquote(upper)
      :eq -> quote do: unquote(field) >= unquote(lower) and unquote(field) < unquote(upper)
    end
  end

  def build(_, _, _, _) do
    raise ArgumentError, "timestamp must be interpolated with ^"
  end

  defp simple?(timestamp) when is_integer(timestamp), do: true
  defp simple?({name, _, context}) when is_atom(name) and is_atom(context), do: true
  defp simple?({:@, _, [{name, _, context}]}) when is_atom(name) and is_atom(context), do: true
  defp simple?({sigil, _, [{:<<>>, _, _}, _]}) when sigil in [:sigil_U, :sigil_u], do: true

  defp simple?({{:., _, [{name, _, context}, key]}, meta, []})
       when is_atom(name) and is_atom(context) and is_atom(key),
       do: Keyword.get(meta, :no_parens, false)

  defp simple?(_), do: false

  defp boundary_ast(timestamp, epoch, offset) do
    quote do
      ^Once.Query.Boundary.new(unquote(timestamp), unquote(epoch), unquote(offset))
    end
  end
end
