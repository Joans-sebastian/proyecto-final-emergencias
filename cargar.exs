# Permite ejecutar los scripts del proyecto con `elixir archivo.exs`, como en clase.
#
# Cada script empieza con:
#
#   Code.require_file("cargar.exs", __DIR__)
#   Cargar.aplicacion()   # carga el código y arranca los gestores (servidor, consola, ...)
#   Cargar.codigo()       # solo carga el código (clientes de otro nodo)
#
# Con `mix run archivo.exs` también funciona: como Mix ya cargó el proyecto, aquí no se hace nada más.

defmodule Cargar do
  @carpeta __DIR__
  @ebin Path.join(@carpeta, "_build/dev/lib/emergencias/ebin")

  @doc "Compila el proyecto si hace falta y agrega sus módulos a la ruta de código."
  def codigo do
    File.cd!(@carpeta)

    if not Code.ensure_loaded?(Emergencias) do
      compilar()
      Code.prepend_path(@ebin)
    end

    :ok
  end

  @doc "Carga el código y arranca la aplicación (árbol de supervisión con los gestores)."
  def aplicacion do
    codigo()

    case Application.ensure_all_started(:emergencias) do
      {:ok, _} ->
        :ok

      {:error, motivo} ->
        IO.puts(:standard_error, "No se pudo iniciar el sistema: #{inspect(motivo)}")
        System.halt(1)
    end
  end

  # `mix compile` solo vuelve a compilar los archivos que cambiaron.
  defp compilar do
    case System.find_executable("mix") do
      nil ->
        if not File.dir?(@ebin) do
          IO.puts(:standard_error, "No se encontró mix. Compile una vez con: mix compile")
          System.halt(1)
        end

      mix ->
        case System.cmd(mix, ["compile"], cd: @carpeta, stderr_to_stdout: true) do
          {_salida, 0} ->
            :ok

          {salida, _} ->
            IO.puts(:standard_error, "Error al compilar el proyecto:\n#{salida}")
            System.halt(1)
        end
    end
  end
end
