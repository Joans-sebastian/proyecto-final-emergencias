defmodule Emergencias.Interfaz.Consola do
  @moduledoc """
  Consola del sistema (intérprete de comandos). Lee y muestra con los módulos
  del curso `Util` y `Util2`.

  - Comando completo: `registrar_necesidad agua 30 critica centro "Punto 3"`.
  - **Modo guiado**: el comando de registro sin datos (`registrar_necesidad`) pide
    cada campo con la función `ingresar` de la entidad.
  - En modo cliente (`nodo` ≠ nil) `conectar` y `desconectar` se ejecutan en el
    servidor con `:erpc`; los comandos viajan a la sesión remota con `GenServer.call`.
  """

  alias Emergencias.{Distribuido, Permisos, Sesion}
  alias Emergencias.Interfaz.Analizador

  alias Emergencias.Dominio.{
    Albergue,
    Mascota,
    Mensaje,
    Necesidad,
    Persona,
    Recurso,
    Usuario,
    Zona
  }

  @salir ~w(exit salir quit)

  # Comandos de registro que admiten el modo guiado y la entidad que los lee.
  @guiados %{
    "registrar_usuario" => Usuario,
    "registrar_zona" => Zona,
    "registrar_necesidad" => Necesidad,
    "registrar_recurso" => Recurso,
    "reportar_persona" => Persona,
    "enviar_mensaje" => Mensaje,
    "reportar_mascota" => Mascota,
    "registrar_albergue" => Albergue
  }

  @doc """
  Punto de entrada de la consola: muestra el encabezado y atiende comandos
  hasta `exit`. Con `nodo` trabaja como cliente de ese servidor.
  """
  def main(nodo \\ nil) do
    encabezado(nodo)
    bucle(estado_inicial(nodo))
  end

  @doc "Ejecuta los comandos de un archivo de texto (uno por línea; `#` = comentario)."
  def ejecutar_archivo(ruta) do
    if File.regular?(ruta) do
      encabezado(nil)

      ruta
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.reduce_while(estado_inicial(nil), &ejecutar_linea_de_archivo/2)
      |> cerrar()
    else
      Util2.mostrar("No existe el archivo #{ruta}", :error)
    end
  end

  @doc "Procesa una línea y retorna `{:continuar | :salir, estado}`."
  def procesar(linea, estado) do
    case Analizador.analizar(linea) do
      {:ok, nil, _, _} ->
        {:continuar, estado}

      {:ok, comando, _, _} when comando in @salir ->
        {:salir, estado}

      {:ok, "conectar", argumentos, opciones} ->
        {:continuar, conectar(argumentos, opciones, estado)}

      {:ok, "desconectar", _, _} ->
        {:continuar, desconectar(estado)}

      {:ok, "ayuda", [], _} when estado.sesion == nil ->
        mostrar({:ok, Permisos.ayuda(nil)}, estado)

      {:ok, _comando, _, _} when estado.sesion == nil ->
        mostrar({:error, "Primero conéctese: conectar usuario contraseña [tipo] [zona]"}, estado)

      {:ok, comando, [], opciones}
      when is_map_key(@guiados, comando) and map_size(opciones) == 0 ->
        {:continuar, registro_guiado(comando, estado)}

      {:ok, _comando, _, _} ->
        {:continuar, ejecutar(linea, estado)}

      {:error, motivo} ->
        mostrar({:error, motivo}, estado)
    end
  end

  # ---------------------------------------------------------------------------
  # Cómo se hace cada paso
  # ---------------------------------------------------------------------------

  defp estado_inicial(nodo), do: %{sesion: nil, usuario: nil, nodo: nodo}

  # **Recursiva.** Lee un comando, lo procesa y vuelve a empezar.
  defp bucle(estado) do
    case leer(prompt(estado)) do
      nil ->
        cerrar(estado)

      linea ->
        case procesar(linea, estado) do
          {:continuar, nuevo} -> bucle(nuevo)
          {:salir, nuevo} -> cerrar(nuevo)
        end
    end
  end

  defp ejecutar_linea_de_archivo(linea, estado) do
    Util2.mostrar("\n#{prompt(estado)}#{linea}", :mensaje)

    case procesar(linea, estado) do
      {:continuar, nuevo} -> {:cont, nuevo}
      {:salir, nuevo} -> {:halt, nuevo}
    end
  end

  # Util2.ingresar/2 del curso; si la entrada terminó (Ctrl+Z / fin de archivo) retorna nil.
  defp leer(pregunta) do
    Util2.ingresar(pregunta, :texto)
  rescue
    FunctionClauseError -> nil
  end

  defp conectar(_argumentos, _opciones, %{usuario: usuario} = estado) when usuario != nil do
    elem(
      mostrar(
        {:error, "Ya hay una sesión abierta de @#{usuario.username}. Use desconectar primero."},
        estado
      ),
      1
    )
  end

  defp conectar([], opciones, estado) do
    usuario = Util2.ingresar("Usuario: ", :texto)
    contrasena = Util2.ingresar("Contraseña: ", :texto)
    conectar([usuario, contrasena], opciones, estado)
  end

  defp conectar(argumentos, opciones, estado) do
    case remoto(estado, :conectar, [argumentos, opciones]) do
      {:ok, pid, usuario, mensaje} ->
        mostrar({:ok, mensaje}, estado)
        %{estado | sesion: pid, usuario: usuario}

      error ->
        elem(mostrar(error, estado), 1)
    end
  end

  defp desconectar(%{usuario: nil} = estado),
    do: elem(mostrar({:error, "No hay ninguna sesión abierta"}, estado), 1)

  defp desconectar(estado) do
    mostrar(remoto(estado, :desconectar, [estado.usuario.username]), estado)
    %{estado | sesion: nil, usuario: nil}
  end

  defp registro_guiado(comando, estado) do
    if Permisos.permitido?(estado.usuario, comando) do
      entidad = Map.fetch!(@guiados, comando)

      Code.ensure_loaded(entidad)

      datos =
        if function_exported?(entidad, :ingresar, 1),
          do: entidad.ingresar(estado.usuario.username),
          else: entidad.ingresar()

      case datos do
        {:ok, struct} -> enviar(estado, fn -> Sesion.registrar(estado.sesion, struct) end)
        error -> elem(mostrar(error, estado), 1)
      end
    else
      enviar(estado, fn -> Sesion.ejecutar(estado.sesion, comando) end)
    end
  end

  defp ejecutar(linea, estado),
    do: enviar(estado, fn -> Sesion.ejecutar(estado.sesion, linea) end)

  defp enviar(estado, llamada) do
    elem(mostrar(llamada.(), estado), 1)
  catch
    :exit, _razon ->
      mostrar({:error, "La sesión se cerró inesperadamente. Conéctese de nuevo."}, estado)
      %{estado | sesion: nil, usuario: nil}
  end

  defp cerrar(%{usuario: nil}),
    do: Util.mostrar_mensaje("\nSistema de emergencias: sesión terminada.")

  defp cerrar(estado) do
    remoto(estado, :desconectar, [estado.usuario.username])
    cerrar(%{estado | usuario: nil, sesion: nil})
  end

  # Llama a Emergencias.Sesiones en este nodo o, en modo cliente, en el servidor.
  defp remoto(estado, funcion, argumentos),
    do: Distribuido.sesiones(estado.nodo, funcion, argumentos)

  # Muestra el resultado con Util2.mostrar/2 y retorna {:continuar, estado}.
  defp mostrar({:ok, ""}, estado), do: {:continuar, estado}

  defp mostrar({:ok, texto}, estado) do
    Util2.mostrar(texto, :mensaje)
    {:continuar, estado}
  end

  defp mostrar({:error, texto}, estado) do
    Util2.mostrar("ERROR: " <> texto, :mensaje)
    {:continuar, estado}
  end

  defp prompt(%{usuario: nil}), do: "emergencias> "
  defp prompt(%{usuario: u}), do: "#{u.username}@#{u.tipo}> "

  defp encabezado(nodo) do
    Util.mostrar_mensaje("""
    ======================================================================
      SISTEMA DISTRIBUIDO DE COORDINACIÓN Y GESTIÓN DE EMERGENCIAS
      Atención posterior a un terremoto - Programación III (Elixir)
    ======================================================================
    #{if nodo, do: "Conectado al servidor #{nodo}.\n", else: ""}Escriba ayuda para ver los comandos. Para empezar:
      conectar laura 1234 coordinador centro
    Los comandos de registro sin datos (por ejemplo registrar_necesidad) piden cada campo.
    """)
  end
end
