defmodule MyApp.MysqlRepo do
  use Ecto.Repo, otp_app: :no_noncense_id, adapter: Ecto.Adapters.MyXQL
end
