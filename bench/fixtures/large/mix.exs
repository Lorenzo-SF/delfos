defmodule Fixture.MixProject do
  use Mix.Project

  def project, do: [app: :fixture, version: "0.1.0"]
  def application, do: [extra_applications: [:logger]]
end
