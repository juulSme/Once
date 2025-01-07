import Config

config :once, ecto_repos: [MyApp.MysqlRepo, MyApp.PgRepo]

config :once, MyApp.MysqlRepo,
  host: "localhost",
  port: 3306,
  username: "root",
  password: "supersecret",
  database: "no_noncense",
  pool: Ecto.Adapters.SQL.Sandbox

config :once, MyApp.PgRepo,
  host: "localhost",
  port: 5432,
  username: "postgres",
  password: "supersecret",
  database: "no_noncense",
  pool: Ecto.Adapters.SQL.Sandbox
