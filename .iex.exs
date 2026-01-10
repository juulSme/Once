key = :crypto.strong_rand_bytes(32)
NoNoncense.init(name: Once, machine_id: 0, base_key: key)

{:ok, _} = Supervisor.start_link([MyApp.PgRepo, MyApp.MysqlRepo], strategy: :one_for_one)

alias MyApp.{MysqlRepo, PgRepo, Schema}
import Ecto.Query
alias Once.{Prefixed}

opts = Once.init()
masked_opts = Once.init(masked: true)
prefix_opts = Once.init(prefix: "prfx_")
masked_prefix_opts = Once.init(prefix: "prfx_", masked: true)
