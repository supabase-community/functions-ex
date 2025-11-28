defmodule Supabase.Functions.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/supabase-community/functions-ex"

  def project do
    [
      app: :supabase_functions,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      dialyzer: [plt_local_path: "priv/plts", ignore_warnings: ".dialyzerignore"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp supabase_dep do
    if System.get_env("SUPABASE_LOCAL") == "1" do
      {:supabase_potion, path: "../supabase-ex"}
    else
      {:supabase_potion, "~> 0.6"}
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      supabase_dep(),
      {:mox, "~> 1.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      contributors: ["zoedsoupe"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/supabase_functions"
      },
      files: ~w[lib mix.exs README.md LICENSE]
    }
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp description do
    """
    Complete Elixir client for Supabase.
    """
  end
end
