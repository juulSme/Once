defmodule MyApp.MysqlRepo.Migrations.NoncanonicalIds do
  use Ecto.Migration

  # Two tables linked by foreign keys, filled with non-canonical IDs on purpose:
  #   id    hex     uppercase and mixed case
  #   id32  hex32   uppercase and a set trailing bit
  #   id64  url64   a set trailing bit
  #   pid   hex     uppercase, with the persisted prefix "usr_"
  # The third parent row is already canonical and must not be touched.
  #
  # Like MySQL's default, the hex columns use a case-insensitive collation. The url64 columns
  # must be case-sensitive, so they use a binary collation.
  def change do
    create table("canonical_parents", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:id32, :string, size: 13, null: false)
      add(:id64, :string, size: 11, null: false, collation: "utf8mb4_bin")
      add(:pid, :string, size: 20, null: false)
    end

    create(unique_index("canonical_parents", [:id32]))
    create(unique_index("canonical_parents", [:id64]))
    create(unique_index("canonical_parents", [:pid]))

    create table("canonical_children", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:parent_id, :string, size: 16)
      add(:parent_id32, :string, size: 13)
      add(:parent_id64, :string, size: 11, collation: "utf8mb4_bin")
      add(:parent_pid, :string, size: 20)
    end

    for {column, parent_column} <- [
          {"parent_id", "id"},
          {"parent_id32", "id32"},
          {"parent_id64", "id64"},
          {"parent_pid", "pid"}
        ] do
      execute(
        """
        ALTER TABLE canonical_children ADD CONSTRAINT canonical_children_#{column}_fkey
        FOREIGN KEY (#{column}) REFERENCES canonical_parents (#{parent_column})
        """,
        "ALTER TABLE canonical_children DROP FOREIGN KEY canonical_children_#{column}_fkey"
      )
    end

    create table("canonical_grandchildren", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:child_id, :string, size: 16)
    end

    execute(
      """
      ALTER TABLE canonical_grandchildren ADD CONSTRAINT canonical_grandchildren_child_id_fkey
      FOREIGN KEY (child_id) REFERENCES canonical_children (id)
      """,
      "ALTER TABLE canonical_grandchildren DROP FOREIGN KEY canonical_grandchildren_child_id_fkey"
    )

    execute(
      """
      INSERT INTO canonical_parents (id, id32, id64, pid) VALUES
        ('ABCDEF0123456789', 'PG4E2VCSG0003', 'AAAAAAAAAAB', 'usr_ABCDEF0123456789'),
        ('AbCdEf9876543210', '0000000000001', '__________9', 'usr_AbCdEf9876543210'),
        ('00000000000000aa', 'vvvvvvvvvvvvu', 'AAAAAAAAAAE', 'usr_00000000000000aa')
      """,
      "DELETE FROM canonical_parents"
    )

    execute(
      """
      INSERT INTO canonical_children (id, parent_id, parent_id32, parent_id64, parent_pid) VALUES
        ('FFFFFFFF00000001', 'ABCDEF0123456789', 'PG4E2VCSG0003', 'AAAAAAAAAAB', 'usr_ABCDEF0123456789'),
        ('Ffffffff00000002', 'AbCdEf9876543210', '0000000000001', '__________9', 'usr_AbCdEf9876543210'),
        ('ffffffff00000003', '00000000000000aa', 'vvvvvvvvvvvvu', 'AAAAAAAAAAE', 'usr_00000000000000aa'),
        ('FFFFFFFF00000004', NULL, NULL, NULL, NULL),
        ('FFFFFFFF00000005', 'ABCDEF0123456789', 'PG4E2VCSG0003', 'AAAAAAAAAAB', 'usr_ABCDEF0123456789')
      """,
      "DELETE FROM canonical_children"
    )

    execute(
      """
      INSERT INTO canonical_grandchildren (id, child_id) VALUES
        ('AAAAAAAA00000001', 'FFFFFFFF00000001'),
        ('aaaaaaaa00000002', 'Ffffffff00000002'),
        ('AAAAAAAA00000003', NULL)
      """,
      "DELETE FROM canonical_grandchildren"
    )
  end
end
