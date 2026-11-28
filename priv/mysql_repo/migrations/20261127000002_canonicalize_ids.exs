defmodule MyApp.MysqlRepo.Migrations.CanonicalizeIds do
  use Ecto.Migration

  # Only the columns that are not (or not only) foreign keys are listed. The foreign key columns
  # parent_id, parent_id32, parent_id64, parent_pid and child_id are detected, and
  # canonical_children.id is listed so that child_id, which references it, is found too.
  def up do
    Once.Canonicalize.up(
      [
        {"canonical_parents", "id"},
        {"canonical_children", "id"},
        {"canonical_grandchildren", "id"}
      ],
      format: :hex
    )

    Once.Canonicalize.up([{"canonical_parents", "id32"}], format: :hex32)
    Once.Canonicalize.up([{"canonical_parents", "id64"}], format: :url64)
    Once.Canonicalize.up([{"canonical_parents", "pid", "usr_"}], format: :hex)
  end

  def down, do: raise(Ecto.MigrationError, message: "irreversible")
end
