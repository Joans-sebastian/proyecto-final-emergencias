defmodule Emergencias.Estado.GestorMascotas do
  @moduledoc """
  GenServer con los reportes de mascotas perdidas y encontradas (`mascotas.txt`).

  `confirmar/3` cierra los dos reportes en un solo mensaje del GenServer: si dos
  voluntarios confirman la misma pareja a la vez, solo el primero lo logra y el
  segundo recibe un error (un reporte no se resuelve dos veces).
  """

  use GenServer

  alias Emergencias.Dominio.{Comun, Mascota}
  alias Emergencias.Estado.Persistente

  @archivo "mascotas.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Guarda un reporte ya validado y le asigna su identificador (MA001, ...)."
  def reportar(%Mascota{} = mascota), do: GenServer.call(__MODULE__, {:reportar, mascota})

  @doc """
  Compara cada reporte perdido abierto con cada encontrado abierto. Las parejas
  con puntaje >= umbral se retornan ordenadas de mayor a menor y sus reportes
  pasan a `posible_coincidencia`.
  """
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :coincidencias)

  @doc "Confirma la coincidencia entre dos reportes y cierra ambos."
  def confirmar(id_a, id_b, usuario),
    do: GenServer.call(__MODULE__, {:confirmar, id_a, id_b, usuario})

  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})

  @impl true
  def init(:ok), do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Mascota, &1), :id)}

  @impl true
  def handle_call({:reportar, mascota}, _from, estado) do
    mascota = %{mascota | id: Comun.siguiente_id("MA", estado)}
    guardar_y_responder(estado, [mascota], {:ok, mascota})
  end

  def handle_call(:coincidencias, _from, estado) do
    abiertas = estado |> Map.values() |> Enum.filter(&Mascota.abierta?/1)
    perdidas = Enum.filter(abiertas, &(&1.tipo == "perdida"))
    encontradas = Enum.filter(abiertas, &(&1.tipo == "encontrada"))

    parejas =
      for(perdida <- perdidas, encontrada <- encontradas, do: {perdida, encontrada})
      |> Enum.map(fn {perdida, encontrada} ->
        {puntaje, razones} = Mascota.puntaje(perdida, encontrada)
        %{perdida: perdida, encontrada: encontrada, puntaje: puntaje, razones: razones}
      end)
      |> Enum.filter(&(&1.puntaje >= Mascota.umbral()))
      |> Enum.sort_by(&{-&1.puntaje, &1.perdida.id, &1.encontrada.id})

    marcadas =
      parejas
      |> Enum.flat_map(&[&1.perdida, &1.encontrada])
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&%{&1 | estado: "posible_coincidencia"})

    nuevo = Enum.reduce(marcadas, estado, &Map.put(&2, &1.id, &1))
    if marcadas != [], do: Persistente.guardar(@archivo, nuevo, &Comun.a_mapa/1)
    {:reply, {:ok, parejas}, nuevo}
  end

  def handle_call({:confirmar, id_a, id_b, usuario}, _from, estado) do
    with {:ok, a} <- fetch(estado, id_a),
         {:ok, b} <- fetch(estado, id_b),
         :ok <- validar_pareja(a, b) do
      resuelta_a = %{a | estado: "resuelta", coincidencia: b.id, resuelta_por: usuario}
      resuelta_b = %{b | estado: "resuelta", coincidencia: a.id, resuelta_por: usuario}
      {puntaje, _razones} = Mascota.puntaje(perdida_de(a, b), encontrada_de(a, b))

      guardar_y_responder(
        estado,
        [resuelta_a, resuelta_b],
        {:ok, resuelta_a, resuelta_b, puntaje}
      )
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado
      |> Map.values()
      |> Enum.filter(&Mascota.cumple?(&1, filtros))
      |> Enum.sort_by(& &1.id)

    {:reply, lista, estado}
  end

  defp validar_pareja(a, b) do
    cond do
      a.id == b.id ->
        {:error, "Debe indicar dos reportes distintos"}

      a.estado == "resuelta" ->
        {:error, "El reporte #{a.id} ya fue resuelto; no se puede cerrar dos veces"}

      b.estado == "resuelta" ->
        {:error, "El reporte #{b.id} ya fue resuelto; no se puede cerrar dos veces"}

      a.tipo == b.tipo ->
        {:error, "Una coincidencia une un reporte perdido con uno encontrado"}

      a.especie != b.especie ->
        {:error, "Los reportes son de especies distintas (#{a.especie} y #{b.especie})"}

      true ->
        :ok
    end
  end

  defp perdida_de(a, b), do: if(a.tipo == "perdida", do: a, else: b)
  defp encontrada_de(a, b), do: if(a.tipo == "encontrada", do: a, else: b)

  defp fetch(estado, id) do
    case Map.fetch(estado, String.upcase(to_string(id))) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, "El reporte de mascota '#{id}' no existe"}
    end
  end

  defp guardar_y_responder(estado, mascotas, respuesta) do
    nuevo = Enum.reduce(mascotas, estado, &Map.put(&2, &1.id, &1))
    Persistente.guardar(@archivo, nuevo, &Comun.a_mapa/1)
    {:reply, respuesta, nuevo}
  end
end
