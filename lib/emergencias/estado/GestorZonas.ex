defmodule Emergencias.Estado.GestorZonas do
  @moduledoc """
  GenServer con el árbol de zonas → sectores → puntos de atención (`zonas.txt`).
  Cada línea del archivo es una zona raíz con todos sus descendientes anidados.
  """

  use GenServer

  alias Emergencias.Dominio.Zona
  alias Emergencias.Persistencia.Archivo

  @archivo "zonas.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Registra una zona raíz (`padre` = nil) o un sector/punto dentro de `padre`."
  def registrar(%Zona{} = nodo), do: GenServer.call(__MODULE__, {:registrar, nodo})

  @doc "Cambia el nivel de afectación y/o las personas afectadas de un nodo."
  def actualizar(codigo, cambios), do: GenServer.call(__MODULE__, {:actualizar, codigo, cambios})

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def arboles, do: GenServer.call(__MODULE__, :arboles)
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))

  @impl true
  def init(:ok), do: {:ok, @archivo |> Archivo.cargar() |> Enum.map(&Zona.desde_mapa/1)}

  @impl true
  def handle_call({:registrar, nodo}, _from, arboles) do
    with {:ok, nodo} <- normalizar_raiz(nodo),
         :ok <- codigo_libre(arboles, nodo.codigo),
         {:ok, nuevos} <- Zona.insertar(arboles, nodo.padre, nodo) do
      guardar(nuevos)
      {:reply, {:ok, Zona.buscar(nuevos, nodo.codigo)}, nuevos}
    else
      error -> {:reply, error, arboles}
    end
  end

  def handle_call({:actualizar, codigo, cambios}, _from, arboles) do
    with {:ok, cambios} <- validar_cambios(cambios),
         {:ok, nuevos} <- actualizar_nodo(arboles, codigo, cambios) do
      guardar(nuevos)
      {:reply, {:ok, Zona.buscar(nuevos, codigo)}, nuevos}
    else
      error -> {:reply, error, arboles}
    end
  end

  def handle_call({:obtener, codigo}, _from, arboles) do
    respuesta =
      case Zona.buscar(arboles, codigo) do
        nil -> {:error, "La zona '#{codigo}' no está registrada (use registrar_zona)"}
        nodo -> {:ok, nodo}
      end

    {:reply, respuesta, arboles}
  end

  def handle_call(:arboles, _from, arboles), do: {:reply, arboles, arboles}

  # Una zona principal solo puede ser sur, centro, norte, este u oeste.
  defp normalizar_raiz(%Zona{padre: nil} = nodo) do
    with {:ok, codigo} <- Emergencias.Dominio.Comun.zona(nodo.codigo, "Código de zona principal"),
         do: {:ok, %{nodo | codigo: codigo}}
  end

  defp normalizar_raiz(nodo), do: {:ok, nodo}

  defp codigo_libre(arboles, codigo) do
    if Zona.buscar(arboles, codigo),
      do: {:error, "Ya existe una zona, sector o punto con el código '#{codigo}'"},
      else: :ok
  end

  defp validar_cambios(cambios) do
    Enum.reduce_while(cambios, {:ok, %{}}, fn
      {"nivel", valor}, {:ok, acc} ->
        case Zona.validar_nivel(valor) do
          {:ok, nivel} -> {:cont, {:ok, Map.put(acc, :nivel, nivel)}}
          error -> {:halt, error}
        end

      {"personas", valor}, {:ok, acc} ->
        case Emergencias.Dominio.Comun.entero_no_negativo(valor, "Personas afectadas") do
          {:ok, n} -> {:cont, {:ok, Map.put(acc, :personas, n)}}
          error -> {:halt, error}
        end

      {_otro, _valor}, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, vacio} when map_size(vacio) == 0 -> {:error, "Indique nivel=... y/o personas=..."}
      otro -> otro
    end
  end

  defp actualizar_nodo(arboles, codigo, cambios) do
    case Zona.actualizar(arboles, codigo, &Map.merge(&1, cambios)) do
      {:ok, nuevos} -> {:ok, nuevos}
      :no_encontrado -> {:error, "La zona '#{codigo}' no está registrada"}
    end
  end

  defp guardar(arboles), do: Archivo.guardar(@archivo, Enum.map(arboles, &Zona.a_mapa/1))
end
