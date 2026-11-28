defmodule MyApp.PgRepo.Migrations.VariantTables do
  use Ecto.Migration

  # Empty tables for the foreign key variants that Once.Canonicalize must handle. The tests insert
  # non-canonical rows themselves, inside a transaction that is rolled back.
  def change do
    # self-referencing
    create table("canonical_nodes", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:parent_id, references("canonical_nodes", column: :id, type: :string))
    end

    # multi-column foreign key, with columns of different formats
    create table("canonical_orgs", primary_key: false) do
      add(:a_id, :string, size: 16, null: false)
      add(:b_id, :string, size: 13, null: false)
    end

    create(unique_index("canonical_orgs", [:a_id, :b_id]))

    create table("canonical_members", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:a_id, :string, size: 16)
      add(:b_id, :string, size: 13)
    end

    execute(
      """
      ALTER TABLE canonical_members ADD CONSTRAINT canonical_members_org_fkey
      FOREIGN KEY (a_id, b_id) REFERENCES canonical_orgs (a_id, b_id)
      """,
      "ALTER TABLE canonical_members DROP CONSTRAINT canonical_members_org_fkey"
    )

    # ON UPDATE CASCADE, and a foreign key that is already deferrable
    create table("canonical_roots", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
    end

    create table("canonical_cascade", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:root_id, :string, size: 16)
    end

    create table("canonical_deferred", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:root_id, :string, size: 16)
    end

    execute(
      """
      ALTER TABLE canonical_cascade ADD CONSTRAINT canonical_cascade_root_id_fkey
      FOREIGN KEY (root_id) REFERENCES canonical_roots (id) ON UPDATE CASCADE
      """,
      "ALTER TABLE canonical_cascade DROP CONSTRAINT canonical_cascade_root_id_fkey"
    )

    execute(
      """
      ALTER TABLE canonical_deferred ADD CONSTRAINT canonical_deferred_root_id_fkey
      FOREIGN KEY (root_id) REFERENCES canonical_roots (id) DEFERRABLE INITIALLY DEFERRED
      """,
      "ALTER TABLE canonical_deferred DROP CONSTRAINT canonical_deferred_root_id_fkey"
    )

    # the same table names in another schema, to verify that the :prefix option picks the schema
    execute("CREATE SCHEMA canon_alt", "DROP SCHEMA canon_alt CASCADE")

    create table("canonical_parents", prefix: "canon_alt", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
    end

    create table("canonical_children", prefix: "canon_alt", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)

      add(
        :parent_id,
        references("canonical_parents", prefix: "canon_alt", column: :id, type: :string)
      )
    end
  end
end
