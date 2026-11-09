# Servidor del modo distribuido: guarda los datos y atiende a los clientes.
# El script inicia su propio nodo con Node.start/2 y pone la cookie del proyecto.
#
#   elixir servidor.exs                  -> nodo servidor@ESTE_EQUIPO (misma máquina)
#   elixir servidor.exs 192.168.1.20     -> nodo :"servidor@192.168.1.20" (otras máquinas en la red)
#
# Atiende dos tipos de cliente al mismo tiempo:
#   cliente.exs          consola completa (llama a las sesiones del servidor con :erpc)
#   cliente_remoto.exs   menú con send/receive al proceso registrado :servicio_emergencias

Code.require_file("cargar.exs", __DIR__)
Cargar.aplicacion()

Emergencias.main(["servidor" | System.argv()])
