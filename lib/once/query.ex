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

      from p in Post, where: since(p.id, ^start_time) and before(p.id, ^end_time)
      from p in Post, where: since(p.id, ^timestamp) and through(p.id, ^timestamp)

  The macros accept `DateTime` values or integer Unix milliseconds interpolated
  with Ecto's `^` syntax. DateTimes must not have a sub-millisecond component.
  `after_time/2` and `through/2` provide exclusive lower and inclusive upper
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

  defmacro __using__(opts) do
    epoch = Keyword.fetch!(opts, :epoch)

    quote do
      @once_query_epoch Once.Query.Boundary.to_unix_ms!(unquote(epoch), "epoch")

      @doc "Matches IDs generated strictly before the timestamp: `id < timestamp`."
      defmacro before(field, timestamp) do
        Once.Query.build(:before, field, timestamp, @once_query_epoch)
      end

      @doc "Matches IDs generated at or after the timestamp: `id >= timestamp`."
      defmacro since(field, timestamp) do
        Once.Query.build(:since, field, timestamp, @once_query_epoch)
      end

      @doc "Matches IDs generated strictly after the timestamp: `id > timestamp`."
      defmacro after_time(field, timestamp) do
        Once.Query.build(:after_time, field, timestamp, @once_query_epoch)
      end

      @doc "Matches IDs generated at or before the timestamp: `id <= timestamp`."
      defmacro through(field, timestamp) do
        Once.Query.build(:through, field, timestamp, @once_query_epoch)
      end
    end
  end

  @doc false
  def build(operation, field, {:^, _, [timestamp]}, epoch) do
    lower = boundary_ast(timestamp, epoch, 0)
    upper = boundary_ast(timestamp, epoch, 1)

    case operation do
      :before -> quote do: unquote(field) < unquote(lower)
      :since -> quote do: unquote(field) >= unquote(lower)
      :after_time -> quote do: unquote(field) >= unquote(upper)
      :through -> quote do: unquote(field) < unquote(upper)
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
