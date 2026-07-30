defmodule BackBreeze.MixProject do
  use Mix.Project

  @version "0.4.2"

  def project do
    [
      app: :back_breeze,
      description: "A terminal layout rendering library.",
      package: package(),
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "BackBreeze",
      source_url: "https://github.com/Gazler/back_breeze",
      docs: [
        source_ref: "v#{@version}",
        extras: [
          "CHANGELOG.md",
          "README.md"
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :os_mon],
      mod: {BackBreeze.Application, []}
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENCE.md),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Gazler/back_breeze"}
    ]
  end

  defp deps do
    [
      {:termite, "~> 0.4.2 or ~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
