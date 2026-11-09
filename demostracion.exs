# Demostración automática del flujo del enunciado (varios usuarios en paralelo).
#
#   elixir demostracion.exs

Code.require_file("cargar.exs", __DIR__)
Cargar.aplicacion()

Emergencias.main(["demostracion"])
