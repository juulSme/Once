defmodule NoNoncenseID.MixProject do
  use Mix.Project

  def project do
    [
      app: :no_noncense_id,
      version: "0.0.0+development",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description: """
      Generate globally unique nonces in distributed Elixir
      """,
      package: [
        licenses: ["Apache-2.0"],
        links: %{github: "https://github.com/juulSme/NoNoncenseID"},
        source_url: "https://github.com/juulSme/NoNoncenseID",
        exclude_patterns: ["priv"]
      ],
      source_url: "https://github.com/juulSme/NoNoncenseID",
      name: "NoNoncenseID",
      docs: [
        source_ref: ~s(main),
        extras: ~w(./README.md ./LICENSE.md),
        main: "NoNoncenseID",
        skip_undefined_reference_warnings_on: ~w(),
        filter_modules: ~r(^Elixir\.NoNoncenseID\.?.*)
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.36", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: [:dev], runtime: false},
      {:no_noncense, "~> 0.0"},
      {:ecto, "~> 3.0"},
      {:mix_test_watch, "~> 1.2", only: [:dev], runtime: false},
      {:ecto_sql, "~> 3.4", only: [:dev, :test]},
      {:postgrex, "~> 0.1", only: [:dev, :test]},
      {:myxql, "~> 0.1", only: [:dev, :test]}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
