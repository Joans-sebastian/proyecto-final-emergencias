defmodule Emergencias.Estado.GestorAlbergues do
  @moduledoc """
  GenServer con los albergues (`albergues.txt`). Ingresos y salidas pasan por
  este proceso, uno a la vez, así la ocupación nunca supera la capacidad aunque
  lleguen varios ingresos al mismo tiempo.
  """

  use GenServer

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Estado.Persistente

  @archivo "albergues.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Registra un albergue ya validado. El código no se puede repetir."
  def registrar(%Albergue{} = albergue), do: GenServer.call(__MODULE__, {:registrar, albergue})

  def ingresar(codigo, documento, usuario),
    do: GenServer.call(__MODULE__, {:ingresar, codigo, documento, usuario})

  def salir(codigo, documento, usuario),
    do: GenServer.call(__MODULE__, {:salir, codigo, documento, usuario})

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def listar, do: GenServer.call(__MODULE__, :listar)

  @impl true
  def init(:ok), do: {:ok, Persistente.cargar(@archivo, &Albergue.desde_mapa/1, :codigo)}

  @impl true
  def handle_call({:registrar, albergue}, _from, estado) do
    case codigo_libre(estado, albergue.codigo) do
      :ok -> guardar_y_responder(estado, albergue)
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:ingresar, codigo, documento, usuario}, _from, estado) do
    modificar(estado, codigo, &Albergue.ingresar(&1, documento, usuario))
  end

  def handle_call({:salir, codigo, documento, usuario}, _from, estado) do
    modificar(estado, codigo, &Albergue.salir(&1, documento, usuario))
  end

  def handle_call({:obtener, codigo}, _from, estado), do: {:reply, fetch(estado, codigo), estado}

  def handle_call(:listar, _from, estado),
    do: {:reply, estado |> Map.values() |> Enum.sort_by(& &1.codigo), estado}

  defp modificar(estado, codigo, funcion) do
    with {:ok, albergue} <- fetch(estado, codigo),
         {:ok, actualizado} <- funcion.(albergue) do
      guardar_y_responder(estado, actualizado)
    else
      error -> {:reply, error, estado}
    end
  end

  defp codigo_libre(estado, codigo) do
    if Map.has_key?(estado, codigo),
      do: {:error, "Ya existe un albergue con el código '#{codigo}'"},
      else: :ok
  end

  defp fetch(estado, codigo) do
    case Map.fetch(estado, String.trim(to_string(codigo))) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, "El albergue '#{codigo}' no existe"}
    end
  end

  defp guardar_y_responder(estado, albergue) do
    nuevo = Map.put(estado, albergue.codigo, albergue)
    Persistente.guardar(@archivo, nuevo, &Albergue.a_mapa/1)
    {:reply, {:ok, albergue}, nuevo}
  end
end
