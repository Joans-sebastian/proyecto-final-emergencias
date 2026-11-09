# Página web (opcional) del sistema, sin dependencias externas.
#
#   elixir web.exs          -> http://localhost:4000
#   elixir web.exs 5000     -> otro puerto

Code.require_file("cargar.exs", __DIR__)
Cargar.aplicacion()

Emergencias.main(["web" | System.argv()])
