defmodule BackBreeze.MixProject do
  use Mix.Project

  def project do
    [
      app: :back_breeze,
      description: "Styling helpers for terminal applications",
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.17-rc",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENCE.md),
      licenses: ["MIT"],
      links: %{}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:termite, path: "../termite"}
    ]
  end
end
