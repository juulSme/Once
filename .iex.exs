NoNoncense.init(name: Once, machine_id: 0)
{:ok, _} = Supervisor.start_link([MyApp.PgRepo, MyApp.MysqlRepo], strategy: :one_for_one)

alias MyApp.{MysqlRepo, PgRepo, Schema}
import Ecto.Query
alias Once.{Prefixed}

prefix_opts = Prefixed.init(prefix: "prfx_")
