defmodule Emergencias.Estado.GestorMensajes do
  @moduledoc "GenServer con los mensajes entre familiares (`mensajes.txt`)."

  use GenServer

  alias Emergencias.Dominio.{Comun, Mensaje}
  alias Emergencias.Estado.Persistente

  @archivo "mensajes.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Guarda un mensaje ya validado y le asigna su identificador (M001, ...)."
  def enviar(%Mensaje{} = mensaje), do: GenServer.call(__MODULE__, {:enviar, mensaje})

  def marcar(id, estado), do: GenServer.call(__MODULE__, {:marcar, id, estado})
  def listar(documento \\ nil), do: GenServer.call(__MODULE__, {:listar, documento})

  @impl true
  def init(:ok), do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Mensaje, &1), :id)}

  @impl true
  def handle_call({:enviar, mensaje}, _from, estado),
    do: guardar_y_responder(estado, %{mensaje | id: Comun.siguiente_id("M", estado)})

  def handle_call({:marcar, id, nuevo}, _from, estado) do
    with {:ok, mensaje} <- fetch(estado, id),
         {:ok, actualizado} <- Mensaje.marcar(mensaje, nuevo) do
      guardar_y_responder(estado, actualizado)
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:listar, documento}, _from, estado) do
    lista =
      estado
      |> Map.values()
      |> Enum.filter(&(documento == nil or &1.documento == documento))
      |> Enum.sort_by(& &1.id)

    {:reply, lista, estado}
  end

  defp fetch(estado, id) do
    case Map.fetch(estado, String.upcase(to_string(id))) do
      {:ok, mensaje} -> {:ok, mensaje}
      :error -> {:error, "El mensaje '#{id}' no existe"}
    end
  end

  defp guardar_y_responder(estado, mensaje) do
    nuevo = Map.put(estado, mensaje.id, mensaje)
    Persistente.guardar(@archivo, nuevo, &Comun.a_mapa/1)
    {:reply, {:ok, mensaje}, nuevo}
  end
end
