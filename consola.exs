# Consola del sistema de emergencias.
#
#   elixir consola.exs                       -> consola interactiva
#   elixir consola.exs ejemplos/flujo.txt    -> ejecuta los comandos del archivo
#
# (También funciona con `mix run consola.exs`.)

Code.require_file("cargar.exs", __DIR__)
Cargar.aplicacion()

case System.argv() do
  [] -> Emergencias.main(["consola"])
  [archivo | _] -> Emergencias.main(["archivo", archivo])
end
