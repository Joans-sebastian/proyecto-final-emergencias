defmodule Emergencias.Anexos.ClienteRemoto do
  @moduledoc """
  Cliente de otro nodo que habla con `Emergencias.Anexos.ServicioRemoto` con
  **send/receive**, como el cajero con la sede (guía "Aplicaciones distribuidas").

      elixir cliente_remoto.exs                             # servidor en este equipo
      elixir cliente_remoto.exs 192.168.1.20                # servidor en otra máquina
      elixir cliente_remoto.exs 192.168.1.20 192.168.1.21   # además, la IP de este equipo

  Pasos de `main/1`:

  1. Inicia su propio nodo con un nombre al azar (`cliente_4f1a9c2e@...`),
     porque puede haber varios clientes a la vez, y pone la cookie del proyecto.
  2. Se conecta con `Node.connect/1` al nodo servidor.
  3. Pide usuario y contraseña y se conecta al servicio.
  4. Muestra el menú hasta que el usuario elige salir; entonces envía
     `{:fin, pid}` y espera `:adios`.

  Cada petición incluye `self()` para que el servicio sepa a quién responder, y
  la respuesta se espera con `receive ... after @timeout`, para no quedarse
  bloqueado si el servidor no está activo.
  """

  alias Emergencias.Anexos.{Nodo, ServicioRemoto}

  # Debe ser mayor que lo que tarda la operación más lenta, más el viaje del mensaje.
  @timeout 15_000

  @doc "Punto de entrada de `cliente_remoto.exs`."
  def main(argumentos) do
    servidor = Nodo.nodo_servidor(argumentos)

    case Nodo.iniciar(:cliente, Nodo.ip_cliente(argumentos), unico: true) do
      {:ok, nodo} ->
        Util2.mostrar("Cliente iniciado en #{nodo}", :mensaje)
        conectar(Node.connect(servidor), servidor)

      {:error, mensaje} ->
        Util2.mostrar(mensaje, :error)
    end
  end

  defp conectar(true, servidor) do
    Util2.mostrar("Conectado al nodo #{servidor}.\n", :mensaje)
    iniciar_sesion(servidor)
  end

  defp conectar(_false_o_ignored, servidor) do
    Util2.mostrar(
      "No se pudo conectar con #{servidor}. Verifique que el servidor esté activo " <>
        "(elixir servidor.exs), que usen la misma cookie y el mismo tipo de nombre.",
      :error
    )
  end

  defp iniciar_sesion(servidor) do
    usuario = leer("Usuario: ")
    contrasena = leer("Contraseña: ")

    case pedir(servidor, {:conectar, self(), usuario, contrasena}) do
      {:conectado, mensaje} ->
        Util2.mostrar(mensaje, :mensaje)
        menu(servidor)

      {:error, motivo} ->
        Util2.mostrar(motivo, :error)

      :sin_respuesta ->
        :ok
    end
  end

  # Muestra el menú, atiende la opción y vuelve a mostrarlo (recursivo) hasta salir.
  defp menu(servidor) do
    mostrar_menu()

    case leer("Seleccione una opción (1-5): ") do
      "5" ->
        salir(servidor)

      opcion ->
        atender_opcion(opcion, servidor)
        menu(servidor)
    end
  end

  defp mostrar_menu do
    Util2.mostrar(
      """

      1 - Escribir un comando (por ejemplo: estado_zona centro)
      2 - Ver los comandos que permite mi rol
      3 - Necesidades pendientes
      4 - Estado de todas las zonas (consultadas en paralelo)
      5 - Salir
      """,
      :mensaje
    )
  end

  defp atender_opcion("1", servidor),
    do: comando(servidor, leer("Comando: "))

  defp atender_opcion("2", servidor), do: comando(servidor, "ayuda")
  defp atender_opcion("3", servidor), do: comando(servidor, "necesidades_pendientes")

  defp atender_opcion("4", servidor) do
    servidor |> pedir({:estado_zonas, self()}) |> mostrar_respuesta()
  end

  defp atender_opcion(opcion, _servidor) do
    Util2.mostrar("Opción inválida: #{opcion}", :error)
  end

  defp comando(_servidor, ""), do: :ok

  defp comando(servidor, linea) do
    servidor |> pedir({:comando, self(), linea}) |> mostrar_respuesta()
  end

  defp salir(servidor) do
    case pedir(servidor, {:fin, self()}) do
      :adios -> Util2.mostrar("El servidor respondió :adios. Sesión cerrada.", :mensaje)
      _ -> :ok
    end
  end

  # Envía la petición al proceso registrado del servidor y espera la respuesta.
  defp pedir(servidor, mensaje) do
    send({ServicioRemoto.nombre(), servidor}, mensaje)
    esperar_respuesta()
  end

  defp esperar_respuesta do
    receive do
      {:conectado, texto} -> {:conectado, texto}
      {:respuesta, texto} -> {:respuesta, texto}
      {:estado_zonas, textos} -> {:estado_zonas, textos}
      {:error, texto} -> {:error, texto}
      :adios -> :adios
    after
      @timeout ->
        Util2.mostrar("El servidor no respondió a tiempo", :error)
        :sin_respuesta
    end
  end

  defp mostrar_respuesta({:respuesta, texto}), do: Util2.mostrar(texto, :mensaje)
  defp mostrar_respuesta({:error, texto}), do: Util2.mostrar(texto, :error)

  defp mostrar_respuesta({:estado_zonas, []}),
    do: Util2.mostrar("No hay zonas registradas", :mensaje)

  defp mostrar_respuesta({:estado_zonas, textos}),
    do: Util2.mostrar(Enum.join(textos, "\n\n"), :mensaje)

  defp mostrar_respuesta(:sin_respuesta), do: :ok

  # Si la entrada se cierra (por ejemplo, al redirigir un archivo), se toma como "salir".
  defp leer(pregunta) do
    case IO.gets(pregunta) do
      :eof -> "5"
      {:error, _} -> "5"
      texto -> String.trim(texto)
    end
  end
end
