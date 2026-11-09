defmodule Emergencias.Estado.GestorNecesidades do
  @moduledoc """
  GenServer con las necesidades puntuales (`necesidades.txt`).

  La asignación de recursos se hace aquí, en un solo mensaje:

  1. se revisa que la necesidad pueda recibir la cantidad (estado `pendiente`
     y que no supere lo que falta);
  2. se pide al `GestorRecursos` que retire el inventario (todo o nada);
  3. se anotan los recursos en la necesidad.

  Como este proceso atiende un mensaje a la vez, una misma necesidad no puede
  recibir dos asignaciones a la vez, ni volver a consumir recursos una vez atendida.
  """

  use GenServer

  alias Emergencias.Dominio.{Comun, Necesidad}
  alias Emergencias.Estado.{GestorRecursos, Persistente}

  @archivo "necesidades.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Registra una necesidad ya validada y le asigna su identificador (N001, N002, ...)."
  def registrar(%Necesidad{} = necesidad), do: GenServer.call(__MODULE__, {:registrar, necesidad})

  @doc "Asigna `cantidad` unidades del recurso `tipo` (código, nombre o categoría) a la necesidad."
  def asignar(id, tipo, cantidad, usuario),
    do: GenServer.call(__MODULE__, {:asignar, id, tipo, cantidad, usuario}, 15_000)

  @doc """
  Atiende la necesidad pendiente más urgente (por prioridad y antigüedad) que se
  pueda cubrir con el inventario actual. `tipo` = nil considera todos los tipos.
  """
  def atender_siguiente(tipo, usuario),
    do: GenServer.call(__MODULE__, {:atender_siguiente, tipo, usuario}, 15_000)

  def cambiar_estado(id, estado, usuario),
    do: GenServer.call(__MODULE__, {:cambiar_estado, id, estado, usuario}, 15_000)

  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})

  @impl true
  def init(:ok), do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Necesidad, &1), :id)}

  @impl true
  def handle_call({:registrar, necesidad}, _from, estado) do
    necesidad = %{necesidad | id: Comun.siguiente_id("N", estado)}
    guardar_y_responder(estado, necesidad, {:ok, necesidad})
  end

  def handle_call({:asignar, id, tipo, cantidad, usuario}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, cantidad} <- Comun.entero_positivo(cantidad, "La cantidad a asignar"),
         {:ok, actualizada, partes} <- asignar_a(necesidad, tipo, cantidad, usuario) do
      guardar_y_responder(estado, actualizada, {:ok, actualizada, partes})
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:atender_siguiente, tipo, usuario}, _from, estado) do
    filtros =
      if tipo, do: %{"estado" => "pendiente", "tipo" => tipo}, else: %{"estado" => "pendiente"}

    candidatas =
      estado
      |> Map.values()
      |> Enum.filter(&Necesidad.cumple?(&1, filtros))
      |> Necesidad.ordenar()

    case intentar_en_orden(candidatas, usuario, []) do
      {:ok, actualizada, partes} ->
        guardar_y_responder(estado, actualizada, {:ok, actualizada, partes})

      {:error, []} ->
        {:reply,
         {:error, "No hay necesidades pendientes" <> if(tipo, do: " de tipo #{tipo}", else: "")},
         estado}

      {:error, motivos} ->
        {:reply,
         {:error,
          "Ninguna necesidad pendiente se puede cubrir con el inventario actual:\n  " <>
            Enum.join(motivos, "\n  ")}, estado}
    end
  end

  def handle_call({:cambiar_estado, id, nuevo, usuario}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, actualizada} <- Necesidad.cambiar_estado(necesidad, nuevo, usuario),
         {:ok, actualizada} <- devolver_si_cancela(necesidad, actualizada, usuario) do
      guardar_y_responder(estado, actualizada, {:ok, actualizada})
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, id}, _from, estado), do: {:reply, buscar(estado, id), estado}

  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado
      |> Map.values()
      |> Enum.filter(&Necesidad.cumple?(&1, filtros))
      |> Necesidad.ordenar()

    {:reply, lista, estado}
  end

  # **Recursiva.** Recorre las necesidades en orden de prioridad y atiende la
  # primera que se pueda cubrir por completo; acumula el motivo de cada fallo.
  defp intentar_en_orden([], _usuario, motivos), do: {:error, Enum.reverse(motivos)}

  defp intentar_en_orden([necesidad | resto], usuario, motivos) do
    case asignar_a(necesidad, necesidad.tipo, Necesidad.faltante(necesidad), usuario) do
      {:ok, actualizada, partes} ->
        {:ok, actualizada, partes}

      {:error, motivo} ->
        intentar_en_orden(resto, usuario, ["#{necesidad.id}: #{motivo}" | motivos])
    end
  end

  defp asignar_a(necesidad, tipo, cantidad, usuario) do
    with :ok <- Necesidad.puede_recibir(necesidad, cantidad),
         {:ok, partes} <-
           llamar_recursos(fn ->
             GestorRecursos.retirar(tipo, cantidad, necesidad.zona, necesidad.id, usuario)
           end),
         {:ok, actualizada} <- Necesidad.registrar_asignacion(necesidad, partes, usuario) do
      {:ok, actualizada, partes}
    end
  end

  # Al cancelar una necesidad que ya había recibido recursos, se devuelven al inventario.
  defp devolver_si_cancela(%{asignaciones: partes}, %{estado: "cancelada"} = actualizada, usuario)
       when partes != [] do
    with :ok <-
           llamar_recursos(fn -> GestorRecursos.devolver(partes, actualizada.id, usuario) end) do
      {:ok, %{actualizada | asignada: 0, asignaciones: []}}
    end
  end

  defp devolver_si_cancela(_anterior, actualizada, _usuario), do: {:ok, actualizada}

  # Si el GestorRecursos se cayó (y el Supervisor lo está reiniciando), se
  # responde un error en lugar de tumbar también este proceso.
  defp llamar_recursos(funcion) do
    funcion.()
  catch
    :exit, _razon ->
      {:error, "El servicio de recursos no está disponible en este momento; intente de nuevo"}
  end

  defp buscar(estado, id) do
    case Map.fetch(estado, String.upcase(to_string(id))) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, "La necesidad '#{id}' no existe"}
    end
  end

  defp guardar_y_responder(estado, necesidad, respuesta) do
    nuevo = Map.put(estado, necesidad.id, necesidad)
    Persistente.guardar(@archivo, nuevo, &Comun.a_mapa/1)
    {:reply, respuesta, nuevo}
  end
end
