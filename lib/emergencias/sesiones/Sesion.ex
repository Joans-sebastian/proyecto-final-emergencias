defmodule Emergencias.Sesion do
  @moduledoc """
  Sesión de un usuario conectado: **un proceso (GenServer) por usuario**.

  Cada sesión ejecuta los comandos de su usuario en su propio proceso, así
  varios usuarios trabajan en paralelo. Los datos compartidos viven en los
  gestores (GenServers), que resuelven los conflictos atendiendo un mensaje a la vez.

  Las sesiones las inicia el `DynamicSupervisor` `Emergencias.SupervisorSesiones`
  y se registran por nombre de usuario en `Emergencias.RegistroSesiones`.
  Son `:temporary`: si una sesión falla no se reinicia sola (el usuario vuelve
  a conectarse), y su caída no afecta a las demás.
  """

  use GenServer, restart: :temporary

  alias Emergencias.Comandos
  alias Emergencias.Estado.Bitacora

  def start_link(usuario) do
    GenServer.start_link(__MODULE__, usuario, name: nombre(usuario.username))
  end

  @doc "Nombre del proceso en el Registry."
  def nombre(username), do: {:via, Registry, {Emergencias.RegistroSesiones, username}}

  @doc "Ejecuta una línea de comando con los permisos del usuario de la sesión."
  def ejecutar(sesion, linea), do: GenServer.call(sesion, {:ejecutar, linea}, 30_000)

  @doc "Registra un struct creado con `ingresar/2` (modo guiado de la consola)."
  def registrar(sesion, entidad), do: GenServer.call(sesion, {:registrar, entidad}, 30_000)

  @doc "Datos de la sesión: usuario, hora de conexión y comandos ejecutados."
  def info(sesion), do: GenServer.call(sesion, :info)

  @impl true
  def init(usuario) do
    {:ok, %{usuario: usuario, conectado_en: Emergencias.Dominio.Comun.ahora(), comandos: 0}}
  end

  @impl true
  def handle_call({:ejecutar, linea}, _from, estado) do
    resultado = Comandos.ejecutar(linea, estado.usuario)
    Bitacora.registrar(estado.usuario.username, linea, elem(resultado, 0))
    {:reply, resultado, %{estado | comandos: estado.comandos + 1}}
  end

  def handle_call({:registrar, entidad}, _from, estado) do
    resultado = Comandos.registrar(entidad, estado.usuario)
    accion = "registro guiado de #{entidad.__struct__ |> Module.split() |> List.last()}"
    Bitacora.registrar(estado.usuario.username, accion, elem(resultado, 0))
    {:reply, resultado, %{estado | comandos: estado.comandos + 1}}
  end

  def handle_call(:info, _from, estado), do: {:reply, estado, estado}
end
