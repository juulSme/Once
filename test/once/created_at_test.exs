defmodule Once.CreatedAtTest do
  use ExUnit.Case, async: true

  @epoch ~U[2025-01-01 00:00:00Z]

  test "loads sortable IDs from each database format" do
    for format <- [:signed, :unsigned, :raw, :hex, :hex32, :url64],
        timestamp <- [10, 2 ** 41] do
      raw = <<timestamp::42, 3::9, 7::13>>
      expected = DateTime.add(@epoch, timestamp, :millisecond)
      params = Once.CreatedAt.init(epoch: @epoch, nonce_type: :sortable, db_format: format)
      value = Once.to_format!(raw, format)
      assert {:ok, ^expected} = Once.CreatedAt.load(value, nil, params)
    end
  end

  test "loads persisted prefixes and masked IDs from their stored plaintext" do
    params =
      Once.CreatedAt.init(
        epoch: @epoch,
        nonce_type: :sortable,
        mask: true,
        db_format: :hex,
        prefix: "id_",
        persist_prefix: true
      )

    assert {:ok, ~U[2025-01-01 00:00:00.010Z]} =
             Once.CreatedAt.load("id_0000000002800001", nil, params)

    assert :error = Once.CreatedAt.load("wrong_0000000002800001", nil, params)
  end

  test "validates configuration and rejects writes and invalid stored IDs" do
    params = Once.CreatedAt.init(epoch: @epoch, nonce_type: :sortable)

    assert_raise ArgumentError, ~r/requires nonce_type: :sortable/, fn ->
      Once.CreatedAt.init(epoch: @epoch, nonce_type: :counter)
    end

    assert_raise ArgumentError, ~r/requires nonce_type: :sortable/, fn ->
      Once.CreatedAt.init(epoch: @epoch, nonce_type: :encrypted)
    end

    assert_raise KeyError, fn -> Once.CreatedAt.init(nonce_type: :sortable) end
    assert {:ok, nil} = Once.CreatedAt.load(nil, nil, params)
    assert :error = Once.CreatedAt.load("invalid", nil, params)
    assert :error = Once.CreatedAt.cast(@epoch, params)
    assert :error = Once.CreatedAt.dump(@epoch, nil, params)
    assert {:ok, nil} = Once.CreatedAt.dump(nil, nil, params)

    assert_raise ArgumentError, ~r/require writable: :never/, fn ->
      Once.CreatedAt.init(schema: __MODULE__, epoch: @epoch, nonce_type: :sortable)
    end
  end

  test "accepts query boundaries only with the matching epoch" do
    epoch = DateTime.to_unix(@epoch, :millisecond)
    params = Once.CreatedAt.init(epoch: @epoch, nonce_type: :sortable)
    boundary = Once.Query.Boundary.new(epoch + 10, epoch, 0)
    wrong_epoch = Once.Query.Boundary.new(epoch + 10, epoch + 1, 0)

    assert {:ok, ^boundary} = Once.CreatedAt.cast(boundary, params)
    assert {:ok, 10 * 4_194_304} == Once.CreatedAt.dump(boundary, nil, params)

    assert_raise ArgumentError, ~r/query epoch does not match field epoch/, fn ->
      Once.CreatedAt.cast(wrong_epoch, params)
    end

    assert_raise ArgumentError, ~r/query epoch does not match field epoch/, fn ->
      Once.CreatedAt.dump(wrong_epoch, nil, params)
    end
  end

  test "dumps query boundaries with numeric, masked and persisted-prefix options" do
    epoch = DateTime.to_unix(@epoch, :millisecond)
    boundary = Once.Query.Boundary.new(epoch + 10, epoch, 0)

    for masked <- [false, true] do
      params =
        Once.CreatedAt.init(
          epoch: @epoch,
          nonce_type: :sortable,
          ex_format: :signed,
          db_format: :hex,
          mask: masked,
          prefix: "id_",
          persist_prefix: true
        )

      assert {:ok, "id_0000000002800000"} = Once.CreatedAt.dump(boundary, nil, params)
    end
  end
end

defmodule Once.CreatedAtDbTest.IDQuery do
  use Once.Query, epoch: 1_735_689_600_000
end

defmodule Once.CreatedAtDbTest.WrongEpochQuery do
  use Once.Query, epoch: 1_735_689_600_001
end

