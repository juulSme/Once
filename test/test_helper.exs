ExUnit.start()
{:ok, _} = Supervisor.start_link([MyApp.PgRepo, MyApp.MysqlRepo], strategy: :one_for_one)

Ecto.Adapters.SQL.Sandbox.mode(MyApp.PgRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(MyApp.MysqlRepo, :manual)

base_key =
  <<93, 198, 179, 97, 145, 106, 54, 165, 219, 77, 223, 54, 58, 16, 164, 222, 242, 214, 181, 143,
    10, 19, 20, 51, 63, 238, 38, 150, 45, 183, 153, 69>>

NoNoncense.init(name: Once, machine_id: 0, base_key: base_key)
