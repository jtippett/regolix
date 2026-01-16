defmodule Regolix.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jtippett/regolix"

  def project do
    [
      app: :regolix,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.37.1"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Elixir wrapper for Regorus, a fast Rego policy engine written in Rust."
  end

  defp package do
    [
      name: "regolix",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Regorus" => "https://github.com/microsoft/regorus"
      },
      files: ~w(lib native .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
