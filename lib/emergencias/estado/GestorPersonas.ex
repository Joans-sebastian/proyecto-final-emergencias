defmodule Emergencias.Estado.GestorPersonas do
  @moduledoc """
  GenServer con las personas afectadas (`personas.txt`), indexadas por documento
  (dato de referencia). El documento no se puede repetir.
  """

  use GenServer

  alias Emergencias.Dominio.{Comun, Persona}
  alias Emergencias.Estado.Persistente

  @archivo "personas.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Registra una persona ya validada. El documento no se puede repetir."
  def registrar(%Persona{} = persona), do: GenServer.call(__MODULE__, {:registrar, persona})

  @doc "Cambia el estado de una persona. `cambios` permite actualizar otros campos (p. ej. el albergue)."
  def cambiar_estado(documento, estado, usuario, detalle \\ "", cambios \\ %{}),
    do:
      GenServer.call(__MODULE__, {:cambiar_estado, documento, estado, usuario, detalle, cambios})

  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, documento})
  def buscar(filtros), do: GenServer.call(__MODULE__, {:buscar, filtros})

  @impl true
  def init(:ok),
    do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Persona, &1), :documento)}

  @impl true
  def handle_call({:registrar, persona}, _from, estado) do
    case documento_libre(estado, persona.documento) do
      :ok -> guardar_y_responder(estado, %{persona | id: Comun.siguiente_id("P", estado)})
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:cambiar_estado, documento, nuevo, usuario, detalle, cambios}, _from, estado) do
    with {:ok, persona} <- fetch(estado, documento),
         {:ok, actualizada} <- Persona.cambiar_estado(persona, nuevo, usuario, detalle, cambios) do
      guardar_y_responder(estado, actualizada)
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, documento}, _from, estado),
    do: {:reply, fetch(estado, documento), estado}

  def handle_call({:buscar, filtros}, _from, estado) do
    lista =
      estado
      |> Map.values()
      |> Enum.filter(&Persona.cumple?(&1, filtros))
      |> Enum.sort_by(& &1.id)

    {:reply, lista, estado}
  end

  defp documento_libre(estado, documento) do
    if Map.has_key?(estado, documento),
      do: {:error, "Ya existe una persona registrada con el documento #{documento}"},
      else: :ok
  end

  defp fetch(estado, documento) do
    case Map.fetch(estado, String.trim(to_string(documento))) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, "No hay ninguna persona registrada con el documento '#{documento}'"}
    end
  end

  defp guardar_y_responder(estado, persona) do
    nuevo = Map.put(estado, persona.documento, persona)
    Persistente.guardar(@archivo, nuevo, &Comun.a_mapa/1)
    {:reply, {:ok, persona}, nuevo}
  end
end
