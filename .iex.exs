NoNoncense.init(name: NoNoncenseID, machine_id: 0)
{:ok, _} = Supervisor.start_link([MyApp.PgRepo, MyApp.MysqlRepo], strategy: :one_for_one)

alias MyApp.{MysqlRepo, PgRepo, Schema}
import Ecto.Query
