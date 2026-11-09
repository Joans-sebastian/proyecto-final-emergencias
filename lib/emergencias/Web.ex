defmodule Emergencias.Web do
  @moduledoc """
  Página web (opcional) del sistema, hecha solo con Elixir/OTP, sin Phoenix.

      mix run web.exs          # http://localhost:4000
      mix run web.exs 5000     # otro puerto

  Al iniciar se agregan al árbol de supervisión `Web.Fichas` (Agent con las
  sesiones de los navegadores) y `Web.Servidor` (Task que acepta conexiones;
  cada petición se atiende en su propio proceso).
  """

  alias Emergencias.Web.{Servidor, Fichas}

  @doc "Inicia la página web y la deja atendiendo hasta que se cierre el programa."
  def main(argumentos \\ []) do
    puerto = puerto(argumentos)

    case iniciar(puerto) do
      :ok ->
        Util2.mostrar(
          "Página web lista en http://localhost:#{puerto}  (Ctrl+C dos veces para detenerla)",
          :mensaje
        )

        Process.sleep(:infinity)

      {:error, motivo} when is_binary(motivo) ->
        Util2.mostrar(motivo, :error)

      {:error, motivo} ->
        Util2.mostrar(
          "No se pudo iniciar la página web en el puerto #{puerto}: #{inspect(motivo)}",
          :error
        )
    end
  end

  @doc "Agrega el Agent de fichas y el servidor HTTP al Supervisor principal."
  def iniciar(puerto) do
    with :ok <- verificar_puerto(puerto),
         {:ok, _} <- iniciar_hijo(Fichas),
         {:ok, _} <- iniciar_hijo({Servidor, puerto}) do
      :ok
    end
  end

  defp verificar_puerto(puerto) do
    if Servidor.puerto_libre?(puerto),
      do: :ok,
      else:
        {:error,
         "El puerto #{puerto} ya está en uso (¿ya hay otra página web abierta?). " <>
           "Ciérrela o use otro puerto: mix run web.exs 5000"}
  end

  defp iniciar_hijo(especificacion) do
    case Supervisor.start_child(Emergencias.Supervisor, especificacion) do
      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, :already_present} ->
        Supervisor.restart_child(Emergencias.Supervisor, id(especificacion))

      otro ->
        otro
    end
  end

  defp id({modulo, _argumento}), do: modulo
  defp id(modulo), do: modulo

  defp puerto([texto | _]) do
    case Integer.parse(texto) do
      {numero, ""} when numero > 0 -> numero
      _ -> 4000
    end
  end

  defp puerto([]), do: 4000
end
