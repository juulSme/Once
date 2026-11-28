import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :once, MyApp.MysqlRepo,
  database: "once_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false,
  socket_options: [nodelay: true]

config :once, MyApp.PgRepo,
  database: "once_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false,
  socket_options: [nodelay: true]
