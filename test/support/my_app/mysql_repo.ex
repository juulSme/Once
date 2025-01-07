defmodule MyApp.MysqlRepo do
  use Ecto.Repo, otp_app: :once, adapter: Ecto.Adapters.MyXQL
end
