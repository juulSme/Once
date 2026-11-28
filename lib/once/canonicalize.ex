defmodule Once.Canonicalize do
  require Logger

  @moduledoc """
  Migration helpers that rewrite stored `:hex`, `:hex32` and `:url64` IDs to their canonical spelling.

  Once generates lowercase hex and hex32 strings and url64 and hex32 strings with zeroed trailing
  bits, but older versions (and other writers) may have stored other spellings of the same ID. See
  [Non-canonical String IDs](`m:Once#module-non-canonical-string-ids`) for the problems this causes.
  Use these helpers to fix existing data.

  ## Usage

  List the columns that hold IDs of one format, typically the primary keys. Foreign keys that
  reference them, and the columns those reference in turn, are detected and changed along with
  them. Call the helper once per format:

      defmodule MyApp.Repo.Migrations.CanonicalizeIds do
        use Ecto.Migration

        def up do
          # also changes posts.user_id, comments.post_id and any other foreign keys to these columns
          Once.Canonicalize.up([{"users", "id"}, {"posts", "id"}], format: :hex)

          # a persisted prefix is the optional third element of a column tuple
          Once.Canonicalize.up([{"orgs", "id", "org_"}], format: :hex32)
        end

        def down, do: raise(Ecto.MigrationError, message: "irreversible")
      end

  All columns of one call are changed together, so foreign keys between them stay valid. Already
  canonical values and `NULL`s are left alone, so running it again changes nothing.

  Values that are not valid IDs of the given format cannot be canonicalized. They abort the
  migration with an error that lists some examples.

  Use `check/3` to check for non-canonical values without changing data or locking rows:

      Once.Canonicalize.check(MyApp.Repo, [{"users", "id"}], format: :hex)
      # => {:need_migration, [{{"users", "id"}, 2}, {{"posts", "user_id"}, 3}]}

  The result is `:no_migration_needed` when all checked values are canonical, or
  `{:need_migration, counts}` listing affected columns and their counts otherwise. The check also
  detects foreign keys and raises on invalid values. It does not test whether a rewrite would
  succeed, for example when two values canonicalize to the same unique key. Its results can become
  stale if other writers change the data.

  ## Foreign keys

  Only declared foreign key constraints in the same schema are detected, and they are followed in
  both directions: listing `posts.user_id` also changes `users.id` and everything else that
  references it. Related columns get the ID prefix of the column they are linked to. The detected
  columns are logged and included in the result of `run/3`.

  Columns that reference IDs without a constraint (polymorphic associations, `references: false`
  or references in application code) are not detected; list them yourself. Set
  `foreign_keys: false` to change only the listed columns. An omitted column protected by a
  same-schema foreign key then aborts the migration if the rewrite violates that constraint.

  On MySQL and MariaDB, do not use `run/3` or `up/2` on tables involved in cross-database foreign
  keys. Such constraints are not reliably checked while foreign key checks are disabled, so
  rewriting a referenced ID can leave orphaned rows in another database. Handle those relationships
  separately with a migration that preserves and validates them. `check/3` does not follow
  cross-database foreign keys; check those columns separately.

  ## Options

  - `:format` (required) the format of the columns: `:hex`, `:hex32` or `:url64`
  - `:prefix` the database schema (PostgreSQL) or database (MySQL) of the tables, defaults to the
    migration's prefix
  - `:foreign_keys` detect related foreign key columns (default `true`)
  - `:dry_run` for `run/3` and `up/2`, do everything, including all checks, but roll the changes back, and report the rows
    that would change in the log (default `false`). Use `run/3` to get them as a return value. The
    locks are held until the end of the surrounding transaction, so that is not free on large tables.

  ## How it works

  The helper updates the values with SQL in a single transaction, so the migration is atomic. How
  foreign keys are handled depends on the adapter:

  - **PostgreSQL** (`Ecto.Adapters.Postgres`): the tables are locked against writes, foreign keys
    that touch them are temporarily made deferrable, all columns are updated, and all constraints
    are validated. Afterwards the foreign key definitions are restored. The helper also makes all
    deferrable constraints immediate for the rest of the surrounding transaction, including
    unrelated constraints, and can fail if unrelated deferred changes are temporarily invalid.
  - **MySQL and MariaDB** (`Ecto.Adapters.MyXQL`): the rows of the tables are locked with
    `SELECT ... FOR UPDATE`, so writers wait until the migration commits, while readers keep seeing
    the old values. MySQL has no deferrable constraints, so `FOREIGN_KEY_CHECKS` is disabled for the
    session while the columns are updated. Before commit, the helper checks same-database foreign
    keys involving the tables for orphaned rows itself, and the setting is restored afterwards.
    Row locks also block inserts under the default `REPEATABLE READ` isolation level, but not under
    `READ COMMITTED`. Writers can hit their lock wait timeout while a large table is rewritten.

  Other adapters are not supported. Run this before upgrading to a Once version that rejects
  non-canonical values.

  ## Large tables

  Memory use in your application is constant: only counts and a few sample values come back from
  the database. The cost is in the database, and it grows with the number of rows that change:

  - **Writers are blocked** for the whole run: with a table lock on PostgreSQL, with row locks on
    MySQL, where writers can also hit their lock wait timeout. `LOCK TABLE` waits for running
    transactions that use the table, and statements that arrive meanwhile queue behind it.
  - **It is a single transaction**, as it has to be to stay atomic. On PostgreSQL every changed row
    and its index entries are rewritten, which means table and index bloat until `VACUUM`, a lot
    of WAL and replication lag; plan for more than twice the table and index size in free disk.
    On MySQL it means a large undo log, large binlog events and replica lag, and rolling back
    after a late failure takes a long time (see the dry run numbers below).
  - **PostgreSQL queues the deferred foreign key checks in server memory**, one per changed row
    per foreign key, until they run at the end. That is modest (about 30 MB for the measurements
    below) but grows with the number of changed rows.
  - **MySQL locks every row of the involved tables, even when nothing has to change**, so a
    repeat run on an already canonical table is much slower than on PostgreSQL.
  - Each table is scanned three times when it changes: to count and validate, to update, and to
    verify. A table that is already canonical is scanned once. A table with several columns is
    still rewritten in a single `UPDATE`.
  - A `dry_run` costs the same as the real run, and on MySQL more, as it has to undo its changes.
  - `SET FOREIGN_KEY_CHECKS` belongs to a session, so on MySQL use a direct connection, not a
    transaction-pooling proxy.

  ### Measurements

  Two tables with 1 million rows each, a foreign key between them and uppercase hex everywhere, so
  that the primary keys and the foreign key column (about 2.9 million values) all had to change.
  This ran in Docker on a laptop, with default settings: PostgreSQL 17.9 and MySQL 8.0.34 with
  binary logging on and a 128 MB buffer pool. Treat them as orders of magnitude, not as promises.

  |                          | PostgreSQL        | MySQL              |
  |--------------------------|-------------------|--------------------|
  | real run                 | 44 s              | 98 s               |
  | dry run                  | 45 s              | 164 s              |
  | repeat run, no changes   | 1.8 s             | 23 s               |
  | log written (real run)   | 870 MB WAL        | 101 MB binlog      |
  | table and index size     | 231 → 537 MB      | 375 → 565 MB       |
  | server memory, extra     | 31 MB (private)   | about 12 MB        |

  PostgreSQL's size growth is bloat that `VACUUM` has to reclaim; a dry run leaves the same bloat
  behind. The application's memory use did not depend on the number of rows.

  Rehearse on a copy of production data and pick a quiet period. If the tables are too large for
  that, use an online approach instead: write the canonical values to new columns in batches,
  then switch over.
  """

  @type format :: :hex | :hex32 | :url64
  @type column ::
          {table :: String.t(), column :: String.t()}
          | {table :: String.t(), column :: String.t(), id_prefix :: String.t()}
  @type check_opt ::
          {:format, format()}
          | {:prefix, String.t() | nil}
          | {:foreign_keys, boolean()}
  @type opt :: check_opt() | {:dry_run, boolean()}

  @hex32_alphabet "0123456789abcdefghijklmnopqrstuv"
  @url64_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

  # Maps every alphabet character to the one with its trailing bits cleared (the canonical last
  # character): 13 hex32 characters hold 65 bits, so 1 spare bit; 11 url64 characters, 2 spare bits.
  floor = fn alphabet, step ->
    chars = String.graphemes(alphabet)

    chars
    |> Enum.with_index()
    |> Enum.map_join(fn {_, i} -> Enum.at(chars, i - rem(i, step)) end)
  end

  @hex32_floor floor.(@hex32_alphabet, 2)
  @url64_floor floor.(@url64_alphabet, 4)

  @identifier ~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/
  # printable ASCII, excluding ' and \ so prefixes can be embedded in SQL string literals
  @id_prefix ~r/\A[\x20-\x26\x28-\x5B\x5D-\x7E]+\z/

  if Code.ensure_loaded?(Ecto.Migration) do
    @doc """
    Canonicalizes the columns from a migration. See the module documentation.
    """
    @spec up([column()], [opt()]) :: :ok
    def up(columns, opts) do
      repo = Ecto.Migration.repo()
      opts = Keyword.put_new(opts, :prefix, Ecto.Migration.prefix())
      # validate eagerly, so mistakes surface before any migration command runs
      {_, _, _, _} = validate!(repo, columns, opts)
      Ecto.Migration.execute(fn -> run(repo, columns, opts) end)
    end
  end

  @doc """
  Checks for non-canonical values without changing data or locking rows.

  Takes the same columns and options as `run/3`, except for `:dry_run`. Declared foreign keys in
  the same schema are included by default. Returns `:no_migration_needed` if all checked values
  are canonical, or `{:need_migration, counts}` with the number of non-canonical values in each
  affected column. Columns with no non-canonical values are omitted. `NULL` values are ignored;
  invalid values raise with examples. This does not check for collisions or foreign key violations
  during a rewrite. Concurrent writes can make the results stale.
  """
  @spec check(Ecto.Repo.t(), [column()], [check_opt()]) ::
          :no_migration_needed | {:need_migration, [{column(), pos_integer()}]}
  def check(repo, columns, opts) do
    if Keyword.has_key?(opts, :dry_run) do
      raise ArgumentError, "option :dry_run is not supported by check/3"
    end

    {dialect, format, schema, columns} = validate!(repo, columns, opts)

    columns =
      if Keyword.get(opts, :foreign_keys, true),
        do: expand_foreign_keys(dialect, repo, schema, columns),
        else: columns

    specs = Enum.map(columns, &column_spec(dialect, format, schema, &1))
    scans = scan_specs!(dialect, repo, specs, false)

    counts =
      for spec <- specs, count = scans[spec.relation][spec.key], count > 0, do: {spec.key, count}

    case counts do
      [] -> :no_migration_needed
      _ -> {:need_migration, counts}
    end
  end

  @doc """
  Canonicalizes the columns using `repo`, outside of a migration.

  Takes the same arguments as `up/2` and returns the number of changed rows per column, including
  the foreign key columns that were detected. With `dry_run: true` nothing is changed and the
  returned counts are the rows that would change.
  """
  @spec run(Ecto.Repo.t(), [column()], [opt()]) :: [{column(), non_neg_integer()}]
  def run(repo, columns, opts) do
    {dialect, format, schema, columns} = validate!(repo, columns, opts)
    detect? = Keyword.get(opts, :foreign_keys, true)
    dry_run? = Keyword.get(opts, :dry_run, false)

    {:ok, result} =
      repo.transaction(
        fn ->
          columns =
            if detect?, do: expand_foreign_keys(dialect, repo, schema, columns), else: columns

          specs = Enum.map(columns, &column_spec(dialect, format, schema, &1))

          # a savepoint, because rolling back a nested Ecto transaction aborts the outer one
          if dry_run?, do: query!(repo, "SAVEPOINT once_canonicalize")
          counts = do_run(dialect, repo, specs, schema)

          if dry_run? do
            query!(repo, "ROLLBACK TO SAVEPOINT once_canonicalize")
            query!(repo, "RELEASE SAVEPOINT once_canonicalize")
          end

          Logger.info(
            "Once.Canonicalize: " <>
              "#{if dry_run?, do: "dry run, rows that would change", else: "rows changed"}: " <>
              inspect(counts)
          )

          counts
        end,
        timeout: :infinity
      )

    result
  end

  ##############
  # Validation #
  ##############

  defp validate!(repo, columns, opts) do
    format = Keyword.get(opts, :format)
    schema = Keyword.get(opts, :prefix)

    if format not in [:hex, :hex32, :url64] do
      raise ArgumentError,
            "option :format must be :hex, :hex32 or :url64, got: #{inspect(format)}"
    end

    if columns == [] or not is_list(columns) do
      raise ArgumentError, "expected a non-empty list of {table, column} tuples"
    end

    if schema, do: identifier!(schema)

    if not is_boolean(Keyword.get(opts, :foreign_keys, true)) do
      raise ArgumentError, "option :foreign_keys must be a boolean"
    end

    if not is_boolean(Keyword.get(opts, :dry_run, false)) do
      raise ArgumentError, "option :dry_run must be a boolean"
    end

    columns = columns |> Enum.map(&normalize_column!/1) |> dedupe!()
    {dialect(repo), format, schema, columns}
  end

  # a column can only be assigned once per UPDATE
  defp dedupe!(columns) do
    Enum.reduce(columns, [], fn column, acc ->
      case Enum.find(acc, &(&1.table == column.table and &1.column == column.column)) do
        nil ->
          acc ++ [column]

        ^column ->
          acc

        other ->
          raise ArgumentError,
                "column #{inspect({column.table, column.column})} is listed with different ID " <>
                  "prefixes: #{inspect(other.id_prefix)} and #{inspect(column.id_prefix)}"
      end
    end)
  end

  defp normalize_column!({table, column}), do: normalize_column!({table, column, nil})

  defp normalize_column!({table, column, id_prefix}) do
    if id_prefix != nil and not (is_binary(id_prefix) and Regex.match?(@id_prefix, id_prefix)) do
      raise ArgumentError,
            "an ID prefix must be printable ASCII without ' or \\, got: #{inspect(id_prefix)}"
    end

    %{table: identifier!(table), column: identifier!(column), id_prefix: id_prefix}
  end

  defp normalize_column!(other) do
    raise ArgumentError,
          "expected {table, column} or {table, column, id_prefix}, got: #{inspect(other)}"
  end

  defp identifier!(name) do
    if is_binary(name) and Regex.match?(@identifier, name) do
      name
    else
      raise ArgumentError, "invalid table, column or prefix name: #{inspect(name)}"
    end
  end

  defp dialect(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        :postgres

      Ecto.Adapters.MyXQL ->
        :mysql

      other ->
        raise ArgumentError,
              "unsupported adapter #{inspect(other)}, supported are " <>
                "Ecto.Adapters.Postgres and Ecto.Adapters.MyXQL"
    end
  end

  ###############
  # Foreign keys #
  ###############

  # Grows the columns along declared foreign keys, in both directions: a foreign key column holds
  # the same values as the column it references, so they have to change together. Related columns
  # inherit the persisted ID prefix.
  defp expand_foreign_keys(dialect, repo, schema, columns) do
    edges = foreign_key_pairs(dialect, repo, schema)
    known = Map.new(columns, &{{&1.table, &1.column}, &1})
    grown = grow(known, edges)

    Enum.each(edges, fn {child, parent} ->
      with %{id_prefix: a} <- grown[child], %{id_prefix: b} <- grown[parent], true <- a != b do
        raise ArgumentError,
              "foreign key #{inspect(child)} -> #{inspect(parent)} links columns with different " <>
                "ID prefixes: #{inspect(a)} and #{inspect(b)}"
      end
    end)

    detected = grown |> Map.drop(Map.keys(known)) |> Enum.sort() |> Enum.map(&elem(&1, 1))

    if detected != [] do
      Logger.info(
        "Once.Canonicalize: also canonicalizing foreign key columns " <>
          inspect(Enum.map(detected, &{&1.table, &1.column}))
      )
    end

    Enum.uniq_by(columns, &{&1.table, &1.column}) ++ detected
  end

  defp grow(known, edges) do
    grown =
      Enum.reduce(edges, known, fn {child, parent}, acc ->
        cond do
          is_map_key(acc, parent) and not is_map_key(acc, child) ->
            put_related(acc, child, acc[parent])

          is_map_key(acc, child) and not is_map_key(acc, parent) ->
            put_related(acc, parent, acc[child])

          true ->
            acc
        end
      end)

    if map_size(grown) == map_size(known), do: known, else: grow(grown, edges)
  end

  defp put_related(columns, {table, column}, %{id_prefix: id_prefix}) do
    Map.put(columns, {table, column}, %{table: table, column: column, id_prefix: id_prefix})
  end

  # all foreign key column pairs in the schema as [{{child_table, child_column}, {parent_table, parent_column}}]
  defp foreign_key_pairs(:postgres, repo, schema) do
    %{rows: rows} =
      query!(
        repo,
        """
        SELECT c.relname, a.attname, p.relname, pa.attname
        FROM pg_constraint con
        CROSS JOIN LATERAL unnest(con.conkey, con.confkey) AS k(attnum, fattnum)
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_class p ON p.oid = con.confrelid
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
        JOIN pg_attribute pa ON pa.attrelid = con.confrelid AND pa.attnum = k.fattnum
        WHERE con.contype = 'f' AND c.relnamespace = p.relnamespace
          AND c.relnamespace = (
            SELECT oid FROM pg_namespace WHERE nspname = COALESCE($1::text, current_schema())
          )
        """,
        [schema]
      )

    pairs(rows)
  end

  defp foreign_key_pairs(:mysql, repo, schema) do
    schema_sql = if schema, do: "'#{schema}'", else: "DATABASE()"

    %{rows: rows} =
      query!(repo, """
      SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = #{schema_sql} AND REFERENCED_TABLE_SCHEMA = #{schema_sql}
        AND REFERENCED_TABLE_NAME IS NOT NULL
      """)

    pairs(rows)
  end

  defp pairs(rows), do: Enum.map(rows, fn [ct, cc, pt, pc] -> {{ct, cc}, {pt, pc}} end)

  ###############
  # Adapter flow #
  ###############

  defp do_run(:postgres, repo, specs, _schema) do
    relations = specs |> Enum.map(& &1.relation) |> Enum.uniq() |> Enum.sort()

    query!(repo, "LOCK TABLE #{Enum.join(relations, ", ")} IN SHARE ROW EXCLUSIVE MODE")

    # foreign keys can only be deferred if they are deferrable
    %{rows: fks} =
      query!(
        repo,
        """
        SELECT con.conrelid::regclass::text, con.conname
        FROM pg_constraint con
        WHERE con.contype = 'f' AND NOT con.condeferrable
          AND (con.conrelid = ANY ($1::text[]::regclass[])
            OR con.confrelid = ANY ($1::text[]::regclass[]))
        """,
        [relations]
      )

    for [relation, name] <- fks do
      query!(
        repo,
        "ALTER TABLE #{relation} ALTER CONSTRAINT #{quote_ident(:postgres, name)} " <>
          "DEFERRABLE INITIALLY IMMEDIATE"
      )
    end

    query!(repo, "SET CONSTRAINTS ALL DEFERRED")
    counts = update_and_verify(:postgres, repo, specs)
    # validates all foreign keys, raising on violations
    query!(repo, "SET CONSTRAINTS ALL IMMEDIATE")

    for [relation, name] <- fks do
      query!(
        repo,
        "ALTER TABLE #{relation} ALTER CONSTRAINT #{quote_ident(:postgres, name)} NOT DEFERRABLE"
      )
    end

    counts
  end

  defp do_run(:mysql, repo, specs, schema) do
    query!(repo, "SET FOREIGN_KEY_CHECKS = 0")

    try do
      counts = update_and_verify(:mysql, repo, specs)
      check_orphans!(repo, specs, schema)
      counts
    after
      query!(repo, "SET FOREIGN_KEY_CHECKS = 1")
    end
  end

  # Every table is read once to count and validate, before anything is written, so bad data fails
  # early. On MySQL that read also locks the rows, in a fixed order. Each table that needs changes
  # then gets a single UPDATE for all of its columns, which rewrites every row once, and is
  # verified afterwards.
  defp update_and_verify(dialect, repo, specs) do
    groups = group_by_relation(specs)
    scans = scan_specs!(dialect, repo, specs, true)

    changed =
      Enum.flat_map(groups, fn {relation, group} ->
        case Enum.filter(group, &(scans[relation][&1.key] > 0)) do
          [] -> []
          changing -> [{relation, changing}]
        end
      end)

    for {relation, changing} <- changed, do: query!(repo, update_sql(dialect, relation, changing))
    for {relation, changing} <- changed, do: verify!(dialect, repo, relation, changing)

    for spec <- specs, do: {spec.key, scans[spec.relation][spec.key]}
  end

  defp group_by_relation(specs) do
    specs
    |> Enum.map(& &1.relation)
    |> Enum.uniq()
    |> Enum.map(fn relation -> {relation, Enum.filter(specs, &(&1.relation == relation))} end)
  end

  defp scan_specs!(dialect, repo, specs, lock?) do
    for {relation, group} <- specs |> group_by_relation() |> Enum.sort_by(&elem(&1, 0)),
        into: %{} do
      {relation, scan!(dialect, repo, relation, group, lock?)}
    end
  end

  # returns the number of rows to change per column, raises if a column has unfixable values
  defp scan!(dialect, repo, relation, group, lock?) do
    selects =
      Enum.flat_map(group, fn spec ->
        [
          "COUNT(CASE WHEN #{change_cond(dialect, spec)} THEN 1 END)",
          "COUNT(CASE WHEN #{invalid_cond(dialect, spec)} THEN 1 END)"
        ]
      end)

    lock = if dialect == :mysql and lock?, do: " FOR UPDATE", else: ""
    %{rows: [row]} = query!(repo, "SELECT #{Enum.join(selects, ", ")} FROM #{relation}#{lock}")

    group
    |> Enum.zip(Enum.chunk_every(row, 2))
    |> Map.new(fn {spec, [changing, invalid]} ->
      if invalid > 0, do: raise_invalid!(repo, spec, invalid, invalid_cond(dialect, spec))
      {spec.key, changing}
    end)
  end

  # checks what was actually stored
  defp verify!(dialect, repo, relation, changing) do
    selects =
      Enum.map(changing, &"COUNT(CASE WHEN #{invalid_after_cond(dialect, &1)} THEN 1 END)")

    %{rows: [row]} = query!(repo, "SELECT #{Enum.join(selects, ", ")} FROM #{relation}")

    for {spec, invalid} <- Enum.zip(changing, row), invalid > 0 do
      raise_invalid!(repo, spec, invalid, invalid_after_cond(dialect, spec))
    end
  end

  defp raise_invalid!(repo, spec, invalid, condition) do
    %{rows: samples} =
      query!(repo, "SELECT #{spec.col} FROM #{spec.relation} WHERE #{condition} LIMIT 3")

    raise "Once.Canonicalize: #{invalid} value(s) in #{inspect(spec.key)} are not valid " <>
            "#{spec.format} IDs and cannot be canonicalized, for example: " <>
            inspect(List.flatten(samples))
  end

  # MySQL does not validate foreign keys when FOREIGN_KEY_CHECKS is re-enabled, so do it ourselves
  defp check_orphans!(repo, specs, schema) do
    tables = specs |> Enum.map(& &1.table) |> Enum.uniq()
    list = Enum.map_join(tables, ", ", &"'#{&1}'")
    schema_sql = if schema, do: "'#{schema}'", else: "DATABASE()"

    %{rows: rows} =
      query!(repo, """
      SELECT CONSTRAINT_NAME, TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = #{schema_sql} AND REFERENCED_TABLE_NAME IS NOT NULL
        AND (TABLE_NAME IN (#{list}) OR REFERENCED_TABLE_NAME IN (#{list}))
      ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
      """)

    rows
    |> Enum.group_by(fn [name, table, _, ref_table, _] -> {name, table, ref_table} end)
    |> Enum.each(fn {{name, table, ref_table}, parts} ->
      child = qualified(:mysql, schema, table)
      parent = qualified(:mysql, schema, ref_table)

      on =
        Enum.map_join(parts, " AND ", fn [_, _, col, _, ref_col] ->
          "c.#{quote_ident(:mysql, col)} = p.#{quote_ident(:mysql, ref_col)}"
        end)

      not_null =
        Enum.map_join(parts, " AND ", fn [_, _, col, _, _] ->
          "c.#{quote_ident(:mysql, col)} IS NOT NULL"
        end)

      [_, _, _, _, first_ref] = hd(parts)

      %{rows: [[orphans]]} =
        query!(repo, """
        SELECT COUNT(*) FROM #{child} c LEFT JOIN #{parent} p ON #{on}
        WHERE #{not_null} AND p.#{quote_ident(:mysql, first_ref)} IS NULL
        """)

      if orphans > 0 do
        raise "Once.Canonicalize: foreign key #{name} on #{table} would be violated by " <>
                "#{orphans} row(s). Add every column that holds or references these IDs " <>
                "to the list."
      end
    end)
  end

  #######
  # SQL #
  #######

  defp column_spec(dialect, format, schema, %{table: table, column: column, id_prefix: prefix}) do
    col = quote_ident(dialect, column)
    {value, prefix_guards} = strip_prefix(dialect, col, prefix)
    canonical = canonical_sql(dialect, format, value)
    new = if prefix, do: "CONCAT('#{prefix}', #{canonical})", else: canonical

    %{
      key: if(prefix, do: {table, column, prefix}, else: {table, column}),
      table: table,
      relation: qualified(dialect, schema, table),
      col: col,
      format: format,
      value: value,
      canonical: canonical,
      new: new,
      guard: Enum.join(prefix_guards ++ [shape_sql(dialect, format, value)], " AND ")
    }
  end

  defp strip_prefix(_, col, nil), do: {col, []}

  defp strip_prefix(dialect, col, prefix) do
    len = String.length(prefix)

    {"SUBSTR(#{col}, #{len + 1})",
     ["#{bin(dialect, "LEFT(#{col}, #{len})")} = #{bin(dialect, "'#{prefix}'")}"]}
  end

  # one UPDATE for all columns of a table; a column is only assigned in the rows where it changes
  defp update_sql(dialect, relation, specs) do
    sets =
      Enum.map_join(specs, ", ", fn spec ->
        "#{spec.col} = CASE WHEN #{change_cond(dialect, spec)} THEN #{spec.new} ELSE #{spec.col} END"
      end)

    where = Enum.map_join(specs, " OR ", &"(#{change_cond(dialect, &1)})")
    "UPDATE #{relation} SET #{sets} WHERE #{where}"
  end

  # rows that have to change
  defp change_cond(dialect, spec) do
    "#{spec.col} IS NOT NULL AND #{spec.guard} " <>
      "AND #{bin(dialect, spec.col)} <> #{bin(dialect, spec.new)}"
  end

  # before the update: rows that can never become a canonical, valid ID
  defp invalid_cond(dialect, spec) do
    "#{spec.col} IS NOT NULL AND NOT (#{spec.guard} AND " <>
      "#{spec.canonical} #{regex_op(dialect)} '#{pattern(spec.format)}')"
  end

  # after the update: rows that are not a canonical, valid ID
  defp invalid_after_cond(dialect, spec) do
    "#{spec.col} IS NOT NULL AND NOT (#{spec.guard} AND #{bin(dialect, spec.col)} = " <>
      "#{bin(dialect, spec.new)} AND #{spec.value} #{regex_op(dialect)} '#{pattern(spec.format)}')"
  end

  # the value has the right length and its last character exists in the alphabet,
  # so the canonical expression is well-defined
  defp shape_sql(_, :hex, v), do: "CHAR_LENGTH(#{v}) = 16 AND OCTET_LENGTH(#{v}) = 16"

  defp shape_sql(dialect, :hex32, v) do
    "CHAR_LENGTH(#{v}) = 13 AND OCTET_LENGTH(#{v}) = 13 " <>
      "AND #{position(dialect, "RIGHT(LOWER(#{v}), 1)", @hex32_alphabet)} > 0"
  end

  defp shape_sql(dialect, :url64, v) do
    "CHAR_LENGTH(#{v}) = 11 AND OCTET_LENGTH(#{v}) = 11 " <>
      "AND #{position(dialect, "RIGHT(#{v}, 1)", @url64_alphabet)} > 0"
  end

  defp canonical_sql(_, :hex, v), do: "LOWER(#{v})"

  defp canonical_sql(dialect, :hex32, v) do
    lower = "LOWER(#{v})"
    last = position(dialect, "RIGHT(#{lower}, 1)", @hex32_alphabet)
    "CONCAT(LEFT(#{lower}, 12), SUBSTR('#{@hex32_floor}', #{last}, 1))"
  end

  defp canonical_sql(dialect, :url64, v) do
    last = position(dialect, "RIGHT(#{v}, 1)", @url64_alphabet)
    "CONCAT(LEFT(#{v}, 10), SUBSTR('#{@url64_floor}', #{last}, 1))"
  end

  defp pattern(:hex), do: "^[0-9a-f]{16}$"
  defp pattern(:hex32), do: "^[0-9a-v]{12}[02468acegikmoqsu]$"
  defp pattern(:url64), do: "^[A-Za-z0-9_-]{10}[AEIMQUYcgkosw048]$"

  defp position(dialect, needle, alphabet) do
    "POSITION(#{bin(dialect, needle)} IN #{bin(dialect, "'#{alphabet}'")})"
  end

  # compare bytewise: MySQL string comparisons depend on the column's collation, which is usually
  # case-insensitive
  defp bin(:postgres, sql), do: sql
  defp bin(:mysql, sql), do: "CAST(#{sql} AS BINARY)"

  defp regex_op(:postgres), do: "~"
  defp regex_op(:mysql), do: "REGEXP"

  defp quote_ident(:postgres, name), do: ~s("#{String.replace(name, "\"", "\"\"")}")
  defp quote_ident(:mysql, name), do: "`#{name}`"

  defp qualified(dialect, nil, table), do: quote_ident(dialect, table)

  defp qualified(dialect, schema, table),
    do: "#{quote_ident(dialect, schema)}.#{quote_ident(dialect, table)}"

  defp query!(repo, sql, params \\ []), do: repo.query!(sql, params, timeout: :infinity)
end
