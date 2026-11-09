defmodule Emergencias.Anexos.ServicioRemoto do
  @moduledoc """
  Servicio del nodo servidor que atiende a los clientes de otros nodos con
  **send/receive**, como la sede de Armenia atiende a los cajeros (guía
  "Aplicaciones distribuidas") y como `NodoServidor` de la clase de IPC remota.

  El proceso se registra con `Process.register/2` como `:servicio_emergencias`.
  Desde otro nodo se le escribe con la tupla `{nombre, nodo}`:

      send({:servicio_emergencias, :"servidor@EQUIPO"}, {:conectar, self(), "laura", "1234"})

  ## Mensajes que atiende

  | Mensaje del cliente                          | Respuesta                                   |
  |----------------------------------------------|---------------------------------------------|
  | `{:conectar, pid, usuario, contraseña}`      | `{:conectado, texto}` o `{:error, texto}`   |
  | `{:comando, pid, linea}`                     | `{:respuesta, texto}` o `{:error, texto}`   |
  | `{:estado_zonas, pid}`                       | `{:estado_zonas, [texto]}` o `{:error, texto}` |
  | `{:fin, pid}`                                | `:adios`                                    |

  En todos, `pid` es el PID del proceso cliente, para que el servicio sepa a
  quién responder. Un PID sirve entre nodos, así que se responde con
  `send(pid, ...)` sin conocer el nombre del nodo del cliente.

  ## Cómo evita bloquearse

  El `loop/1` atiende un mensaje a la vez. Lo único que guarda es qué usuario
  conectó cada cliente (`clientes`, un mapa `pid => usuario`), igual que la sede
  guarda el inventario. Los comandos y las consultas se ejecutan con `spawn` en
  otro proceso, como el reporte de la Versión 4: el loop solo crea ese proceso y
  vuelve enseguida a esperar el siguiente mensaje, así un comando lento de un
  cliente no hace esperar a los demás.

  Los datos siguen en los gestores (GenServers), que atienden un mensaje a la
  vez: si dos clientes asignan el último recurso al mismo tiempo, uno lo recibe
  y el otro recibe el error, igual que las dos ventas del último frijol.

  `{:estado_zonas, pid}` consulta todas las zonas **en paralelo** con
  `Task.async_stream/3`, como el comparador de tiendas con `Task`.
  """

  use Task, restart: :permanent

  require Logger

  alias Emergencias.{Comandos, Sesion, Sesiones}
  alias Emergencias.Estado.GestorZonas

  @nombre :servicio_emergencias

  @doc "Nombre con el que queda registrado el proceso en su nodo."
  def nombre, do: @nombre

  @doc "Inicia el servicio bajo el árbol de supervisión (`Aplicacion.ex`)."
  def start_link(_opciones), do: Task.start_link(&iniciar/0)

  # Registra el proceso con un nombre y empieza a atender mensajes.
  defp iniciar do
    Process.register(self(), @nombre)
    loop(%{})
  end

  # Atiende un mensaje y vuelve a esperar el siguiente, con los clientes actualizados.
  defp loop(clientes) do
    receive do
      {:conectar, pid, usuario, contrasena} ->
        registrar("conectar #{usuario}")
        {respuesta, clientes} = conectar(clientes, pid, usuario, contrasena)
        send(pid, respuesta)
        loop(clientes)

      {:comando, pid, linea} ->
        registrar("comando de #{quien(clientes, pid)}: #{linea}")
        atender_aparte(clientes, pid, fn usuario -> ejecutar(usuario, linea) end)
        loop(clientes)

      {:estado_zonas, pid} ->
        registrar("estado de todas las zonas para #{quien(clientes, pid)}")
        atender_aparte(clientes, pid, &estado_zonas/1)
        loop(clientes)

      {:fin, pid} ->
        registrar("fin de #{quien(clientes, pid)}")
        send(pid, :adios)
        loop(desconectar(clientes, pid))

      # El nodo del cliente se cerró sin enviar :fin (Ctrl+C, se cayó la red, ...).
      {:DOWN, _referencia, :process, pid, _motivo} ->
        loop(desconectar(clientes, pid))

      otro ->
        registrar("mensaje desconocido: #{inspect(otro)}")
        loop(clientes)
    end
  end

  defp conectar(clientes, pid, usuario, contrasena) do
    case Sesiones.conectar([usuario, contrasena]) do
      {:ok, _sesion, usuario, mensaje} ->
        # Si el nodo del cliente se cae, llega {:DOWN, ...} y se libera su sesión.
        Process.monitor(pid)
        {{:conectado, mensaje}, Map.put(clientes, pid, usuario)}

      {:error, motivo} ->
        {{:error, motivo}, clientes}
    end
  end

  # El trabajo se hace en otro proceso para que el loop no se bloquee.
  defp atender_aparte(clientes, pid, trabajo) do
    case Map.fetch(clientes, pid) do
      {:ok, usuario} -> spawn(fn -> send(pid, trabajo.(usuario)) end)
      :error -> send(pid, {:error, "Primero debe conectarse con usuario y contraseña"})
    end
  end

  # Se ejecuta en la sesión del usuario: valida sus permisos y queda en la bitácora.
  defp ejecutar(usuario, linea) do
    case Sesion.ejecutar(Sesion.nombre(usuario.username), linea) do
      {:ok, texto} -> {:respuesta, texto}
      {:error, texto} -> {:error, texto}
    end
  catch
    :exit, _motivo -> {:error, "La sesión de #{usuario.username} ya no está abierta"}
  end

  @doc """
  Estado de cada zona principal, consultadas en paralelo (una `Task` por zona).
  Retorna `{:estado_zonas, textos}`.
  """
  def estado_zonas(usuario) do
    textos =
      GestorZonas.arboles()
      |> Task.async_stream(&estado_zona(usuario, &1.codigo), timeout: 10_000)
      |> Enum.map(fn {:ok, texto} -> texto end)

    {:estado_zonas, textos}
  end

  defp estado_zona(usuario, codigo) do
    case Comandos.ejecutar("estado_zona #{codigo}", usuario) do
      {:ok, texto} -> texto
      {:error, texto} -> "#{codigo}: #{texto}"
    end
  end

  defp desconectar(clientes, pid) do
    case Map.pop(clientes, pid) do
      {nil, clientes} ->
        clientes

      {usuario, clientes} ->
        # Solo se cierra la sesión si ningún otro cliente usa ese mismo usuario.
        if not Enum.any?(clientes, fn {_pid, otro} -> otro.username == usuario.username end),
          do: Sesiones.desconectar(usuario.username)

        clientes
    end
  end

  defp quien(clientes, pid) do
    case Map.fetch(clientes, pid) do
      {:ok, usuario} -> "@#{usuario.username}"
      :error -> "cliente sin conectar (#{inspect(pid)})"
    end
  end

  defp registrar(texto), do: Logger.info("[servicio_emergencias] #{texto}")
end
