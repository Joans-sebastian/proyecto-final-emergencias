defmodule Emergencias.Interfaz.Grafica do
  @moduledoc """
  Interfaz gráfica con ventanas emergentes (`Emergencias.Interfaz.Ventanas`).

      mix run ventanas.exs

  Flujo: ventana de inicio de sesión → menú con las acciones que permite el rol
  (`Emergencias.Interfaz.Acciones`) → formulario de la acción → ventana con el
  resultado. Por dentro usa la misma sesión y los mismos comandos que la consola.
  """

  alias Emergencias.{Distribuido, Sesion, Sesiones}
  alias Emergencias.Interfaz.{Acciones, Ventanas}

  @doc "Inicia la interfaz gráfica (con `nodo`, como cliente de ese servidor)."
  def main(nodo \\ nil) do
    if Ventanas.disponible?() do
      case iniciar_sesion(nodo) do
        {:ok, estado} -> estado |> menu_principal() |> cerrar_sesion()
        :cancelado -> :ok
      end
    else
      Util2.mostrar(
        "No se encontró Python con tkinter. Use la consola: mix run consola.exs",
        :error
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Pasos
  # ---------------------------------------------------------------------------

  # **Recursiva.** Pide los datos hasta que el inicio de sesión funcione o se cancele.
  defp iniciar_sesion(nodo) do
    campos = [
      "Usuario (sin espacios, ej: joan.vargas)",
      "*Contraseña",
      "Tipo, solo si es nuevo (ciudadano/voluntario/coordinador/administrador)",
      "Zona principal, solo si es nuevo",
      "Nombre completo, solo si es nuevo"
    ]

    case Ventanas.formulario("Iniciar sesión - Sistema de emergencias", campos) do
      :cancelado ->
        :cancelado

      {:ok, valores} ->
        {argumentos, opciones} = Sesiones.desde_formulario(valores)

        case Distribuido.sesiones(nodo, :conectar, [argumentos, opciones]) do
          {:ok, sesion, usuario, mensaje} ->
            Ventanas.mostrar(mensaje, :mensaje)
            {:ok, %{sesion: sesion, usuario: usuario, nodo: nodo}}

          {:error, motivo} ->
            Ventanas.mostrar(motivo, :error, "Error")
            iniciar_sesion(nodo)
        end
    end
  end

  # **Recursiva.** Muestra el menú y ejecuta la acción elegida hasta "Cerrar sesión".
  defp menu_principal(estado) do
    acciones = Acciones.permitidas(estado.usuario)
    botones = Enum.map(acciones, & &1.texto) ++ ["Escribir un comando", "Cerrar sesión"]
    titulo = "Emergencias - @#{estado.usuario.username} (#{estado.usuario.tipo})"

    case Ventanas.menu(titulo, botones) do
      {:ok, indice} when indice < length(acciones) ->
        ejecutar_accion(Enum.at(acciones, indice), estado)
        menu_principal(estado)

      {:ok, indice} when indice == length(acciones) ->
        comando_libre(estado)
        menu_principal(estado)

      _cerrar_o_cancelar ->
        estado
    end
  end

  defp cerrar_sesion(estado) do
    estado.nodo
    |> Distribuido.sesiones(:desconectar, [estado.usuario.username])
    |> mostrar_resultado()
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp ejecutar_accion(%{campos: [], opcionales: []} = accion, estado),
    do: enviar(estado, accion.comando)

  defp ejecutar_accion(accion, estado) do
    campos = Enum.map(accion.campos ++ accion.opcionales, &Acciones.texto_ventana/1)

    with {:ok, valores} <- Ventanas.formulario(accion.texto, campos) do
      case Acciones.armar(accion, valores) do
        {:ok, linea} -> enviar(estado, linea)
        error -> mostrar_resultado(error)
      end
    end
  end

  defp comando_libre(estado) do
    with {:ok, [linea]} <-
           Ventanas.formulario("Escribir un comando (ayuda para ver la lista)", ["Comando"]) do
      enviar(estado, linea)
    end
  end

  defp enviar(estado, linea), do: estado.sesion |> Sesion.ejecutar(linea) |> mostrar_resultado()

  defp mostrar_resultado({:ok, texto}), do: Ventanas.mostrar(texto, :mensaje)
  defp mostrar_resultado({:error, texto}), do: Ventanas.mostrar(texto, :error, "Error")
end
