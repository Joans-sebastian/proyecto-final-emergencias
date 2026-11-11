# Cliente con send/receive entre nodos (tema "Aplicaciones distribuidas").
# Le envía mensajes al proceso registrado :servicio_emergencias del servidor,
# como el cajero le envía mensajes a la sede.
#
#   elixir cliente_remoto.exs                              -> servidor de este equipo
#   elixir cliente_remoto.exs 192.168.1.20                 -> servidor en otra máquina
#   elixir cliente_remoto.exs 192.168.1.20 192.168.1.21    -> además indica la IP de este equipo

Code.require_file("cargar.exs", __DIR__)
Cargar.codigo()

Emergencias.Remoto.ClienteRemoto.main(System.argv())
