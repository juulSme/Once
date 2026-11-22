defmodule Once.Query do
  @moduledoc """
  Ecto query expression macros for the generation time of sortable Once IDs.

  Define a module with the epoch used by your NoNoncense instance, expressed
  as Unix milliseconds or a millisecond-precision `DateTime`, and import it where
  you build queries:

      defmodule MyApp.IDQuery do
        use Once.Query, epoch: 1_735_689_600_000
      end

      import Ecto.Query
      import MyApp.IDQuery

      from p in Post, where: gte(p.id, ^start_time) and lt(p.id, ^end_time)
      from p in Post, where: gte(p.id, ^timestamp) and lte(p.id, ^timestamp)

  The macros accept `DateTime` values or integer Unix milliseconds interpolated
  with Ecto's `^` syntax. DateTimes must not have a sub-millisecond component.
  `gt/2` and `lte/2` provide exclusive lower and inclusive upper
  bounds, respectively.

  In the comparisons below, `id` means the ID's generation timestamp, not its
  numeric value.

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

  @lt_doc "Matches IDs generated strictly before the timestamp: `id < timestamp`."
  @gte_doc "Matches IDs generated at or after the timestamp: `id >= timestamp`."
  @gt_doc "Matches IDs generated strictly after the timestamp: `id > timestamp`."
  @lte_doc "Matches IDs generated at or before the timestamp: `id <= timestamp`."

  @doc @lt_doc
  @macrocallback lt(field :: Macro.t(), timestamp :: Macro.t()) :: Macro.t()

  @doc @gte_doc
  @macrocallback gte(field :: Macro.t(), timestamp :: Macro.t()) :: Macro.t()

  @doc @gt_doc
  @macrocallback gt(field :: Macro.t(), timestamp :: Macro.t()) :: Macro.t()

  @doc @lte_doc
  @macrocallback lte(field :: Macro.t(), timestamp :: Macro.t()) :: Macro.t()

  defmacro __using__(opts) do
    epoch = Keyword.fetch!(opts, :epoch)

    quote do
      @behaviour Once.Query
      @once_query_epoch Once.Query.Boundary.to_unix_ms!(unquote(epoch), "epoch")

      @doc unquote(@lt_doc)
      @impl true
      defmacro lt(field, timestamp) do
        Once.Query.build(:lt, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@gte_doc)
      @impl true
      defmacro gte(field, timestamp) do
        Once.Query.build(:gte, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@gt_doc)
      @impl true
      defmacro gt(field, timestamp) do
        Once.Query.build(:gt, field, timestamp, @once_query_epoch)
      end

      @doc unquote(@lte_doc)
      @impl true
      defmacro lte(field, timestamp) do
        Once.Query.build(:lte, field, timestamp, @once_query_epoch)
      end
    end
  end

  @doc false
  def build(operation, field, {:^, _, [timestamp]}, epoch) do
    lower = boundary_ast(timestamp, epoch, 0)
    upper = boundary_ast(timestamp, epoch, 1)

    case operation do
      :lt -> quote do: unquote(field) < unquote(lower)
      :gte -> quote do: unquote(field) >= unquote(lower)
      :gt -> quote do: unquote(field) >= unquote(upper)
      :lte -> quote do: unquote(field) < unquote(upper)
    end
  end

  def build(_, _, _, _) do
    raise ArgumentError, "timestamp must be interpolated with ^"
  end

  defp boundary_ast(timestamp, epoch, offset) do
    quote do
      ^Once.Query.Boundary.new(unquote(timestamp), unquote(epoch), unquote(offset))
    end
  end
end
