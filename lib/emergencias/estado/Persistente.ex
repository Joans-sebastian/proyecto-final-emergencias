defmodule Emergencias.Estado.Persistente do
  @moduledoc """
  Funciones comunes de los GenServers con estado: cargar su mapa desde el
  archivo de texto al iniciar y guardarlo después de cada cambio.

  Como cada GenServer vuelve a leer su archivo en `init/1`, cuando el
  Supervisor lo reinicia después de una falla recupera los datos guardados.
  """

  alias Emergencias.Persistencia.Archivo

  @doc "Carga `archivo` y lo convierte en `%{clave => struct}`."
  def cargar(archivo, desde_mapa, clave) do
    archivo
    |> Archivo.cargar()
    |> Enum.map(desde_mapa)
    |> Map.new(&{Map.fetch!(&1, clave), &1})
  end

  @doc "Guarda el mapa de structs, ordenado por su clave, un registro por línea."
  def guardar(archivo, mapa, a_mapa) do
    registros =
      mapa
      |> Enum.sort_by(fn {clave, _valor} -> clave end)
      |> Enum.map(fn {_clave, valor} -> a_mapa.(valor) end)

    Archivo.guardar(archivo, registros)
  end
end
