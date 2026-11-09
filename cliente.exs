# Cliente del modo distribuido (una terminal por usuario), con la consola completa.
#
#   elixir cliente.exs                              -> servidor de este equipo
#   elixir cliente.exs 192.168.1.20                 -> servidor en otra máquina (IP del servidor)
#   elixir cliente.exs 192.168.1.20 192.168.1.21    -> además indica la IP de este equipo
#
# El cliente no arranca los gestores: todo se guarda en el servidor.

Code.require_file("cargar.exs", __DIR__)
Cargar.codigo()

Emergencias.main(["cliente" | System.argv()])
