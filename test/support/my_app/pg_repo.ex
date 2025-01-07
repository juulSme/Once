defmodule MyApp.PgRepo do
  use Ecto.Repo, otp_app: :no_noncense_id, adapter: Ecto.Adapters.Postgres
end
