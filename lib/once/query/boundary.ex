defmodule Once.Query.Boundary do
  @moduledoc false
  alias Once.{Parse, Prefix}

  defstruct [:unix_ms, :epoch, :offset]

  @signed_ts_limit 2 ** 41
  @unsigned_ts_limit 2 ** 42

  def new(timestamp, epoch, offset) do
    %__MODULE__{unix_ms: to_unix_ms!(timestamp, "timestamp"), epoch: epoch, offset: offset}
  end

  def cast(%__MODULE__{} = boundary, params) do
    if params.nonce_type != :sortable do
      raise ArgumentError, "field must use nonce_type: :sortable"
    end

    if params.db_format not in [:signed, :unsigned, :raw, :hex, :hex32] do
      raise ArgumentError,
            "database format #{inspect(params.db_format)} does not sort by timestamp"
    end

    timestamp = boundary.unix_ms - boundary.epoch + boundary.offset
    limit = if params.db_format == :signed, do: @signed_ts_limit, else: @unsigned_ts_limit

    if timestamp < 0 or timestamp >= limit do
      raise ArgumentError,
            "timestamp is outside the sortable range for #{inspect(params.db_format)}"
    end

    raw = <<timestamp::42, 0::22>>
    raw = if params.mask, do: NoNoncense.encrypt(params.no_noncense, raw), else: raw
    {:ok, raw |> Parse.from_raw(params.ex_format) |> Prefix.put(params.prefix)}
  end

  def to_unix_ms!(unix_ms, _) when is_integer(unix_ms), do: unix_ms

  def to_unix_ms!(dt = %DateTime{microsecond: {usec, _}}, _) when rem(usec, 1_000) == 0 do
    DateTime.to_unix(dt, :millisecond)
  end

  def to_unix_ms!(%DateTime{}, _),
    do: raise(ArgumentError, "timestamp must have millisecond precision")

  def to_unix_ms!(_, name),
    do: raise(ArgumentError, "#{name} must be a DateTime or Unix millisecond integer")
end
