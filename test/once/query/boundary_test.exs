defmodule Once.Query.BoundaryTest do
  use ExUnit.Case, async: true

  alias Once.Query.Boundary

  test "renders boundaries for inspection and string interpolation" do
    epoch = 1_577_836_800_000

    for {bound, description} <- [lower: "first", upper: "last"] do
      boundary = Boundary.new(epoch + 10, epoch, bound)

      expected =
        "#Once.Query.Boundary<#{description} id of ~U[2020-01-01 00:00:00.010Z]>"

      assert inspect(boundary) == expected
      assert inspect([boundary]) == "[#{expected}]"
      assert "#{boundary}" == "#{description} id of 2020-01-01T00:00:00.010Z"
    end
  end

  test "renders timestamps outside DateTime's range as Unix milliseconds" do
    boundary = Boundary.new(999_999_999_999_999_999, 0, :lower)

    assert inspect(boundary) ==
             "#Once.Query.Boundary<first id of {:unix_ms, 999999999999999999}>"

    assert to_string(boundary) ==
             "first id of 999999999999999999 milliseconds since the Unix epoch (outside DateTime range)"
  end

  if function_exported?(Inspect.Algebra, :to_doc_with_opts, 2) do
    test "propagates updated inspection options" do
      inspect_fun = fn _value, opts ->
        count = Keyword.get(opts.custom_options, :count, 0)
        {"value", %{opts | custom_options: [count: count + 1]}}
      end

      opts = Inspect.Opts.new(inspect_fun: inspect_fun)
      boundary = Boundary.new(10, 0, :lower)

      assert {doc, %Inspect.Opts{custom_options: [count: 1]}} = Inspect.inspect(boundary, opts)

      assert IO.iodata_to_binary(Inspect.Algebra.format(doc, 80)) ==
               "#Once.Query.Boundary<first id of value>"
    end
  end

  test "rejects invalid and sub-millisecond inputs" do
    assert_raise ArgumentError, ~r/timestamp must have millisecond precision/, fn ->
      Boundary.to_unix_ms!(~U[2020-01-01 00:00:00.000001Z], "epoch")
    end

    assert_raise ArgumentError,
                 ~r/timestamp must be a DateTime or Unix millisecond integer/,
                 fn ->
                   Boundary.new("10", 1_577_836_800_000, :lower)
                 end
  end

  test "rejects fields that do not support time-ordered queries" do
    boundary = Boundary.new(~U[2020-01-01 00:00:00.010Z], 1_577_836_800_000, :lower)

    for opts <- [
          [nonce_type: :counter],
          [nonce_type: :encrypted],
          [nonce_type: :sortable, db_format: :url64]
        ] do
      assert_raise ArgumentError, fn -> Boundary.cast(boundary, Once.init(opts)) end
    end
  end

  test "supports the final millisecond and rejects timestamps outside each format's range" do
    epoch = 1_577_836_800_000

    for {format, timestamp_bits} <- [signed: 41, unsigned: 42, raw: 42, hex: 42, hex32: 42] do
      params = Once.init(nonce_type: :sortable, db_format: format)
      last_timestamp = 2 ** timestamp_bits - 1
      boundary = Boundary.new(epoch + last_timestamp, epoch, :upper)

      assert {:ok, id} = Boundary.cast(boundary, params)
      assert Once.to_format!(id, :raw) == <<last_timestamp::42, 2 ** 22 - 1::22>>

      for timestamp <- [epoch - 1, epoch + last_timestamp + 1], bound <- [:lower, :upper] do
        boundary = Boundary.new(timestamp, epoch, bound)

        assert_raise ArgumentError, ~r/outside the sortable range/, fn ->
          Boundary.cast(boundary, params)
        end
      end
    end
  end

  test "preserves integer timestamp limits with persisted prefixes" do
    epoch = 1_577_836_800_000

    for {format, bits} <- [{:signed, 41}, {:unsigned, 42}] do
      params =
        Once.init(nonce_type: :sortable, db_format: format, prefix: "id_", persist_prefix: true)

      last_timestamp = 2 ** bits - 1
      last_boundary = Boundary.new(epoch + last_timestamp, epoch, :upper)
      assert {:ok, id} = Boundary.cast(last_boundary, params)
      assert {:ok, "id_" <> stored} = Once.dump(id, nil, params)
      assert byte_size(stored) == 20
      assert {:ok, first_id} = Boundary.cast(Boundary.new(epoch, epoch, :lower), params)
      assert {:ok, first_stored} = Once.dump(first_id, nil, params)
      assert first_stored < "id_" <> stored

      values =
        for timestamp <- [0, 1, 10, 100, last_timestamp] do
          {:ok, id} = Boundary.cast(Boundary.new(epoch + timestamp, epoch, :lower), params)
          {:ok, stored} = Once.dump(id, nil, params)
          stored
        end

      assert values == Enum.sort(values)

      assert_raise ArgumentError, ~r/outside the sortable range/, fn ->
        Boundary.cast(Boundary.new(epoch + last_timestamp + 1, epoch, :lower), params)
      end
    end
  end
end
