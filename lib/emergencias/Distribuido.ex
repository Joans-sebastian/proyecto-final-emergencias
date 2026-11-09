defmodule Emergencias.Distribuido do
  @moduledoc """
  Modo distribuido: un nodo **servidor** guarda los datos y cada terminal
  **cliente** es otro nodo de Erlang conectado a él.

      elixir servidor.exs                 # terminal 1
      elixir cliente.exs                  # terminal 2, 3, ... (consola completa, usa :erpc)
      elixir cliente_remoto.exs           # terminal 2, 3, ... (menú con send/receive)

  Los nodos se inician desde el script con `Node.start/2` y la cookie del
  proyecto (ver `Emergencias.Anexos.Nodo`). Con una IP como argumento se usan
  nombres completos y funciona entre máquinas de la misma red.
  """

  alias Emergencias.Anexos.Nodo
  alias Emergencias.Interfaz.Consola

  @doc """
  Inicia el servidor: inicia su nodo, avisa su nombre, abre una consola local y
  sigue atendiendo. `argumentos` = [] (misma máquina) o [ip_del_servidor].
  """
  def servidor(argumentos \\ []) do
    case Nodo.iniciar(:servidor, List.first(argumentos)) do
      {:ok, nodo} ->
        anunciar_servidor(nodo, argumentos)
        Consola.main()
        seguir_atendiendo()

      {:error, mensaje} ->
        Util2.mostrar(mensaje, :error)
    end
  end

  @doc "Inicia un cliente conectado al servidor (por defecto `servidor@este_equipo`)."
  def cliente(argumentos) do
    nodo = Nodo.nodo_servidor(argumentos)

    with {:ok, _propio} <- Nodo.iniciar(:cliente, Nodo.ip_cliente(argumentos), unico: true),
         true <- Node.connect(nodo) do
      Consola.main(nodo)
    else
      {:error, mensaje} -> Util2.mostrar(mensaje, :error)
      _ -> Util2.mostrar(mensaje_sin_servidor(nodo), :error)
    end
  end

  @doc """
  Llama a `Emergencias.Sesiones` en este nodo (`nodo` = nil) o en el servidor
  (con `:erpc`). Lo usan la consola y las ventanas para conectar y desconectar.
  """
  def sesiones(nil, funcion, argumentos), do: apply(Emergencias.Sesiones, funcion, argumentos)

  def sesiones(nodo, funcion, argumentos) do
    :erpc.call(nodo, Emergencias.Sesiones, funcion, argumentos, 10_000)
  catch
    :error, {:erpc, motivo} ->
      {:error, "No hay conexión con el servidor #{nodo} (#{inspect(motivo)})"}
  end

  defp anunciar_servidor(nodo, argumentos) do
    direccion = Enum.map_join(argumentos, &(" " <> &1))

    Util2.mostrar(
      """
      Servidor activo en el nodo #{nodo}
      Proceso registrado para send/receive: :servicio_emergencias
      Clientes: elixir cliente.exs#{direccion}  |  elixir cliente_remoto.exs#{direccion}
      """,
      :mensaje
    )
  end

  defp seguir_atendiendo do
    Util2.mostrar(
      "Consola local cerrada. El servidor sigue atendiendo (Ctrl+C dos veces para detenerlo).",
      :mensaje
    )

    Process.sleep(:infinity)
  end

  defp mensaje_sin_servidor(nodo) do
    "No se pudo conectar con el servidor #{nodo}.\n" <>
      "Verifique que esté activo (elixir servidor.exs), que use el mismo tipo de nombre " <>
      "y la misma cookie (my_cookie), y que el firewall permita los puertos 4369 y 9000-9100."
  end
end
