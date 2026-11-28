defmodule MyApp.MysqlRepo.Migrations.VariantTables do
  use Ecto.Migration

  # Empty tables for the foreign key variants that Once.Canonicalize must handle. The tests insert
  # non-canonical rows themselves, inside a transaction that is rolled back.
  def change do
    # self-referencing
    create table("canonical_nodes", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:parent_id, :string, size: 16)
    end

    execute(
      """
      ALTER TABLE canonical_nodes ADD CONSTRAINT canonical_nodes_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES canonical_nodes (id)
      """,
      "ALTER TABLE canonical_nodes DROP FOREIGN KEY canonical_nodes_parent_id_fkey"
    )

    # multi-column foreign key, with columns of different formats; binary collations, so the
    # columns are case-sensitive, like the url64 columns in the other fixtures
    create table("canonical_orgs", primary_key: false) do
      add(:a_id, :string, size: 16, null: false, collation: "utf8mb4_bin")
      add(:b_id, :string, size: 13, null: false, collation: "utf8mb4_bin")
    end

    create(unique_index("canonical_orgs", [:a_id, :b_id]))

    create table("canonical_members", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:a_id, :string, size: 16, collation: "utf8mb4_bin")
      add(:b_id, :string, size: 13, collation: "utf8mb4_bin")
    end

    execute(
      """
      ALTER TABLE canonical_members ADD CONSTRAINT canonical_members_org_fkey
      FOREIGN KEY (a_id, b_id) REFERENCES canonical_orgs (a_id, b_id)
      """,
      "ALTER TABLE canonical_members DROP FOREIGN KEY canonical_members_org_fkey"
    )

    # ON UPDATE CASCADE (MySQL has no deferrable foreign keys)
    create table("canonical_roots", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
    end

    create table("canonical_cascade", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:root_id, :string, size: 16)
    end

    execute(
      """
      ALTER TABLE canonical_cascade ADD CONSTRAINT canonical_cascade_root_id_fkey
      FOREIGN KEY (root_id) REFERENCES canonical_roots (id) ON UPDATE CASCADE
      """,
      "ALTER TABLE canonical_cascade DROP FOREIGN KEY canonical_cascade_root_id_fkey"
    )

    # The same table names in another database, to verify that the :prefix option picks the
    # database. It is not dropped along with the test database, so start from scratch.
    execute("DROP DATABASE IF EXISTS canon_alt", "DROP DATABASE IF EXISTS canon_alt")
    execute("CREATE DATABASE canon_alt", "DROP DATABASE IF EXISTS canon_alt")

    create table("canonical_parents", prefix: "canon_alt", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
    end

    create table("canonical_children", prefix: "canon_alt", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:parent_id, :string, size: 16)
    end

    execute(
      """
      ALTER TABLE canon_alt.canonical_children ADD CONSTRAINT canonical_children_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES canon_alt.canonical_parents (id)
      """,
      "ALTER TABLE canon_alt.canonical_children DROP FOREIGN KEY canonical_children_parent_id_fkey"
    )
  end
end