defmodule Once.CreatedAtDbTest.Schema do
  use Ecto.Schema

  @epoch 1_735_689_600_000
  schema "test_table" do
    field :bigint_id, Once, nonce_type: :sortable

    field :bigint_created_at, Once.CreatedAt,
      source: :bigint_id,
      epoch: @epoch,
      nonce_type: :sortable,
      writable: :never,
      on_writable_violation: :raise

    field :bin_id, Once, nonce_type: :sortable, db_format: :raw, mask: true

    field :bin_created_at, Once.CreatedAt,
      source: :bin_id,
      epoch: @epoch,
      nonce_type: :sortable,
      db_format: :raw,
      mask: true,
      writable: :never,
      on_writable_violation: :raise

    field :string_id, Once,
      nonce_type: :sortable,
      db_format: :hex,
      prefix: "id_",
      persist_prefix: true

    field :string_created_at, Once.CreatedAt,
      source: :string_id,
      epoch: @epoch,
      nonce_type: :sortable,
      db_format: :hex,
      prefix: "id_",
      persist_prefix: true,
      writable: :never,
      on_writable_violation: :raise
  end
end

defmodule Once.CreatedAtDbTest do
  use TestOnce.DataCase, async: true
  import Ecto.Query
  import Once.CreatedAtDbTest.IDQuery
  alias Once.CreatedAtDbTest.Schema

  test "loads timestamps alongside IDs from shared columns" do
    raw = <<10::42, 3::9, 7::13>>
    expected = ~U[2025-01-01 00:00:00.010Z]

    for repo <- [MyApp.PgRepo, MyApp.MysqlRepo] do
      repo.insert_all("test_table", [
        %{
          bigint_id: Once.to_format!(raw, :signed),
          bin_id: raw,
          string_id: "id_" <> Once.to_format!(raw, :hex)
        }
      ])

      row = repo.one!(Schema)
      assert row.bigint_created_at == expected
      assert row.bin_created_at == expected
      assert row.string_created_at == expected
      assert row.bigint_id == Once.to_format!(raw, :url64)
      assert row.string_id == "id_" <> Once.to_format!(raw, :url64)
      assert repo.one!(from row in Schema, select: row.bigint_created_at) == expected

      assert_raise Ecto.Query.CastError, fn ->
        repo.all(from row in Schema, where: row.bigint_created_at >= ^expected)
      end

      assert_raise ArgumentError, fn ->
        repo.insert!(%Schema{bigint_created_at: expected})
      end
    end
  end

  test "query macros filter derived timestamps across database formats" do
    require Once.CreatedAtDbTest.WrongEpochQuery
    epoch = 1_735_689_600_000
    start_time = DateTime.from_unix!(epoch + 10, :millisecond)
    end_time = epoch + 20

    values = [
      9 * 4_194_304,
      10 * 4_194_304,
      10 * 4_194_304 + 8_192,
      11 * 4_194_304,
      20 * 4_194_304
    ]

    for repo <- [MyApp.PgRepo, MyApp.MysqlRepo] do
      rows =
        Enum.map(values, fn value ->
          %{
            bigint_id: value,
            bin_id: Once.to_format!(value, :raw),
            string_id: "id_" <> Once.to_format!(value, :hex)
          }
        end)

      repo.insert_all("test_table", rows)

      for field <- [:bigint_created_at, :bin_created_at, :string_created_at] do
        queries = [
          {from(row in Schema, where: lt(field(row, ^field), ^start_time)), Enum.take(values, 1)},
          {from(row in Schema, where: gte(field(row, ^field), ^start_time)),
           Enum.drop(values, 1)},
          {from(row in Schema, where: gt(field(row, ^field), ^start_time)), Enum.drop(values, 3)},
          {from(row in Schema, where: lte(field(row, ^field), ^start_time)),
           Enum.take(values, 3)},
          {from(row in Schema,
             where: gte(field(row, ^field), ^start_time) and lt(field(row, ^field), ^end_time)
           ), Enum.slice(values, 1, 3)}
        ]

        for {query, expected} <- queries do
          actual =
            query
            |> select([row], row.bigint_id)
            |> repo.all()
            |> Enum.map(&Once.to_format!(&1, :unsigned))
            |> Enum.sort()

          assert actual == expected
        end
      end

      query =
        from row in Schema,
          where: Once.CreatedAtDbTest.WrongEpochQuery.gte(row.bigint_created_at, ^start_time)

      assert_raise ArgumentError, ~r/query epoch does not match field epoch/, fn ->
        repo.all(query)
      end
    end
  end
end
