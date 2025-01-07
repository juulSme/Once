import Config

config :no_noncense_id, ecto_repos: [MyApp.MysqlRepo, MyApp.PgRepo]

config :no_noncense_id, MyApp.MysqlRepo,
  host: "localhost",
  port: 3306,
  username: "root",
  password: "supersecret",
  database: "no_noncense",
  pool: Ecto.Adapters.SQL.Sandbox

config :no_noncense_id, MyApp.PgRepo,
  host: "localhost",
  port: 5432,
  username: "postgres",
  password: "supersecret",
  database: "no_noncense",
  pool: Ecto.Adapters.SQL.Sandbox
