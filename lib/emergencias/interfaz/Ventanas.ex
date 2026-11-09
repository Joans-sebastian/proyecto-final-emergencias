defmodule Emergencias.Interfaz.Ventanas do
  @moduledoc """
  Ventanas emergentes con Python/tkinter, como `mostrar_dialogo.py` visto en clase.

  Elixir ejecuta `priv/ventanas/dialogo.py` con `System.cmd/3` y lee la
  respuesta del usuario por la salida estándar. Requiere Python 3 con tkinter.
  """

  @doc "Indica si se pueden abrir ventanas (Python instalado y script presente)."
  def disponible?, do: python() != nil and File.regular?(script())

  @doc """
  Muestra un texto en una ventana. `tipo` es `:mensaje` o `:error`.

      Ventanas.mostrar("Necesidad registrada", :mensaje)
  """
  def mostrar(texto, tipo, titulo \\ "Sistema de emergencias") do
    archivo =
      Path.join(System.tmp_dir!(), "emergencias_#{System.unique_integer([:positive])}.txt")

    File.write!(archivo, texto)
    ejecutar([if(tipo == :error, do: "error", else: "info"), titulo, archivo])
    File.rm(archivo)
    :ok
  end

  @doc """
  Pide varios campos en una sola ventana. Un campo que empieza con `*` se
  escribe oculto (contraseña). Retorna `{:ok, valores}` o `:cancelado`.

      Ventanas.formulario("Iniciar sesión", ["Usuario", "*Contraseña"])
  """
  def formulario(titulo, campos) do
    case ejecutar(["formulario", titulo | campos]) do
      "" -> :cancelado
      salida -> {:ok, JSON.decode!(salida)}
    end
  end

  @doc "Muestra un menú de botones. Retorna `{:ok, indice}` (desde 0) o `:cancelado`."
  def menu(titulo, opciones) do
    case ejecutar(["menu", titulo | opciones]) do
      "" -> :cancelado
      salida -> {:ok, String.to_integer(salida)}
    end
  end

  defp ejecutar(argumentos) do
    {salida, _codigo} =
      System.cmd(python(), [script() | argumentos], env: [{"PYTHONIOENCODING", "utf-8"}])

    String.trim(salida)
  end

  defp python,
    do:
      System.find_executable("python") || System.find_executable("python3") ||
        System.find_executable("py")

  defp script, do: :emergencias |> :code.priv_dir() |> Path.join("ventanas/dialogo.py")
end
