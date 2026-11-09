defmodule Emergencias.Persistencia.Archivo do
  @moduledoc """
  Persistencia en **archivos de texto plano**.

  Cada archivo guarda un registro por línea en formato JSON (texto legible que
  se puede abrir con cualquier editor). Se eligió JSON por línea porque:

  - es texto plano, como pide el enunciado;
  - admite estructuras anidadas (el árbol de zonas, historiales, inventario por ubicación);
  - se lee sin evaluar código (a diferencia de `Code.eval_string/1`, que ejecutaría
    cualquier cosa que alguien escriba en el archivo).

  La escritura es atómica: primero se escribe un archivo temporal y luego se
  renombra, así un corte a mitad de escritura no deja el archivo dañado.
  La carpeta se configura en `config/config.exs` (`:directorio_datos`).
  """

  require Logger

  @doc "Carpeta de datos configurada."
  def directorio, do: Application.get_env(:emergencias, :directorio_datos, "datos")

  @doc "Ruta completa de un archivo de datos."
  def ruta(nombre), do: Path.join(directorio(), nombre)

  @doc """
  Reemplaza el contenido de `nombre` con los `registros` (lista de mapas),
  uno por línea. Retorna `:ok` o `{:error, motivo}`.
  """
  def guardar(nombre, registros) do
    File.mkdir_p!(directorio())
    destino = ruta(nombre)
    temporal = destino <> ".tmp"
    contenido = Enum.map(registros, &[JSON.encode!(&1), "\n"])

    with :ok <- File.write(temporal, contenido),
         :ok <- File.rename(temporal, destino) do
      :ok
    else
      {:error, razon} ->
        mensaje = "No se pudo guardar #{destino}: #{:file.format_error(razon)}"
        Logger.error(mensaje)
        {:error, mensaje}
    end
  end

  @doc """
  Lee los registros de `nombre` como una lista de mapas (claves de texto).
  Si el archivo no existe retorna `[]`. Las líneas dañadas se ignoran y se
  informan en el log, para que un archivo editado a mano no tumbe el sistema.
  """
  def cargar(nombre) do
    origen = ruta(nombre)

    if File.regular?(origen) do
      origen
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.flat_map(&decodificar(&1, origen))
      |> Enum.to_list()
    else
      []
    end
  end

  @doc "Agrega una línea al final de `nombre` (se usa para la bitácora de actividad)."
  def agregar_linea(nombre, linea) do
    File.mkdir_p!(directorio())
    File.write(ruta(nombre), [linea, "\n"], [:append, :utf8])
  end

  @doc "Lee las líneas de un archivo de texto (vacío si no existe)."
  def leer_lineas(nombre) do
    origen = ruta(nombre)

    if File.regular?(origen) do
      origen |> File.stream!() |> Stream.map(&String.trim_trailing/1) |> Enum.to_list()
    else
      []
    end
  end

  defp decodificar(linea, origen) do
    case JSON.decode(linea) do
      {:ok, mapa} when is_map(mapa) ->
        [mapa]

      _ ->
        Logger.warning("Línea ignorada en #{origen}: no es un registro válido")
        []
    end
  end
end
