defmodule Emergencias.Estado.Bitacora do
  @moduledoc """
  Registro de la actividad de cada usuario (`actividad.txt`, una línea por acción).

  `registrar/3` usa `GenServer.cast`: la sesión no espera a que se escriba la
  línea. Los mensajes se procesan en orden, así la bitácora queda en el orden
  en que llegaron las acciones.
  """

  use GenServer

  alias Emergencias.Dominio.Comun
  alias Emergencias.Persistencia.Archivo

  @archivo "actividad.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Anota una acción: `resultado` es `:ok` o `:error`."
  def registrar(usuario, accion, resultado),
    do: GenServer.cast(__MODULE__, {:registrar, usuario, accion, resultado})

  @doc "Últimas `cantidad` acciones (de un usuario o, con `nil`, de todos)."
  def listar(usuario \\ nil, cantidad \\ 20),
    do: GenServer.call(__MODULE__, {:listar, usuario, cantidad})

  @impl true
  def init(:ok), do: {:ok, nil}

  @impl true
  def handle_cast({:registrar, usuario, accion, resultado}, estado) do
    etiqueta = if resultado == :ok, do: "OK   ", else: "ERROR"
    accion = String.replace(accion, ~r/[\r\n]+/, " ")
    Archivo.agregar_linea(@archivo, "#{Comun.ahora()} | #{usuario} | #{etiqueta} | #{accion}")
    {:noreply, estado}
  end

  @impl true
  def handle_call({:listar, usuario, cantidad}, _from, estado) do
    lineas =
      @archivo
      |> Archivo.leer_lineas()
      |> Enum.filter(&(usuario == nil or String.contains?(&1, " | #{usuario} | ")))
      |> Enum.take(-cantidad)

    {:reply, lineas, estado}
  end
end
