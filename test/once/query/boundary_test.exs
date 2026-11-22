defmodule Once.Query.BoundaryTest do
  use ExUnit.Case, async: true

  alias Once.Query.Boundary

  test "rejects invalid and sub-millisecond inputs" do
    assert_raise ArgumentError, ~r/timestamp must have millisecond precision/, fn ->
      Boundary.to_unix_ms!(~U[2020-01-01 00:00:00.000001Z], "epoch")
    end

    assert_raise ArgumentError,
                 ~r/timestamp must be a DateTime or Unix millisecond integer/,
                 fn ->
                   Boundary.new("10", 1_577_836_800_000, 0)
                 end
  end

  test "rejects fields that do not support time-ordered queries" do
    boundary = Boundary.new(~U[2020-01-01 00:00:00.010Z], 1_577_836_800_000, 0)

    for opts <- [
          [nonce_type: :counter],
          [nonce_type: :encrypted],
          [nonce_type: :sortable, db_format: :url64]
        ] do
      assert_raise ArgumentError, fn -> Boundary.cast(boundary, Once.init(opts)) end
    end
  end

  test "rejects an upper boundary beyond the signed range" do
    epoch = 1_577_836_800_000
    boundary = Boundary.new(epoch + 2 ** 41 - 1, epoch, 1)

    assert_raise ArgumentError, ~r/outside the sortable range/, fn ->
      Boundary.cast(boundary, Once.init(nonce_type: :sortable))
    end
  end
end
