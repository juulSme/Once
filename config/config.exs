import Config

config :once, ecto_repos: [MyApp.MysqlRepo, MyApp.PgRepo]

config :once, MyApp.MysqlRepo,
  host: "localhost",
  port: System.get_env("MYSQL_PORT", "3306") |> String.to_integer(),
  username: "root",
  password: "supersecret",
  database: "once",
  pool: DBConnection.ConnectionPool

config :once, MyApp.PgRepo,
  host: "localhost",
  port: System.get_env("PG_PORT", "5432") |> String.to_integer(),
  username: "postgres",
  password: "supersecret",
  database: "once",
  pool: DBConnection.ConnectionPool

import_config("#{Mix.env()}.exs")
