defmodule Emergencias.Dominio.Recurso do
  @moduledoc """
  Recurso del inventario (agua, alimentos, medicamentos, ...).

  Un recurso tiene existencias en una o varias **ubicaciones** (centros de
  acopio, albergues, puntos de atención):

      existencias: %{"centro_acopio" => 50, "A02" => 30}

  Códigos de recurso permitidos: `R001`, `R002`, `R003`. Ubicaciones:
  `centro_acopio`, `bodega`, `fundacion` y los albergues `A01`–`A03`.

  Cada entrada, salida, transferencia, asignación o devolución queda en
  `movimientos`. Ninguna operación deja cantidades negativas.
  """

  alias Emergencias.Dominio.Comun

  defstruct [
    :codigo,
    :nombre,
    :categoria,
    :unidad,
    :zona,
    :creado,
    existencias: %{},
    movimientos: []
  ]

  @doc "Crea un recurso con su existencia inicial en `ubicacion`."
  def crear(codigo, nombre, cantidad, unidad, ubicacion, categoria, zona, usuario) do
    with {:ok, codigo} <- Comun.recurso(codigo, "Código del recurso"),
         {:ok, nombre} <- Comun.requerido(nombre, "Nombre del recurso"),
         {:ok, cantidad} <- Comun.entero_no_negativo(cantidad, "La cantidad"),
         {:ok, unidad} <- Comun.requerido(unidad, "Unidad de medida"),
         {:ok, ubicacion} <- Comun.ubicacion(ubicacion, "Ubicación"),
         {:ok, zona} <- Comun.codigo(zona, "Zona") do
      nombre = Comun.normalizar(nombre)
      categoria = if categoria in [nil, ""], do: nombre, else: Comun.normalizar(categoria)

      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         categoria: categoria,
         unidad: unidad,
         zona: zona,
         creado: Comun.ahora(),
         existencias: %{ubicacion => cantidad},
         movimientos: [
           movimiento("entrada", ubicacion, nil, cantidad, "registro inicial", usuario)
         ]
       }}
    end
  end

  @doc """
  Lee desde teclado los datos de un recurso (con `Util2` del curso).
  `usuario` queda en el primer movimiento del historial.
  """
  def ingresar(usuario) do
    Util2.mostrar("\nIngrese los datos del recurso:\n", :mensaje)

    crear(
      Util2.ingresar("Código: ", :texto),
      Util2.ingresar("Nombre (agua, alimentos, ...): ", :texto),
      Util2.ingresar("Cantidad disponible: ", :entero),
      Util2.ingresar("Unidad de medida: ", :texto),
      Util2.ingresar("Ubicación (centro de apoyo): ", :texto),
      Comun.opcional(Util2.ingresar("Categoría (vacío = igual al nombre): ", :texto)),
      Util2.ingresar("Zona: ", :texto),
      usuario
    )
  end

  @doc "Representación del recurso como texto, con sus existencias por ubicación."
  def to_string(%__MODULE__{} = r) do
    ubicaciones =
      r.existencias
      |> Util2.ordenar()
      |> Enum.map_join(", ", fn {ubicacion, cantidad} -> "#{ubicacion}: #{cantidad}" end)

    "#{r.codigo} | #{r.nombre} (#{r.categoria}) | total #{total(r)} #{r.unidad} | " <>
      "zona #{r.zona} | #{ubicaciones}"
  end

  @doc "Cantidad total disponible sumando todas las ubicaciones."
  def total(%__MODULE__{existencias: existencias}), do: existencias |> Map.values() |> Enum.sum()

  @doc "Cantidad disponible en una ubicación."
  def en(%__MODULE__{existencias: existencias}, ubicacion), do: Map.get(existencias, ubicacion, 0)

  @doc "Registra una entrada de inventario."
  def entrada(%__MODULE__{} = recurso, ubicacion, cantidad, detalle, usuario, tipo \\ "entrada") do
    with {:ok, ubicacion} <- Comun.ubicacion(ubicacion, "Ubicación"),
         {:ok, cantidad} <- Comun.entero_positivo(cantidad, "La cantidad") do
      {:ok,
       %{
         recurso
         | existencias: Map.update(recurso.existencias, ubicacion, cantidad, &(&1 + cantidad)),
           movimientos:
             recurso.movimientos ++ [movimiento(tipo, ubicacion, nil, cantidad, detalle, usuario)]
       }}
    end
  end

  @doc "Registra una salida. Falla si no hay suficiente en esa ubicación."
  def salida(%__MODULE__{} = recurso, ubicacion, cantidad, detalle, usuario, tipo \\ "salida") do
    with {:ok, cantidad} <- Comun.entero_positivo(cantidad, "La cantidad"),
         :ok <- hay_suficiente(recurso, ubicacion, cantidad) do
      {:ok,
       %{
         recurso
         | existencias: Map.update!(recurso.existencias, ubicacion, &(&1 - cantidad)),
           movimientos:
             recurso.movimientos ++ [movimiento(tipo, ubicacion, nil, cantidad, detalle, usuario)]
       }}
    end
  end

  @doc "Mueve existencias entre dos centros de apoyo."
  def transferir(%__MODULE__{} = recurso, origen, destino, cantidad, usuario) do
    with {:ok, destino} <- Comun.ubicacion(destino, "Destino"),
         :ok <-
           if(origen == destino, do: {:error, "El origen y el destino son iguales"}, else: :ok),
         {:ok, cantidad} <- Comun.entero_positivo(cantidad, "La cantidad"),
         :ok <- hay_suficiente(recurso, origen, cantidad) do
      existencias =
        recurso.existencias
        |> Map.update!(origen, &(&1 - cantidad))
        |> Map.update(destino, cantidad, &(&1 + cantidad))

      {:ok,
       %{
         recurso
         | existencias: existencias,
           movimientos:
             recurso.movimientos ++
               [movimiento("transferencia", origen, destino, cantidad, "", usuario)]
       }}
    end
  end

  defp hay_suficiente(recurso, ubicacion, cantidad) do
    disponible = en(recurso, ubicacion)

    cond do
      not Map.has_key?(recurso.existencias, ubicacion) ->
        {:error, "El recurso #{recurso.codigo} no tiene existencias en '#{ubicacion}'"}

      cantidad > disponible ->
        {:error,
         "Inventario insuficiente de #{recurso.codigo} en #{ubicacion}: hay #{disponible} " <>
           "#{recurso.unidad} y se pidieron #{cantidad}"}

      true ->
        :ok
    end
  end

  @doc "Indica si el recurso sirve para el `tipo` pedido (código, nombre o categoría)."
  def coincide?(%__MODULE__{} = recurso, tipo) do
    recurso.codigo == tipo or recurso.nombre == Comun.normalizar(tipo) or
      recurso.categoria == Comun.normalizar(tipo)
  end

  @doc """
  Fuentes de donde se puede retirar, como tuplas `{codigo, ubicacion, disponible}`:
  primero las de la misma zona de la necesidad y, dentro de ellas, las de más existencias.
  """
  def fuentes(recursos, zona_preferida) do
    for recurso <- recursos,
        {ubicacion, disponible} <- recurso.existencias,
        disponible > 0 do
      {recurso.zona == zona_preferida, recurso.codigo, ubicacion, disponible}
    end
    |> Enum.sort_by(fn {misma_zona, codigo, ubicacion, disponible} ->
      {not misma_zona, -disponible, codigo, ubicacion}
    end)
    |> Enum.map(fn {_misma_zona, codigo, ubicacion, disponible} ->
      {codigo, ubicacion, disponible}
    end)
  end

  @doc """
  **Recursiva.** Decide de qué fuentes sacar `cantidad` unidades. Toma de cada
  fuente lo que pueda hasta completar. Si la suma de todas las fuentes no
  alcanza, retorna `:insuficiente` y no se toma nada (todo o nada).

      iex> Emergencias.Dominio.Recurso.planear_retiro([{"R1", "c1", 20}, {"R2", "c2", 50}], 30)
      {:ok, [%{"codigo" => "R1", "ubicacion" => "c1", "cantidad" => 20},
             %{"codigo" => "R2", "ubicacion" => "c2", "cantidad" => 10}]}
  """
  def planear_retiro(fuentes, cantidad), do: planear(fuentes, cantidad, [])

  defp planear(_fuentes, 0, partes), do: {:ok, Enum.reverse(partes)}
  defp planear([], _faltante, _partes), do: :insuficiente

  defp planear([{codigo, ubicacion, disponible} | resto], faltante, partes) do
    toma = min(disponible, faltante)
    parte = %{"codigo" => codigo, "ubicacion" => ubicacion, "cantidad" => toma}
    planear(resto, faltante - toma, [parte | partes])
  end

  defp movimiento(tipo, ubicacion, destino, cantidad, detalle, usuario) do
    %{
      "fecha" => Comun.ahora(),
      "tipo" => tipo,
      "ubicacion" => ubicacion,
      "destino" => destino,
      "cantidad" => cantidad,
      "detalle" => detalle,
      "usuario" => usuario
    }
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
