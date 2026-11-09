defmodule Emergencias.Dominio.Albergue do
  @moduledoc """
  Albergue temporal. Los ocupantes se guardan en un `MapSet` de documentos:
  así una misma persona no puede ingresar dos veces y contar la ocupación es
  directo (`MapSet.size/1`). La ocupación nunca supera la capacidad máxima.
  """

  alias Emergencias.Dominio.Comun

  defstruct [:codigo, :nombre, :zona, :capacidad, :creado, ocupantes: MapSet.new(), historial: []]

  @doc "Crea un albergue vacío validando sus datos."
  def crear(codigo, nombre, zona, capacidad) do
    with {:ok, codigo} <- Comun.albergue(codigo, "Código del albergue"),
         {:ok, nombre} <- Comun.requerido(nombre, "El nombre del albergue"),
         {:ok, zona} <- Comun.codigo(zona, "Zona"),
         {:ok, capacidad} <- Comun.entero_positivo(capacidad, "La capacidad máxima") do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         zona: zona,
         capacidad: capacidad,
         creado: Comun.ahora()
       }}
    end
  end

  @doc "Lee desde teclado los datos de un albergue (con `Util2` del curso)."
  def ingresar do
    Util2.mostrar("\nIngrese los datos del albergue:\n", :mensaje)

    crear(
      Util2.ingresar("Código: ", :texto),
      Util2.ingresar("Nombre: ", :texto),
      Util2.ingresar("Zona: ", :texto),
      Util2.ingresar("Capacidad máxima: ", :entero)
    )
  end

  @doc "Representación del albergue como texto, con su ocupación."
  def to_string(%__MODULE__{} = a) do
    "#{a.codigo} | #{a.nombre} | zona #{a.zona} | ocupación #{ocupacion(a)}/#{a.capacidad} " <>
      "(#{porcentaje(a)}%) | #{cupos(a)} cupos disponibles"
  end

  @doc "Personas alojadas actualmente."
  def ocupacion(%__MODULE__{ocupantes: ocupantes}), do: MapSet.size(ocupantes)

  @doc "Cupos libres."
  def cupos(%__MODULE__{} = albergue), do: albergue.capacidad - ocupacion(albergue)

  @doc "Porcentaje de ocupación con un decimal."
  def porcentaje(%__MODULE__{} = albergue),
    do: Float.round(ocupacion(albergue) * 100 / albergue.capacidad, 1)

  @doc "Registra el ingreso de una persona (por documento)."
  def ingresar(%__MODULE__{} = albergue, documento, usuario) do
    cond do
      MapSet.member?(albergue.ocupantes, documento) ->
        {:error, "La persona #{documento} ya está registrada en el albergue #{albergue.codigo}"}

      ocupacion(albergue) >= albergue.capacidad ->
        {:error,
         "El albergue #{albergue.codigo} está lleno (#{ocupacion(albergue)}/#{albergue.capacidad}); no se puede superar la capacidad"}

      true ->
        {:ok,
         %{
           albergue
           | ocupantes: MapSet.put(albergue.ocupantes, documento),
             historial: albergue.historial ++ [Comun.evento(nil, "ingreso", usuario, documento)]
         }}
    end
  end

  @doc "Registra la salida de una persona."
  def salir(%__MODULE__{} = albergue, documento, usuario) do
    if MapSet.member?(albergue.ocupantes, documento) do
      {:ok,
       %{
         albergue
         | ocupantes: MapSet.delete(albergue.ocupantes, documento),
           historial: albergue.historial ++ [Comun.evento(nil, "salida", usuario, documento)]
       }}
    else
      {:error, "La persona #{documento} no está en el albergue #{albergue.codigo}"}
    end
  end

  def a_mapa(%__MODULE__{} = albergue) do
    albergue
    |> Map.from_struct()
    |> Map.put(:ocupantes, albergue.ocupantes |> MapSet.to_list() |> Enum.sort())
  end

  def desde_mapa(mapa) do
    albergue = Comun.desde_mapa(__MODULE__, mapa)
    %{albergue | ocupantes: MapSet.new(albergue.ocupantes || [])}
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
