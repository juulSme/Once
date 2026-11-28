defmodule MyApp.PgRepo.Migrations.NoncanonicalIds do
  use Ecto.Migration

  # Two tables linked by foreign keys, filled with non-canonical IDs on purpose:
  #   id    hex     uppercase and mixed case
  #   id32  hex32   uppercase and a set trailing bit
  #   id64  url64   a set trailing bit
  #   pid   hex     uppercase, with the persisted prefix "usr_"
  # The third parent row is already canonical and must not be touched.
  def change do
    create table("canonical_parents", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:id32, :string, size: 13, null: false)
      add(:id64, :string, size: 11, null: false)
      add(:pid, :string, size: 20, null: false)
    end

    create(unique_index("canonical_parents", [:id32]))
    create(unique_index("canonical_parents", [:id64]))
    create(unique_index("canonical_parents", [:pid]))

    create table("canonical_children", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:parent_id, references("canonical_parents", column: :id, type: :string))
      add(:parent_id32, references("canonical_parents", column: :id32, type: :string))
      add(:parent_id64, references("canonical_parents", column: :id64, type: :string))
      add(:parent_pid, references("canonical_parents", column: :pid, type: :string))
    end

    create table("canonical_grandchildren", primary_key: false) do
      add(:id, :string, size: 16, primary_key: true)
      add(:child_id, references("canonical_children", column: :id, type: :string))
    end

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
