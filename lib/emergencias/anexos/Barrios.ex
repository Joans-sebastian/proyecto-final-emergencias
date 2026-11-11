defmodule Emergencias.Anexos.Barrios do
  @moduledoc """
  Barrios registrados a mano (`barrios.txt`).

  No hay barrios escritos en el código: cada barrio nuevo se registra con su
  **nombre** y su **zona**, y recibe el siguiente código: el primero `B01`, el
  segundo `B02` y así consecutivamente.

  Es un GenServer, como los gestores: atiende un registro a la vez, así dos
  usuarios que registran al mismo tiempo nunca reciben el mismo código.

      registrar_barrio "La Castellana" norte     → B01
      registrar_barrio Granada centro            → B02
      reportar_mascota MT1 ES01 Luna CO01 TA2 B01 3001112233
  """

  use GenServer

  alias Emergencias.Dominio.Comun
  alias Emergencias.Estado.Persistente

  @archivo "barrios.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Registra un barrio con su zona y le asigna el siguiente código (B01, B02...).
  Si ya existe un barrio con ese nombre, retorna el que ya estaba.
  Retorna `{:ok, barrio, :nuevo | :existente}` o `{:error, motivo}`.
  """
  def registrar(nombre, zona) do
    with {:ok, nombre} <- Comun.requerido(nombre, "El nombre del barrio"),
         {:ok, zona} <- Comun.requerido(zona, "La zona del barrio"),
         {:ok, zona} <- Comun.codigo(zona, "Zona del barrio") do
      if activo?(),
        do: GenServer.call(__MODULE__, {:registrar, nombre, zona}),
        else: {:error, "El registro de barrios no está activo"}
    end
  end

  @doc "Barrios registrados, ordenados por código: `[%{codigo, nombre, zona}]`."
  def listar do
    mapa = if activo?(), do: GenServer.call(__MODULE__, :listar), else: cargar()
    mapa |> Map.values() |> Enum.sort_by(& &1.codigo)
  end

  @doc """
  **Recursiva.** Siguiente código libre: B01, B02, ... (salta los que ya existen).

      iex> Emergencias.Anexos.Barrios.siguiente_codigo(%{})
      "B01"
      iex> Emergencias.Anexos.Barrios.siguiente_codigo(%{"B01" => :x, "B02" => :y})
      "B03"
  """
  def siguiente_codigo(existentes, numero \\ 1) do
    codigo = "B" <> String.pad_leading(Integer.to_string(numero), 2, "0")

    if Map.has_key?(existentes, codigo),
      do: siguiente_codigo(existentes, numero + 1),
      else: codigo
  end

  @impl true
  def init(:ok), do: {:ok, cargar()}

  @impl true
  def handle_call({:registrar, nombre, zona}, _from, estado) do
    case Enum.find(Map.values(estado), &(Comun.normalizar(&1.nombre) == Comun.normalizar(nombre))) do
      nil ->
        barrio = %{codigo: siguiente_codigo(estado), nombre: nombre, zona: zona}
        nuevo = Map.put(estado, barrio.codigo, barrio)
        Persistente.guardar(@archivo, nuevo, & &1)
        {:reply, {:ok, barrio, :nuevo}, nuevo}

      existente ->
        {:reply, {:ok, existente, :existente}, estado}
    end
  end

  def handle_call(:listar, _from, estado), do: {:reply, estado, estado}

  defp activo?, do: Process.whereis(__MODULE__) != nil

  defp cargar,
    do:
      Persistente.cargar(
        @archivo,
        &%{codigo: &1["codigo"], nombre: &1["nombre"], zona: &1["zona"]},
        :codigo
      )
end
