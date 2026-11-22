defmodule Once.QueryTest.IDQuery do
  use Once.Query, epoch: 1_577_836_800_000
end

defmodule Once.QueryTest.DateTimeEpochQuery do
  use Once.Query, epoch: ~U[2020-01-01 00:00:00Z]
end

defmodule Once.QueryTest.DefaultEpochQuery do
  use Once.Query
end

defmodule Once.QueryTest.Schema do
  use Ecto.Schema

  schema "test_table" do
    field :custom_epoch, Once, nonce_type: :sortable
    field :sortable, Once, nonce_type: :sortable
  end
end

defmodule Once.QueryTest do
  use ExUnit.Case, async: true
  import Ecto.Query
  import Once.QueryTest.IDQuery
  alias Once.QueryTest.Schema

  test "documents the default query macros" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Once.Query)

    for name <- [:lt, :gte, :gt, :lte, :eq] do
      assert Enum.any?(entries, fn
               {{:macro, ^name, 2}, _, _, %{"en" => doc}, _} ->
                 is_binary(doc) and doc != ""

               _ ->
                 false
             end)
    end
  end

  test "direct macros use the default epoch" do
    require Once.Query
    time = ~U[2025-01-01 00:00:00.010Z]
    type = Schema.__schema__(:type, :sortable)

    queries = [
      {from(row in Schema, where: Once.Query.lt(row.sortable, ^time)), [10]},
      {from(row in Schema, where: Once.Query.gte(row.sortable, ^time)), [10]},
      {from(row in Schema, where: Once.Query.gt(row.sortable, ^time)), [11]},
      {from(row in Schema, where: Once.Query.lte(row.sortable, ^time)), [11]},
      {from(row in Schema, where: Once.Query.eq(row.sortable, ^time)), [10, 11]}
    ]

    for {query, milliseconds} <- queries do
      [%{params: params}] = query.wheres

      dumped =
        Enum.map(params, fn {value, _} ->
          assert {:ok, cast} = Ecto.Type.cast(type, value)
          assert {:ok, result} = Ecto.Type.dump(type, cast)
          result
        end)

      assert dumped == Enum.map(milliseconds, &(&1 * 4_194_304))
    end
  end

  test "builds boundaries using the explicitly configured epoch" do
    time = ~U[2020-01-01 00:00:00.010Z]

    query =
      from row in Schema,
        where: gte(row.custom_epoch, ^time) and lte(row.custom_epoch, ^time)

    type = Schema.__schema__(:type, :custom_epoch)
    [%{params: params}] = query.wheres

    dumped =
      Enum.map(params, fn {value, {0, :custom_epoch}} ->
        assert {:ok, cast} = Ecto.Type.cast(type, value)
        assert {:ok, result} = Ecto.Type.dump(type, cast)
        result
      end)

    assert dumped == [10 * 4_194_304, 11 * 4_194_304]
  end

  test "uses the NoNoncense default epoch when none is configured" do
    require Once.QueryTest.DefaultEpochQuery
    time = ~U[2025-01-01 00:00:00.010Z]

    query =
      from row in Schema,
        where: Once.QueryTest.DefaultEpochQuery.gte(row.sortable, ^time)

    [%{params: [{value, _}]}] = query.wheres
    type = Schema.__schema__(:type, :sortable)
    assert {:ok, cast} = Ecto.Type.cast(type, value)
    assert {:ok, 10 * 4_194_304} == Ecto.Type.dump(type, cast)

    created_at = Once.CreatedAt.init(epoch: ~U[2025-01-01 00:00:00Z], nonce_type: :sortable)
    assert {:ok, boundary} = Once.CreatedAt.cast(value, created_at)
    assert {:ok, 10 * 4_194_304} == Once.CreatedAt.dump(boundary, nil, created_at)
  end

  test "equality spans the full millisecond" do
    time = ~U[2020-01-01 00:00:00.010Z]
    type = Schema.__schema__(:type, :sortable)
    created_at = Once.CreatedAt.init(epoch: ~U[2020-01-01 00:00:00Z], nonce_type: :sortable)

    for timestamp <- [time, DateTime.to_unix(time, :millisecond)] do
      query = from row in Schema, where: eq(row.sortable, ^timestamp)
      [%{expr: {:and, _, [{:>=, _, _}, {:<, _, _}]}, params: params}] = query.wheres

      dumped =
        Enum.map(params, fn {value, _} ->
          assert {:ok, cast} = Ecto.Type.cast(type, value)
          assert {:ok, result} = Ecto.Type.dump(type, cast)
          assert {:ok, boundary} = Once.CreatedAt.cast(value, created_at)
          assert {:ok, ^result} = Once.CreatedAt.dump(boundary, nil, created_at)
          result
        end)

      assert dumped == [10 * 4_194_304, 11 * 4_194_304]
    end
  end

  test "accepts a DateTime epoch" do
    require Once.QueryTest.DateTimeEpochQuery
    time = 1_577_836_800_010

    query =
      from row in Schema,
        where: Once.QueryTest.DateTimeEpochQuery.gte(row.sortable, ^time)

    [%{params: [{value, _}]}] = query.wheres
    type = Schema.__schema__(:type, :sortable)
    assert {:ok, cast} = Ecto.Type.cast(type, value)
    assert {:ok, 10 * 4_194_304} == Ecto.Type.dump(type, cast)
  end

  test "rejects sub-millisecond timestamps" do
    sub_millisecond = ~U[2020-01-01 00:00:00.000001Z]

    assert_raise ArgumentError, ~r/timestamp must have millisecond precision/, fn ->
      from row in Schema, where: lt(row.sortable, ^sub_millisecond)
    end
  end

  test "eq only accepts side-effect free timestamp expressions" do
    for ok <- ["time", "1_000", "@time", "opts.time", "~U[2025-01-01 00:00:00.010Z]"] do
      assert Macro.expand(Code.string_to_quoted!("eq(row.sortable, ^#{ok})"), __ENV__)
    end

    for bad <- ["DateTime.utc_now()", "now()", "opts.time()", "time + 1"] do
      assert_raise ArgumentError, ~r/interpolates the timestamp twice/, fn ->
        Macro.expand(Code.string_to_quoted!("eq(row.sortable, ^(#{bad}))"), __ENV__)
      end
    end
  end

  test "requires timestamps to use Ecto interpolation" do
    assert_raise ArgumentError, ~r/interpolated with \^/, fn ->
      Macro.expand(quote(do: lt(row.sortable, time)), __ENV__)
    end
  end
