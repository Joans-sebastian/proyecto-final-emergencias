defmodule Emergencias.MixProject do
  use Mix.Project

  # Proyecto final de Programación III (Universidad del Quindío):
  # sistema concurrente de coordinación y gestión de emergencias.
  # No usa dependencias externas: solo Elixir/OTP (JSON viene incluido desde Elixir 1.18).
  def project do
    [
      app: :emergencias,
      version: "1.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      # :crypto se usa para guardar las contraseñas con hash SHA-256 y sal.
      extra_applications: [:logger, :crypto],
      mod: {Emergencias.Aplicacion, []}
    ]
  end
end
