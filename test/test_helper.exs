ExUnit.start()
{:ok, _} = Supervisor.start_link([MyApp.PgRepo, MyApp.MysqlRepo], strategy: :one_for_one)

Ecto.Adapters.SQL.Sandbox.mode(MyApp.PgRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(MyApp.MysqlRepo, :manual)

NoNoncense.init(name: Once, machine_id: 0)