end

defmodule Once.QueryDbTest.IDQuery do
  use Once.Query, epoch: 1_735_689_600_000
end

defmodule Once.QueryDirectTest do
  use ExUnit.Case, async: true
  import Ecto.Query
  import Once.Query
  alias Once.QueryTest.Schema

  test "imports default macros into Ecto expressions" do
    time = ~U[2025-01-01 00:00:00.010Z]
    query = from row in Schema, where: eq(row.sortable, ^time)
    assert [%{expr: {:and, _, [{:>=, _, _}, {:<, _, _}]}}] = query.wheres
  end
end

defmodule Once.QueryDbTest.Schema do
  use Ecto.Schema

  schema "test_table" do
    field :bigint_id, Once, nonce_type: :sortable
    field :autogenerated, Once, nonce_type: :sortable, mask: true, prefix: "id_"

    field :string_id, Once,
      nonce_type: :sortable,
      ex_format: :signed,
      db_format: :hex,
      prefix: "id_",
      persist_prefix: true
  end
end

defmodule Once.QueryDbTest do
  use TestOnce.DataCase, async: true
  import Ecto.Query
  import Once.QueryDbTest.IDQuery
  alias Once.QueryDbTest.Schema

  defp take_at(list, indices) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> if i in indices, do: [v], else: [] end)
  end

  test "composes timestamp predicates, including joined fields, on both adapters" do
    require Once.Query
    epoch = ~U[2025-01-01 00:00:00.000Z]
    time = DateTime.add(epoch, 10, :millisecond)
    end_time = DateTime.add(epoch, 20, :millisecond)
    unix_time = DateTime.to_unix(time, :millisecond)

    values =
      for {milliseconds, machine_id, counter} <- [
            {9, 0, 0},
            {10, 0, 0},
            {10, 1, 0},
            {11, 0, 0},
            {20, 0, 0}
          ] do
        <<value::unsigned-64>> = <<milliseconds::42, machine_id::9, counter::13>>
        value
      end

    for repo <- [MyApp.PgRepo, MyApp.MysqlRepo] do
      rows =
        Enum.map(values, fn value ->
          %{
            bigint_id: value,
            autogenerated: value,
            string_id: "id_" <> Once.to_format!(value, :hex)
          }
        end)

      repo.insert_all("test_table", rows)

      queries = [
        {from(row in Schema, where: lt(row.bigint_id, ^time)), take_at(values, 0..0)},
        {from(row in Schema, where: gte(row.bigint_id, ^time)), take_at(values, 1..4)},
        {from(row in Schema, where: gt(row.bigint_id, ^time)), take_at(values, 3..4)},
        {from(row in Schema, where: lte(row.bigint_id, ^time)), take_at(values, 0..2)},
        {from(row in Schema, where: lt(row.bigint_id, ^unix_time)), take_at(values, 0..0)},
        {from(row in Schema, where: gte(row.bigint_id, ^unix_time)), take_at(values, 1..4)},
        {from(row in Schema, where: gt(row.bigint_id, ^unix_time)), take_at(values, 3..4)},
        {from(row in Schema, where: lte(row.bigint_id, ^unix_time)), take_at(values, 0..2)},
        {from(row in Schema, where: eq(row.bigint_id, ^time)), take_at(values, 1..2)},
        {from(row in Schema, where: Once.Query.lt(row.bigint_id, ^time)), take_at(values, 0..0)},
        {from(row in Schema, where: Once.Query.gte(row.bigint_id, ^time)), take_at(values, 1..4)},
        {from(row in Schema, where: Once.Query.gt(row.bigint_id, ^time)), take_at(values, 3..4)},
        {from(row in Schema, where: Once.Query.lte(row.bigint_id, ^time)), take_at(values, 0..2)},
        {from(row in Schema, where: Once.Query.eq(row.bigint_id, ^time)), take_at(values, 1..2)},
        {from(row in Schema,
           where: gte(row.autogenerated, ^time) and lte(row.autogenerated, ^time)
         ), take_at(values, 1..2)},
        {from(row in Schema,
           where: gte(row.string_id, ^time) and lt(row.string_id, ^end_time)
         ), take_at(values, 1..3)},
        {from(row in Schema,
           join: joined in Schema,
           on: joined.id == row.id,
           where:
             lt(joined.bigint_id, ^time) or
               (gte(joined.bigint_id, ^end_time) and lte(joined.bigint_id, ^end_time))
         ), take_at(values, [0, 4])}
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
  end
end
