defmodule Keypad.MixProject do
  use Mix.Project

  def project do
    [
      app: :keypad,
      version: "0.3.0",
      elixir: "~> 1.8",
      name: "Keypad",
      description: "A small library to interact with keypads connected to GPIO pins",
      source_url: "https://github.com/jjcarstens/keypad",
      docs: [extras: ["README.md", "CONFIGURATION.md", "SETUP.md"], main: "readme"],
      start_permanent: Mix.env() == :prod,
      aliases: [docs: ["docs", &copy_images/1]],
      package: [
        maintainers: ["Jon Carstens"],
        licenses: ["Apache License 2.0"],
        links: %{
          "GitHub" => "https://github.com/jjcarstens/keypad"
        }
      ],
      deps: deps()
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
      {:circuits_gpio, "~> 0.3"},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false}
    ]
  end
end
