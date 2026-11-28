defmodule Once.CreatedAt do
  @moduledoc """
  A read-only Ecto type exposing the generation time of a sortable Once ID.

  Map the field to the same database column as the ID and provide the same
  Once options:

      @once_opts [nonce_type: :sortable]
      schema "posts" do
        field :event_id, Once, @once_opts
        field :event_created_at, Once.CreatedAt,
          @once_opts ++ [
            source: :event_id,
            writable: :never,
            on_writable_violation: :raise
          ]
      end

  Ecto 3.12 or later is recommended: it enforces `writable: :never` for read-only
  schema fields. Older versions ignore the option, so the field works only as long
  as it is never set. The `on_writable_violation` option in the example requires
  Ecto 3.14.1 or later.

  The epoch defaults to the NoNoncense default, 2025-01-01 00:00:00 UTC. If the
  generator uses a different epoch, pass it as `epoch:`, either as a `DateTime`
  with millisecond precision or an integer Unix timestamp in milliseconds. It
  must match the epoch used to generate the IDs.
  The timestamp represents ID generation time, not database insertion time.
  Only sortable IDs are supported; masked sortable IDs are stored unmasked and
  are supported, but exposing their timestamp reveals their generation time.
  Database format and persisted prefix options must match the ID.

  The field is populated when loaded from the database, not automatically when
  the ID is generated or inserted.
  On Postgres, you can set `read_after_writes: true` on the field to have the value available immediately (it uses "RETURNING" so there isn't even an extra read query).
  Schema fields must specify `writable: :never`; use `on_writable_violation: :raise` to reject attempted writes explicitly.
  Use `Once.Query` macros to filter on this field or the original ID field:

      from p in Post,
        where: later_or_at(p.event_created_at, ^start_time) and earlier_than(p.event_created_at, ^end_time)

  Use `at(p.event_created_at, ^timestamp)` to match the timestamp's millisecond.

  The query module's epoch must match this field's epoch. Direct comparisons
  against interpolated timestamps are rejected: comparing a timestamp with the
  underlying ID would not have the expected datetime semantics.
  """

  use Ecto.ParameterizedType
  use Once.Constants
  alias Once.{Parse, Prefix}
  alias Once.Query.Boundary

  @impl true
  def init(opts) do
    if opts[:schema] && opts[:writable] != :never do
      raise ArgumentError, "Once.CreatedAt fields require writable: :never"
    end

    epoch = opts |> Keyword.get(:epoch, @default_epoch) |> Boundary.to_unix_ms!("epoch")
    params = opts |> Keyword.delete(:epoch) |> Once.init()

    if params.nonce_type != :sortable do
      raise ArgumentError, "Once.CreatedAt requires nonce_type: :sortable"
    end

    Map.put(params, :epoch, epoch)
  end

  @impl true
  def type(params), do: Once.type(params)

  @impl true
  def cast(nil, _), do: {:ok, nil}
  def cast(%Boundary{epoch: epoch} = boundary, %{epoch: epoch}), do: {:ok, boundary}
  def cast(%Boundary{}, _), do: raise(ArgumentError, "query epoch does not match field epoch")
  def cast(_, _), do: :error

  @impl true
  def dump(nil, _, _), do: {:ok, nil}

  def dump(%Boundary{} = boundary, dumper, params) do
    with {:ok, boundary} <- cast(boundary, params),
         {:ok, id} <- Boundary.cast(boundary, params) do
      Once.dump(id, dumper, params)
    end
  end

  def dump(_, _, _), do: :error

  @impl true
  def load(nil, _, _), do: {:ok, nil}
  def load(value, _, %{persist_prefix: true}) when not is_binary(value), do: :error

  def load(value, _, params) do
    parse_num? = params.persist_prefix and params.db_format in @int_formats

    with {:ok, value} <- Prefix.strip(value, Prefix.if_persistent(params.prefix, params)),
         {:ok, value} <- Parse.maybe_parse_num_str(value, parse_num?),
         {:ok, raw_nonce} <- to_raw(value, params.db_format) do
      {:ok, NoNoncense.created_at(raw_nonce, params.epoch)}
    else
      _ -> :error
    end
  end

  defp to_raw(value, format) when format in [:signed, :unsigned] and is_integer(value),
    do: Parse.to_raw(value, format)

  defp to_raw(value, format)
       when format in [:raw, :hex, :hex32, :url64] and is_binary(value),
       do: Parse.to_raw(value, format)

  defp to_raw(_, _), do: :error
end
