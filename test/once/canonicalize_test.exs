defmodule Once.CanonicalizeTest do
  # the tables are shared (and locked) by every test, so don't run these concurrently
  use TestOnce.DataCase

  @repos [PgRepo, MysqlRepo]

  # primary keys only, the foreign keys that reference them are detected
  @hex [
    {"canonical_parents", "id"},
    {"canonical_children", "id"},
    {"canonical_grandchildren", "id"}
  ]
  @hex32 [{"canonical_parents", "id32"}]
  @url64 [{"canonical_parents", "id64"}]
  @prefixed [{"canonical_parents", "pid", "usr_"}]

  @hex32_alphabet ~c"0123456789abcdefghijklmnopqrstuv"
  @url64_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

  defp canonicalize_all(repo) do
    [
      Once.Canonicalize.run(repo, @hex, format: :hex),
      Once.Canonicalize.run(repo, @hex32, format: :hex32),
      Once.Canonicalize.run(repo, @url64, format: :url64),
      Once.Canonicalize.run(repo, @prefixed, format: :hex)
    ]
  end

  defp rows(repo, sql), do: repo.query!(sql).rows |> Enum.sort()

  defp parents(repo),
    do: rows(repo, "SELECT id, id32, id64, pid FROM canonical_parents")

  defp children(repo) do
    rows(
      repo,
      "SELECT id, parent_id, parent_id32, parent_id64, parent_pid FROM canonical_children"
    )
  end

  defp grandchildren(repo), do: rows(repo, "SELECT id, child_id FROM canonical_grandchildren")

  defp assert_fk_settings_restored(MyApp.PgRepo) do
    assert [[false]] =
             MyApp.PgRepo.query!("""
             SELECT bool_or(condeferrable) FROM pg_constraint
             WHERE conrelid = 'canonical_children'::regclass AND contype = 'f'
             """).rows
  end

  defp assert_fk_settings_restored(MyApp.MysqlRepo) do
    assert [[1]] = MyApp.MysqlRepo.query!("SELECT @@foreign_key_checks").rows
  end

  # A query function on a separate, non-sandboxed connection with a short lock timeout, to observe
  # what a concurrent session experiences.
  defp other_session(MyApp.PgRepo) do
    {:ok, conn} = Postgrex.start_link(connection_opts(MyApp.PgRepo))
    query = fn sql -> Postgrex.query!(conn, sql, []) end
    query.("SET lock_timeout = '300ms'")
    query
  end

  defp other_session(MyApp.MysqlRepo) do
    {:ok, conn} = MyXQL.start_link(connection_opts(MyApp.MysqlRepo))
    query = fn sql -> MyXQL.query!(conn, sql, []) end
    query.("SET SESSION innodb_lock_wait_timeout = 1")
    query
  end

  defp connection_opts(repo) do
    config = repo.config()

    [
      hostname: config[:host],
      port: config[:port],
      username: config[:username],
      password: config[:password],
      database: config[:database]
    ]
  end

  defp error_of(fun) do
    fun.()
    nil
  rescue
    e -> e
  end

  defp insert_parent(repo, id, id32, id64, pid) do
    repo.query!(
      "INSERT INTO canonical_parents (id, id32, id64, pid) " <>
        "VALUES ('#{id}', '#{id32}', '#{id64}', '#{pid}')"
    )
  end

  defp insert_child(repo, id, parent_id, id32, id64, pid) do
    repo.query!(
      "INSERT INTO canonical_children (id, parent_id, parent_id32, parent_id64, parent_pid) " <>
        "VALUES ('#{id}', '#{parent_id}', '#{id32}', '#{id64}', '#{pid}')"
    )
  end

  for repo <- @repos do
    describe "#{inspect(repo)}" do
      test "the migration canonicalized all data" do
        repo = unquote(repo)

        assert [
                 ["00000000000000aa", "vvvvvvvvvvvvu", "AAAAAAAAAAE", "usr_00000000000000aa"],
                 ["abcdef0123456789", "pg4e2vcsg0002", "AAAAAAAAAAA", "usr_abcdef0123456789"],
                 ["abcdef9876543210", "0000000000000", "__________8", "usr_abcdef9876543210"]
               ] = parents(repo)

        assert [
                 [
                   "ffffffff00000001",
                   "abcdef0123456789",
                   "pg4e2vcsg0002",
                   "AAAAAAAAAAA",
                   "usr_abcdef0123456789"
                 ],
                 [
                   "ffffffff00000002",
                   "abcdef9876543210",
                   "0000000000000",
                   "__________8",
                   "usr_abcdef9876543210"
                 ],
                 [
                   "ffffffff00000003",
                   "00000000000000aa",
                   "vvvvvvvvvvvvu",
                   "AAAAAAAAAAE",
                   "usr_00000000000000aa"
                 ],
                 ["ffffffff00000004", nil, nil, nil, nil],
                 [
                   "ffffffff00000005",
                   "abcdef0123456789",
                   "pg4e2vcsg0002",
                   "AAAAAAAAAAA",
                   "usr_abcdef0123456789"
                 ]
               ] = children(repo)

        assert [
                 ["aaaaaaaa00000001", "ffffffff00000001"],
                 ["aaaaaaaa00000002", "ffffffff00000002"],
                 ["aaaaaaaa00000003", nil]
               ] = grandchildren(repo)
      end

      test "the migrated foreign keys are still enforced" do
        repo = unquote(repo)

        error =
          error_of(fn ->
            repo.transaction(fn ->
              insert_child(repo, "ffffffff00000009", "abcdef0123456789", "x", "y", "z")
            end)
          end)

        assert error.__struct__ in [Postgrex.Error, MyXQL.Error]
      end

      test "canonicalizes new data across all formats and is idempotent" do
        repo = unquote(repo)

        insert_parent(
          repo,
          "BBBBBBBBBBBBBBBB",
          "ABCDEFGHIJKLM",
          "BBBBBBBBBBB",
          "usr_BBBBBBBBBBBBBBBB"
        )

        insert_child(
          repo,
          "CCCCCCCCCCCCCCCC",
          "BBBBBBBBBBBBBBBB",
          "ABCDEFGHIJKLM",
          "BBBBBBBBBBB",
          "usr_BBBBBBBBBBBBBBBB"
        )

        repo.query!(
          "INSERT INTO canonical_grandchildren (id, child_id) VALUES ('DDDDDDDDDDDDDDDD', 'CCCCCCCCCCCCCCCC')"
        )

        # detected foreign keys follow the listed columns, sorted by table and column
        assert [
                 [
                   {{"canonical_parents", "id"}, 1},
                   {{"canonical_children", "id"}, 1},
                   {{"canonical_grandchildren", "id"}, 1},
                   {{"canonical_children", "parent_id"}, 1},
                   {{"canonical_grandchildren", "child_id"}, 1}
                 ],
                 [{{"canonical_parents", "id32"}, 1}, {{"canonical_children", "parent_id32"}, 1}],
                 [{{"canonical_parents", "id64"}, 1}, {{"canonical_children", "parent_id64"}, 1}],
                 [
                   {{"canonical_parents", "pid", "usr_"}, 1},
                   {{"canonical_children", "parent_pid", "usr_"}, 1}
                 ]
               ] = canonicalize_all(repo)

        assert ["bbbbbbbbbbbbbbbb", "abcdefghijklm", "BBBBBBBBBBA", "usr_bbbbbbbbbbbbbbbb"] in parents(
                 repo
               )

        assert [
                 "cccccccccccccccc",
                 "bbbbbbbbbbbbbbbb",
                 "abcdefghijklm",
                 "BBBBBBBBBBA",
                 "usr_bbbbbbbbbbbbbbbb"
               ] in children(repo)

        assert ["dddddddddddddddd", "cccccccccccccccc"] in grandchildren(repo)

        before = {parents(repo), children(repo), grandchildren(repo)}
        assert canonicalize_all(repo) |> List.flatten() |> Enum.all?(fn {_, n} -> n == 0 end)
        assert before == {parents(repo), children(repo), grandchildren(repo)}
      end

      test "restores the foreign key settings" do
        repo = unquote(repo)
        canonicalize_all(repo)
        assert_fk_settings_restored(repo)
      end

      test "checks all spellings and related columns without changing data" do
        repo = unquote(repo)

        insert_parent(
          repo,
          "B1B1B1B1B1B1B1B1",
          "abcdefghijkln",
          "ZZZZZZZZZZB",
          "usr_B1B1B1B1B1B1B1B1"
        )

        insert_child(
          repo,
          "c1c1c1c1c1c1c1c1",
          "B1B1B1B1B1B1B1B1",
          "abcdefghijkln",
          "ZZZZZZZZZZB",
          "usr_B1B1B1B1B1B1B1B1"
        )

        before = {parents(repo), children(repo), fk_state(repo)}

        for {columns, format, affected} <- [
              {@hex, :hex, [{"canonical_parents", "id"}, {"canonical_children", "parent_id"}]},
              {@hex32, :hex32,
               [{"canonical_parents", "id32"}, {"canonical_children", "parent_id32"}]},
              {@url64, :url64,
               [{"canonical_parents", "id64"}, {"canonical_children", "parent_id64"}]},
              {@prefixed, :hex,
               [
                 {"canonical_parents", "pid", "usr_"},
                 {"canonical_children", "parent_pid", "usr_"}
               ]}
            ] do
          assert {:need_migration, Enum.map(affected, &{&1, 1})} ==
                   Once.Canonicalize.check(repo, columns, format: format)
        end

        assert {:need_migration, [{{"canonical_parents", "id64"}, 1}]} =
                 Once.Canonicalize.check(repo, @url64, format: :url64, foreign_keys: false)

        assert before == {parents(repo), children(repo), fk_state(repo)}
      end

      test "check reports when the checked data is canonical" do
        repo = unquote(repo)

        assert :no_migration_needed = Once.Canonicalize.check(repo, @hex32, format: :hex32)
        assert :no_migration_needed = Once.Canonicalize.check(repo, @url64, format: :url64)
        assert :no_migration_needed = Once.Canonicalize.check(repo, @prefixed, format: :hex)
      end

      test "check rejects invalid IDs rather than reporting them as canonical" do
        repo = unquote(repo)
        insert_parent(repo, "eeeeeeeeeeeeeeee", "K000000000000", "EEEEEEEEEEE", "usr_ee")
        before = parents(repo)

        assert_raise RuntimeError, ~r/not valid hex32 IDs/, fn ->
          Once.Canonicalize.check(repo, @hex32, format: :hex32)
        end

        assert before == parents(repo)
      end

      test "blocks concurrent writers, but not readers, until the transaction ends" do
        repo = unquote(repo)
        query = other_session(repo)

        # the sandbox transaction stays open after run/3 returns, so it keeps holding the locks
        Once.Canonicalize.run(repo, @hex32, format: :hex32)

        assert %{rows: [[3]]} = query.("SELECT COUNT(*) FROM canonical_parents")

        for sql <- [
              "UPDATE canonical_parents SET id32 = id32",
              "UPDATE canonical_children SET parent_id32 = parent_id32",
              "INSERT INTO canonical_parents (id, id32, id64, pid) " <>
                "VALUES ('1111111111111111', 'b000000000000', 'Y000000000A', 'usr_lock')"
            ] do
          assert error_of(fn -> query.(sql) end).__struct__ in [Postgrex.Error, MyXQL.Error]
        end
      end

      test "fixes every possible last character of hex32 and url64 values" do
        repo = unquote(repo)

        hex32 =
          for {char, i} <- Enum.with_index(@hex32_alphabet) do
            # the leading "a" keeps these values away from the rows created by the migration
            head = i |> Integer.to_string(32) |> String.downcase() |> String.pad_leading(11, "0")
            {String.upcase("a" <> head <> <<char>>), "e32#{pad(i)}"}
          end

        url64 =
          for {char, i} <- Enum.with_index(@url64_alphabet) do
            # the leading "Z" keeps these values away from the rows created by the migration
            {"Z" <> (i |> Integer.to_string() |> String.pad_leading(9, "A")) <> <<char>>,
             "e64#{pad(i)}"}
          end

        # the column that isn't under test gets a unique, already canonical value
        for {value, key} <- hex32,
            do: insert_parent(repo, key <> "0000000000", value, filler64(key), "p#{key}")

        for {value, key} <- url64,
            do: insert_parent(repo, key <> "0000000000", filler32(key), value, "p#{key}")

        Once.Canonicalize.run(repo, @hex32, format: :hex32)
        Once.Canonicalize.run(repo, @url64, format: :url64)

        expected_hex32 =
          for {value, key} <- hex32 do
            {key,
             value
             |> String.downcase()
             |> Base.hex_decode32!(case: :lower, padding: false)
             |> Base.hex_encode32(case: :lower, padding: false)}
          end

        expected_url64 =
          for {value, key} <- url64 do
            {key,
             value |> Base.url_decode64!(padding: false) |> Base.url_encode64(padding: false)}
          end

        actual32 =
          rows(
            repo,
            "SELECT SUBSTR(id, 1, 5), id32 FROM canonical_parents WHERE id LIKE 'e32%'"
          )

        actual64 =
          rows(
            repo,
            "SELECT SUBSTR(id, 1, 5), id64 FROM canonical_parents WHERE id LIKE 'e64%'"
          )

        assert actual32 == expected_hex32 |> Enum.map(&Tuple.to_list/1) |> Enum.sort()
        assert actual64 == expected_url64 |> Enum.map(&Tuple.to_list/1) |> Enum.sort()
      end

      test "invalid values abort the migration and change nothing" do
        repo = unquote(repo)

        insert_parent(
          repo,
          "dddddddddddddddd",
          "PG4E2VCSG0005",
          "DDDDDDDDDDE",
          "usr_dddddddddddddddd"
        )

        insert_parent(
          repo,
          "eeeeeeeeeeeeeeee",
          "notvalid!!!!!",
          "EEEEEEEEEEE",
          "usr_eeeeeeeeeeeeeeee"
        )

        before = parents(repo)

        error = error_of(fn -> Once.Canonicalize.run(repo, @hex32, format: :hex32) end)
        assert %RuntimeError{message: message} = error
        assert message =~ "not valid hex32 IDs"
        assert message =~ "notvalid!!!!!"

        assert before == parents(repo)
      end

      test "without foreign key detection, forgetting a referencing column aborts and restores settings" do
        repo = unquote(repo)
        insert_linked_rows(repo)
        before = {parents(repo), children(repo)}

        # parent_id64 is not canonicalized along with id64
        error =
          error_of(fn ->
            Once.Canonicalize.run(repo, [{"canonical_parents", "id64"}],
              format: :url64,
              foreign_keys: false
            )
          end)

        assert error.__struct__ in [Postgrex.Error, RuntimeError]
        assert {parents(repo), children(repo)} == before
        assert_fk_settings_restored(repo)
      end

      test "detects the referencing column that foreign_keys: false would forget" do
        repo = unquote(repo)
        insert_linked_rows(repo)

        assert [
                 {{"canonical_parents", "id64"}, 1},
                 {{"canonical_children", "parent_id64"}, 1}
               ] = Once.Canonicalize.run(repo, [{"canonical_parents", "id64"}], format: :url64)

        assert ["fbfbfbfbfbfbfbfb", "fafafafafafafafa", "aaaaaaaaaaaa0", "CCCCCCCCCCA", _] =
                 Enum.find(children(repo), &(hd(&1) == "fbfbfbfbfbfbfbfb"))
      end

      test "follows foreign keys from the referencing side, leaving other columns alone" do
        repo = unquote(repo)
        insert_linked_rows(repo)
        insert_parent(repo, "F1F1F1F1F1F1F1F1", "aaaaaaaaaaaa2", "CCCCCCCCCCE", "usr_f1")

        repo.query!(
          "INSERT INTO canonical_children (id, parent_id) VALUES ('F2F2F2F2F2F2F2F2', 'F1F1F1F1F1F1F1F1')"
        )

        # listing only the referencing column also changes the column it references
        assert [
                 {{"canonical_children", "parent_id"}, 1},
                 {{"canonical_parents", "id"}, 1}
               ] =
                 Once.Canonicalize.run(repo, [{"canonical_children", "parent_id"}], format: :hex)

        # children.id is not linked to it, so it keeps its spelling
        assert [["F2F2F2F2F2F2F2F2", "f1f1f1f1f1f1f1f1"]] =
                 rows(
                   repo,
                   "SELECT id, parent_id FROM canonical_children WHERE id = 'F2F2F2F2F2F2F2F2'"
                 )
      end

      test "detected columns inherit the ID prefix" do
        repo = unquote(repo)
        insert_linked_rows(repo)

        assert [
                 {{"canonical_parents", "pid", "usr_"}, 1},
                 {{"canonical_children", "parent_pid", "usr_"}, 1}
               ] =
                 Once.Canonicalize.run(repo, [{"canonical_parents", "pid", "usr_"}], format: :hex)

        assert [["usr_fafafafafafafafa"]] =
                 rows(repo, "SELECT pid FROM canonical_parents WHERE id = 'fafafafafafafafa'")

        assert [["usr_fafafafafafafafa"]] =
                 rows(
                   repo,
                   "SELECT parent_pid FROM canonical_children WHERE id = 'fbfbfbfbfbfbfbfb'"
                 )
      end

      test "linked columns with different ID prefixes are rejected" do
        repo = unquote(repo)

        error =
          error_of(fn ->
            Once.Canonicalize.run(
              repo,
              [
                {"canonical_parents", "pid", "usr_"},
                {"canonical_children", "parent_pid", "org_"}
              ],
              format: :hex
            )
          end)

        assert %ArgumentError{message: message} = error
        assert message =~ "different ID prefixes"
      end
    end
  end

  for repo <- @repos do
    describe "#{inspect(repo)} edge cases" do
      test "a collision with an existing value aborts and changes nothing" do
        repo = unquote(repo)
        # canonicalizes to "AAAAAAAAAAA", which a migrated row already holds
        insert_parent(repo, "c0c0c0c0c0c0c0c0", "cccccccccccc0", "AAAAAAAAAAB", "usr_c0")
        before = {snapshot(repo), fk_state(repo)}

        error =
          error_of(fn ->
            Once.Canonicalize.run(repo, [{"canonical_parents", "id64"}], format: :url64)
          end)

        assert error.__struct__ in [Postgrex.Error, MyXQL.Error]
        assert before == {snapshot(repo), fk_state(repo)}
      end

      test "the :prefix option selects the schema" do
        repo = unquote(repo)
        repo.query!("INSERT INTO canon_alt.canonical_parents (id) VALUES ('ABCDEF0000000001')")

        repo.query!(
          "INSERT INTO canon_alt.canonical_children (id, parent_id) " <>
            "VALUES ('ABCDEF0000000002', 'ABCDEF0000000001')"
        )

        default_before = snapshot(repo)

        assert [
                 {{"canonical_parents", "id"}, 1},
                 {{"canonical_children", "parent_id"}, 1}
               ] =
                 Once.Canonicalize.run(repo, [{"canonical_parents", "id"}],
                   format: :hex,
                   prefix: "canon_alt"
                 )

        assert [["abcdef0000000001"]] = rows(repo, "SELECT id FROM canon_alt.canonical_parents")

        # children.id is not linked to the listed column, so it keeps its spelling
        assert [["ABCDEF0000000002", "abcdef0000000001"]] =
                 rows(repo, "SELECT id, parent_id FROM canon_alt.canonical_children")

        assert default_before == snapshot(repo)

        # without the option the default schema is used and the other one is left alone
        repo.query!("INSERT INTO canon_alt.canonical_parents (id) VALUES ('FEDCBA0000000001')")

        assert [{{"canonical_parents", "id"}, 0} | _] =
                 Once.Canonicalize.run(repo, [{"canonical_parents", "id"}], format: :hex)

        assert [["FEDCBA0000000001"], ["abcdef0000000001"]] =
                 rows(repo, "SELECT id FROM canon_alt.canonical_parents")
      end

      test "only the listed and linked columns change" do
        repo = unquote(repo)

        insert_parent(
          repo,
          "B1B1B1B1B1B1B1B1",
          "ABCDEFGHIJKL1",
          "ZZZZZZZZZZB",
          "usr_B1B1B1B1B1B1B1B1"
        )

        insert_child(
          repo,
          "E1E1E1E1E1E1E1E1",
          "B1B1B1B1B1B1B1B1",
          "ABCDEFGHIJKL1",
          "ZZZZZZZZZZB",
          "usr_B1B1B1B1B1B1B1B1"
        )

        counts_before = counts(repo)
        untouched_before = untouched(repo)

        assert [
                 {{"canonical_parents", "id"}, 1},
                 {{"canonical_children", "parent_id"}, 1}
               ] = Once.Canonicalize.run(repo, [{"canonical_parents", "id"}], format: :hex)

        assert counts_before == counts(repo)
        assert untouched_before == untouched(repo)

        assert [["b1b1b1b1b1b1b1b1", "ABCDEFGHIJKL1", "ZZZZZZZZZZB", "usr_B1B1B1B1B1B1B1B1"]] =
                 rows(
                   repo,
                   "SELECT id, id32, id64, pid FROM canonical_parents WHERE id LIKE 'b1%'"
                 )
      end

      test "self-referencing foreign keys" do
        repo = unquote(repo)

        for {id, parent} <- [{1, "NULL"}, {2, "'A000000000000001'"}, {3, "'A000000000000002'"}] do
          repo.query!(
            "INSERT INTO canonical_nodes (id, parent_id) VALUES ('A00000000000000#{id}', #{parent})"
          )
        end

        assert [{{"canonical_nodes", "id"}, 3}, {{"canonical_nodes", "parent_id"}, 2}] =
                 Once.Canonicalize.run(repo, [{"canonical_nodes", "id"}], format: :hex)

        assert [
                 ["a000000000000001", nil],
                 ["a000000000000002", "a000000000000001"],
                 ["a000000000000003", "a000000000000002"]
               ] = rows(repo, "SELECT id, parent_id FROM canonical_nodes")
      end

      test "multi-column foreign keys with columns of different formats" do
        repo = unquote(repo)

        repo.query!(
          "INSERT INTO canonical_orgs (a_id, b_id) VALUES ('AAAAAAAA00000001', 'PG4E2VCSG0003')"
        )

        repo.query!(
          "INSERT INTO canonical_members (id, a_id, b_id) VALUES " <>
            "('BBBBBBBB00000001', 'AAAAAAAA00000001', 'PG4E2VCSG0003'), ('BBBBBBBB00000002', NULL, NULL)"
        )

        # each call only changes its own column of the composite key
        assert [{{"canonical_orgs", "a_id"}, 1}, {{"canonical_members", "a_id"}, 1}] =
                 Once.Canonicalize.run(repo, [{"canonical_orgs", "a_id"}], format: :hex)

        assert [{{"canonical_orgs", "b_id"}, 1}, {{"canonical_members", "b_id"}, 1}] =
                 Once.Canonicalize.run(repo, [{"canonical_orgs", "b_id"}], format: :hex32)

        assert [["aaaaaaaa00000001", "pg4e2vcsg0002"]] =
                 rows(repo, "SELECT a_id, b_id FROM canonical_orgs")

        assert [
                 ["BBBBBBBB00000001", "aaaaaaaa00000001", "pg4e2vcsg0002"],
                 ["BBBBBBBB00000002", nil, nil]
               ] = rows(repo, "SELECT id, a_id, b_id FROM canonical_members")
      end

      test "forgetting a column of a multi-column foreign key aborts" do
        repo = unquote(repo)

        repo.query!(
          "INSERT INTO canonical_orgs (a_id, b_id) VALUES ('AAAAAAAA00000001', 'pg4e2vcsg0002')"
        )

        repo.query!(
          "INSERT INTO canonical_members (id, a_id, b_id) " <>
            "VALUES ('BBBBBBBB00000001', 'AAAAAAAA00000001', 'pg4e2vcsg0002')"
        )

        before = {rows(repo, "SELECT * FROM canonical_orgs"), fk_state(repo)}

        error =
          error_of(fn ->
            Once.Canonicalize.run(repo, [{"canonical_orgs", "a_id"}],
              format: :hex,
              foreign_keys: false
            )
          end)

        assert error.__struct__ in [Postgrex.Error, RuntimeError]
        assert before == {rows(repo, "SELECT * FROM canonical_orgs"), fk_state(repo)}
      end

      test "foreign keys with ON UPDATE CASCADE" do
        repo = unquote(repo)
        repo.query!("INSERT INTO canonical_roots (id) VALUES ('B000000000000001')")

        repo.query!(
          "INSERT INTO canonical_cascade (id, root_id) VALUES ('C000000000000001', 'B000000000000001')"
        )

        assert [{{"canonical_roots", "id"}, 1} | _] =
                 Once.Canonicalize.run(repo, [{"canonical_roots", "id"}], format: :hex)

        assert [["C000000000000001", "b000000000000001"]] =
                 rows(repo, "SELECT id, root_id FROM canonical_cascade")

        assert [["b000000000000001"]] = rows(repo, "SELECT id FROM canonical_roots")
      end

      test "rewrites a row once, however many of its columns change" do
        repo = unquote(repo)

        insert_parent(repo, "B2B2B2B2B2B2B2B2", "ABCDEFGHIJKL3", "ZZZZZZZZZZC", "usr_B2")

        insert_child(
          repo,
          "E2E2E2E2E2E2E2E2",
          "B2B2B2B2B2B2B2B2",
          "ABCDEFGHIJKL3",
          "ZZZZZZZZZZC",
          "usr_B2"
        )

        before = rows_updated(repo)

        # children.id is listed (twice, which is fine) and children.parent_id is detected
        assert [
                 {{"canonical_parents", "id"}, 1},
                 {{"canonical_children", "id"}, 1},
                 {{"canonical_grandchildren", "id"}, 0},
                 {{"canonical_children", "parent_id"}, 1},
                 {{"canonical_grandchildren", "child_id"}, 0}
               ] =
                 Once.Canonicalize.run(repo, @hex ++ [{"canonical_children", "id"}], format: :hex)

        # one for the parent and one for the child, not two for the child
        assert rows_updated(repo) - before == 2

        assert [["e2e2e2e2e2e2e2e2", "b2b2b2b2b2b2b2b2"]] =
                 rows(repo, "SELECT id, parent_id FROM canonical_children WHERE id LIKE 'e2%'")
      end

      test "dry run reports what would change, and changes nothing" do
        repo = unquote(repo)
        insert_linked_rows(repo)
        before = {snapshot(repo), fk_state(repo)}
        columns = [{"canonical_parents", "id64"}]

        expected = [
          {{"canonical_parents", "id64"}, 1},
          {{"canonical_children", "parent_id64"}, 1}
        ]

        assert ^expected = Once.Canonicalize.run(repo, columns, format: :url64, dry_run: true)
        assert before == {snapshot(repo), fk_state(repo)}

        # the real run changes exactly what the dry run reported
        assert ^expected = Once.Canonicalize.run(repo, columns, format: :url64)
        assert before != {snapshot(repo), fk_state(repo)}
        assert [{_, 0}, {_, 0}] = Once.Canonicalize.run(repo, columns, format: :url64)
      end

      test "dry run runs all checks" do
        repo = unquote(repo)

        insert_parent(repo, "eeeeeeeeeeeeeeee", "notvalid!!!!!", "EEEEEEEEEEE", "usr_ee")
        before = snapshot(repo)

        error =
          error_of(fn ->
            Once.Canonicalize.run(repo, [{"canonical_parents", "id32"}],
              format: :hex32,
              dry_run: true
            )
          end)

        assert %RuntimeError{message: message} = error
        assert message =~ "not valid hex32 IDs"
        assert before == snapshot(repo)

        # a collision, which only shows up when the update is attempted
        insert_parent(repo, "c0c0c0c0c0c0c0c0", "cccccccccccc0", "AAAAAAAAAAB", "usr_c0")
        before = snapshot(repo)

        error =
          error_of(fn ->
            Once.Canonicalize.run(repo, [{"canonical_parents", "id64"}],
              format: :url64,
              dry_run: true
            )
          end)

        assert error.__struct__ in [Postgrex.Error, MyXQL.Error]
        assert before == snapshot(repo)
      end
    end
  end

  describe "PostgreSQL" do
    test "a case variant that collides with an existing primary key aborts and changes nothing" do
      repo = MyApp.PgRepo
      # a case-sensitive primary key can hold both spellings, until they are canonicalized
      insert_parent(repo, "ABCDEF0123456789", "dddddddddddd0", "AAAAAAAAAAI", "usr_dd")
      before = {snapshot(repo), fk_state(repo)}

      error =
        error_of(fn ->
          Once.Canonicalize.run(repo, [{"canonical_parents", "id"}], format: :hex)
        end)

      assert %Postgrex.Error{postgres: %{code: :unique_violation}} = error
      assert before == {snapshot(repo), fk_state(repo)}
    end

    test "leaves deferrable foreign keys as they were" do
      repo = MyApp.PgRepo
      repo.query!("INSERT INTO canonical_roots (id) VALUES ('D000000000000001')")

      repo.query!(
        "INSERT INTO canonical_deferred (id, root_id) VALUES ('E000000000000001', 'D000000000000001')"
      )

      before = fk_state(repo)

      assert [
               {{"canonical_roots", "id"}, 1},
               {{"canonical_cascade", "root_id"}, _},
               {{"canonical_deferred", "root_id"}, 1}
             ] = Once.Canonicalize.run(repo, [{"canonical_roots", "id"}], format: :hex)

      assert before == fk_state(repo)

      assert [["E000000000000001", "d000000000000001"]] =
               rows(repo, "SELECT id, root_id FROM canonical_deferred")

      assert [["canonical_deferred_root_id_fkey", true, true]] =
               rows(
                 repo,
                 "SELECT conname, condeferrable, condeferred FROM pg_constraint " <>
                   "WHERE conname = 'canonical_deferred_root_id_fkey'"
               )
    end
  end

  # the number of rows that were updated so far in this transaction or session
  defp rows_updated(MyApp.PgRepo) do
    [[n]] =
      MyApp.PgRepo.query!("""
      SELECT COALESCE(SUM(n_tup_upd), 0)::bigint FROM pg_stat_xact_user_tables
      WHERE relname IN ('canonical_parents', 'canonical_children', 'canonical_grandchildren')
      """).rows

    n
  end

  defp rows_updated(MyApp.MysqlRepo) do
    [["Handler_update", n]] =
      MyApp.MysqlRepo.query!("SHOW SESSION STATUS LIKE 'Handler_update'").rows

    String.to_integer(n)
  end

  # all rows of the tables that the other tests insert into
  defp snapshot(repo) do
    for table <- ~w(canonical_parents canonical_children canonical_grandchildren) do
      rows(repo, "SELECT * FROM #{table}")
    end
  end

  defp counts(repo) do
    for table <- ~w(canonical_parents canonical_children canonical_grandchildren) do
      repo.query!("SELECT COUNT(*) FROM #{table}").rows
    end
  end

  # every column that the "only the listed and linked columns" test does not canonicalize
  defp untouched(repo) do
    [
      rows(repo, "SELECT id32, id64, pid FROM canonical_parents"),
      rows(repo, "SELECT id, parent_id32, parent_id64, parent_pid FROM canonical_children"),
      rows(repo, "SELECT id, child_id FROM canonical_grandchildren")
    ]
  end

  # the foreign key settings that Once.Canonicalize changes temporarily
  defp fk_state(MyApp.PgRepo) do
    MyApp.PgRepo.query!("""
    SELECT conname, condeferrable, condeferred FROM pg_constraint
    WHERE contype = 'f' ORDER BY conname
    """).rows
  end

  defp fk_state(MyApp.MysqlRepo), do: MyApp.MysqlRepo.query!("SELECT @@foreign_key_checks").rows

  # a parent and a child whose url64 and prefixed values are not canonical; the other values are
  defp insert_linked_rows(repo) do
    insert_parent(
      repo,
      "fafafafafafafafa",
      "aaaaaaaaaaaa0",
      "CCCCCCCCCCB",
      "usr_FAFAFAFAFAFAFAFA"
    )

    insert_child(
      repo,
      "fbfbfbfbfbfbfbfb",
      "fafafafafafafafa",
      "aaaaaaaaaaaa0",
      "CCCCCCCCCCB",
      "usr_FAFAFAFAFAFAFAFA"
    )
  end

  defp pad(i), do: i |> Integer.to_string() |> String.pad_leading(2, "0")

  # 13 valid hex32 characters ending in an even one, and 11 url64 characters ending in "A"
  defp filler32("e" <> _ = key),
    do:
      "b" <>
        String.pad_leading(
          key |> :erlang.phash2() |> Kernel.*(2) |> Integer.to_string(32) |> String.downcase(),
          12,
          "0"
        )

  defp filler64("e" <> _ = key),
    do: "Y" <> String.pad_leading(key |> :erlang.phash2() |> Integer.to_string(), 9, "A") <> "A"
end
