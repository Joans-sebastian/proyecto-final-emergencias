defmodule Emergencias.Aplicacion do
  @moduledoc """
  Árbol de supervisión (OTP) del sistema:

      Emergencias.Supervisor (one_for_one)
      ├── Estado.Bitacora            GenServer: actividad de los usuarios
      ├── Estado.GestorUsuarios      GenServer
      ├── Estado.GestorZonas         GenServer
      ├── Estado.GestorRecursos      GenServer
      ├── Estado.GestorNecesidades   GenServer (usa GestorRecursos)
      ├── Estado.GestorPersonas      GenServer
      ├── Estado.GestorMensajes      GenServer
      ├── Estado.GestorMascotas      GenServer
      ├── Estado.GestorAlbergues     GenServer
      ├── RegistroSesiones           Registry: usuario → proceso de su sesión
      ├── SupervisorSesiones         DynamicSupervisor
      │   └── Sesion (una por usuario conectado, se crean y cierran en ejecución)
      ├── Remoto.ServicioRemoto      proceso registrado :servicio_emergencias (send/receive entre nodos)
      └── Estado.Barrios             GenServer: barrios registrados a mano (B01, B02...)

  Estrategia `one_for_one`: si un gestor falla, solo ese se reinicia y vuelve
  a cargar sus datos del archivo; los demás siguen atendiendo.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Emergencias.Estado.Bitacora,
      Emergencias.Estado.GestorUsuarios,
      Emergencias.Estado.GestorZonas,
      Emergencias.Estado.GestorRecursos,
      Emergencias.Estado.GestorNecesidades,
      Emergencias.Estado.GestorPersonas,
      Emergencias.Estado.GestorMensajes,
      Emergencias.Estado.GestorMascotas,
      Emergencias.Estado.GestorAlbergues,
      {Registry, keys: :unique, name: Emergencias.RegistroSesiones},
      {DynamicSupervisor, strategy: :one_for_one, name: Emergencias.SupervisorSesiones},
      # Proceso registrado :servicio_emergencias
      # que atiende a los clientes de otros nodos con send/receive.
      Emergencias.Remoto.ServicioRemoto,
      # Los barrios se registran a mano y reciben B01, B02...
      Emergencias.Estado.Barrios
    ]

    opciones = [
      strategy: :one_for_one,
      name: Emergencias.Supervisor,
      max_restarts: 10,
      max_seconds: 5
    ]

    Supervisor.start_link(children, opciones)
  end
end
