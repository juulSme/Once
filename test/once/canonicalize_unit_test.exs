defmodule Once.CanonicalizeUnitTest do
  use ExUnit.Case, async: true

  defmodule UnsupportedRepo do
    def __adapter__, do: Ecto.Adapters.SQLite3
  end

  defmodule FakePg do
    def __adapter__, do: Ecto.Adapters.Postgres
  end

  defmodule FakeMysql do
    def __adapter__, do: Ecto.Adapters.MyXQL

    def query!(sql, _params, _opts) do
      send(self(), {:query, sql})
      %{rows: [[1, 0]]}
    end
  end

  @columns [{"users", "id"}]

  test "check reports that migration is needed without locking rows" do
    assert {:need_migration, [{{"users", "id"}, 1}]} =
             Once.Canonicalize.check(FakeMysql, @columns, format: :hex, foreign_keys: false)

    assert_received {:query, sql}
    refute sql =~ "FOR UPDATE"
  end

  test "check validates its options before accessing the repository" do
    assert_raise ArgumentError, ~r/option :format must be/, fn ->
      Once.Canonicalize.check(FakePg, @columns, [])
    end

    assert_raise ArgumentError, ~r/:dry_run is not supported/, fn ->
      Once.Canonicalize.check(FakePg, @columns, format: :hex, dry_run: true)
    end
  end

  describe "run/3 validation" do
    test "requires a known format" do
      for opts <- [[], [format: :base64], [format: "hex"]] do
        assert_raise ArgumentError, ~r/option :format must be/, fn ->
          Once.Canonicalize.run(FakePg, @columns, opts)
        end
      end
    end

    test "requires a non-empty list of columns" do
      for columns <- [[], nil] do
        assert_raise ArgumentError, ~r/non-empty list/, fn ->
          Once.Canonicalize.run(FakePg, columns, format: :hex)
        end
      end
    end

    test "rejects malformed columns" do
      for column <- [{"users"}, "users.id", {:users, "id"}, {"users", "id; DROP TABLE users"}] do
        assert_raise ArgumentError, fn ->
          Once.Canonicalize.run(FakePg, [column], format: :hex)
        end
      end

      assert_raise ArgumentError, ~r/invalid table, column or prefix name/, fn ->
        Once.Canonicalize.run(FakePg, @columns, format: :hex, prefix: "a\"b")
      end
    end

    test "rejects a column that is listed with different ID prefixes" do
      assert_raise ArgumentError, ~r/different ID prefixes/, fn ->
        Once.Canonicalize.run(FakePg, [{"users", "id", "a_"}, {"users", "id", "b_"}],
          format: :hex
        )
      end
    end

    test "requires a boolean :foreign_keys" do
      assert_raise ArgumentError, ~r/:foreign_keys must be a boolean/, fn ->
        Once.Canonicalize.run(FakePg, @columns, format: :hex, foreign_keys: "yes")
      end
    end

    test "requires a boolean :dry_run" do
      assert_raise ArgumentError, ~r/:dry_run must be a boolean/, fn ->
        Once.Canonicalize.run(FakePg, @columns, format: :hex, dry_run: "yes")
      end
    end

    test "rejects ID prefixes that cannot be embedded in SQL" do
      for id_prefix <- ["", "it's_", "back\\slash", 12] do
        assert_raise ArgumentError, ~r/ID prefix/, fn ->
          Once.Canonicalize.run(FakePg, [{"users", "id", id_prefix}], format: :hex)
        end
      end
    end

    test "rejects unsupported adapters" do
      assert_raise ArgumentError, ~r/unsupported adapter Ecto.Adapters.SQLite3/, fn ->
        Once.Canonicalize.run(UnsupportedRepo, @columns, format: :hex)
      end
    end
  end
end
