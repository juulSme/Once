defmodule MyApp.MysqlRepo.Migrations.PrefixedInteger do
  use Ecto.Migration

  def change do
    alter table("test_table") do
      add(:prefixed_unsigned_id, :string)
      add(:prefixed_signed_id, :string)
    end
  end
end
