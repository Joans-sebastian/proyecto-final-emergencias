ExUnit.start()

defmodule Emergencias.Prueba do
  @moduledoc "Ayudas para las pruebas: datos limpios y usuarios conectados."

  alias Emergencias.{Sesion, Sesiones}

  @doc "Reinicia la aplicación con la carpeta de datos de prueba vacía."
  def reiniciar do
    Application.stop(:emergencias)
    File.rm_rf!(Emergencias.Persistencia.Archivo.directorio())
    {:ok, _} = Application.ensure_all_started(:emergencias)
    :ok
  end

  @doc "Conecta un usuario y retorna el pid de su sesión."
  def sesion(usuario, tipo, zona \\ "centro") do
    {:ok, pid, _usuario, _mensaje} = Sesiones.conectar([usuario, "1234", tipo, zona])
    pid
  end

  @doc "Ejecuta varios comandos y falla si alguno no responde :ok."
  def preparar(sesion, lineas) do
    Enum.each(lineas, fn linea ->
      case Sesion.ejecutar(sesion, linea) do
        {:ok, _} -> :ok
        {:error, motivo} -> raise "Falló la preparación '#{linea}': #{motivo}"
      end
    end)
  end
end
