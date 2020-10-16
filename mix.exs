defmodule Keypad.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/jjcarstens/keypad"

  def project do
    [
      app: :keypad,
      version: @version,
      elixir: "~> 1.8",
      description: "A small library to interact with keypads connected to GPIO pins",
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      aliases: [docs: ["docs", &copy_images/1]],
      package: package(),
      deps: deps(),
      preferred_cli_env: [
        docs: :docs,
        "hex.build": :docs,
        "hex.publish": :docs
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp copy_images(_) do
    File.cp_r("assets", "doc/assets")
  end

  defp deps do
    [
      {:circuits_gpio, "~> 0.4"},
      {:ex_doc, "~> 0.23", only: :docs, runtime: false}
    ]
  end

  defp docs do
    [extras: ["README.md", "CONFIGURATION.md", "SETUP.md", "CHANGELOG.md"], main: "readme",
    source_ref: "v#{@version}",
    source_url: @source_url,
    skip_undefined_reference_warnings_on: ["CHANGELOG.md"]]
  end

  defp package do
    [
      licenses: ["Apache License 2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
