defmodule Emergencias.Dominio.Necesidad do
  @moduledoc """
  Solicitud de ayuda puntual (agua, alimentos, rescate, ...).

  Estados y transiciones válidas:

      pendiente ──► asignada ──► en_atencion ──► atendida
          │             │  └──────────────────────► atendida
          └─────────────┴──► cancelada

  - Una necesidad recibe recursos solo mientras está `pendiente`. Cuando la
    cantidad asignada completa la requerida, pasa sola a `asignada`.
  - `atendida` y `cancelada` son finales: no se pueden cerrar dos veces ni
    volver a consumir recursos.
  - La prioridad tiene un peso (crítica 4 … baja 1) que ordena las listas y
    decide qué necesidad se atiende primero (`atender_siguiente`).
  """

  alias Emergencias.Dominio.Comun
  alias Emergencias.Dominio.Codigos

  defstruct [
    :id,
    :tipo,
    :descripcion,
    :cantidad,
    :zona,
    :lugar,
    :prioridad,
    :responsable,
    :estado,
    :creada,
    asignada: 0,
    asignaciones: [],
    historial: []
  ]

  @tipos ~w(agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra)
  @prioridades ~w(critica alta media baja)
  @peso %{"critica" => 4, "alta" => 3, "media" => 2, "baja" => 1}
  @estados ~w(pendiente asignada en_atencion atendida cancelada)
  @transiciones %{
    "pendiente" => ~w(asignada cancelada),
    "asignada" => ~w(en_atencion atendida cancelada),
    "en_atencion" => ~w(atendida),
    "atendida" => [],
    "cancelada" => []
  }

  @doc "Tipos de necesidad válidos."
  def tipos, do: @tipos

  @doc "Prioridades válidas, de la más a la menos urgente."
  def prioridades, do: @prioridades

  @doc "Estados posibles."
  def estados, do: @estados

  @doc """
  Crea una necesidad pendiente validando sus datos. El `id` lo asigna el
  gestor al registrarla (aquí puede ser `nil`).

      Necesidad.crear(nil, "agua", 30, "critica", "centro", "Punto 3", "laura")
  """
  def crear(id, tipo, cantidad, prioridad, zona, descripcion, responsable, lugar \\ nil) do
    with {:ok, tipo} <-
           Comun.en_lista(Codigos.traducir("tipo_necesidad", tipo), @tipos, "Tipo de necesidad"),
         {:ok, cantidad} <- Comun.entero_positivo(cantidad, "La cantidad requerida"),
         {:ok, prioridad} <-
           Comun.en_lista(Codigos.traducir("prioridad", prioridad), @prioridades, "Prioridad"),
         {:ok, zona} <- Comun.codigo(zona, "Zona"),
         {:ok, descripcion} <- Comun.requerido(descripcion, "La descripción") do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         cantidad: cantidad,
         prioridad: prioridad,
         zona: zona,
         lugar: lugar,
         descripcion: descripcion,
         responsable: responsable,
         estado: "pendiente",
         creada: Comun.ahora(),
         historial: [Comun.evento(nil, "pendiente", responsable, "registro")]
       }}
    end
  end

  @doc """
  Lee desde teclado los datos de una necesidad (con `Util2` del curso).
  `usuario` queda como responsable del reporte.
  """
  def ingresar(usuario) do
    Util2.mostrar("\nIngrese los datos de la necesidad:\n", :mensaje)

    crear(
      nil,
      Util2.ingresar("Tipo (#{Codigos.opciones("tipo_necesidad")}): ", :texto),
      Util2.ingresar("Cantidad requerida: ", :entero),
      Util2.ingresar("Prioridad (#{Codigos.opciones("prioridad")}): ", :texto),
      Util2.ingresar("Zona: ", :texto),
      Util2.ingresar("Descripción: ", :texto),
      usuario,
      Comun.opcional(Util2.ingresar("Albergue asociado (vacío si ninguno): ", :texto))
    )
  end

  @doc "Representación de la necesidad como texto."
  def to_string(%__MODULE__{} = n) do
    asignado = if n.asignada > 0, do: " (asignado #{n.asignada})", else: ""
    lugar = if n.lugar, do: " | lugar #{n.lugar}", else: ""

    "#{n.id} | #{String.upcase(n.prioridad)} | #{n.tipo} x#{n.cantidad}#{asignado} | " <>
      "zona #{n.zona}#{lugar} | #{n.estado} | #{n.descripcion} | por #{n.responsable}"
  end

  @doc "Peso de la prioridad: crítica 4, alta 3, media 2, baja 1."
  def peso(%__MODULE__{prioridad: prioridad}), do: Map.fetch!(@peso, prioridad)

  @doc "Cantidad que todavía falta asignar."
  def faltante(%__MODULE__{cantidad: cantidad, asignada: asignada}), do: cantidad - asignada

  @doc "Ordena por prioridad (más urgente primero) y, en empate, por antigüedad."
  def ordenar(necesidades), do: Util2.ordenar(necesidades, :asc, &{-peso(&1), &1.creada, &1.id})

  @doc "Indica si la necesidad puede recibir `cantidad` unidades más."
  def puede_recibir(%__MODULE__{estado: "pendiente"} = necesidad, cantidad) do
    falta = faltante(necesidad)

    if cantidad <= falta,
      do: :ok,
      else: {:error, "La necesidad #{necesidad.id} solo requiere #{falta} unidades más"}
  end

  def puede_recibir(%__MODULE__{estado: "atendida", id: id}, _cantidad),
    do: {:error, "La necesidad #{id} ya fue atendida; no puede volver a consumir recursos"}

  def puede_recibir(%__MODULE__{estado: "cancelada", id: id}, _cantidad),
    do: {:error, "La necesidad #{id} está cancelada; no puede consumir recursos"}

  def puede_recibir(%__MODULE__{estado: estado, id: id}, _cantidad),
    do: {:error, "La necesidad #{id} ya tiene todos sus recursos (estado #{estado})"}

  @doc """
  Registra los recursos tomados del inventario (`partes`). Si con ellos se
  completa la cantidad requerida, la necesidad pasa a `asignada`.
  """
  def registrar_asignacion(%__MODULE__{} = necesidad, partes, usuario) do
    total = Enum.reduce(partes, 0, &(&1["cantidad"] + &2))

    actualizada = %{
      necesidad
      | asignada: necesidad.asignada + total,
        asignaciones: necesidad.asignaciones ++ partes
    }

    if faltante(actualizada) == 0 do
      cambiar_estado(actualizada, "asignada", usuario, "recursos completos")
    else
      {:ok, actualizada}
    end
  end

  @doc "Cambia el estado si la transición es válida y la anota en el historial."
  def cambiar_estado(%__MODULE__{} = necesidad, nuevo, usuario, detalle \\ "") do
    nuevo = Comun.normalizar(nuevo)
    permitidos = Map.fetch!(@transiciones, necesidad.estado)

    cond do
      nuevo not in @estados ->
        {:error, "Estado inválido '#{nuevo}'. Valores permitidos: #{Enum.join(@estados, ", ")}"}

      nuevo in permitidos ->
        evento = Comun.evento(necesidad.estado, nuevo, usuario, detalle)
        {:ok, %{necesidad | estado: nuevo, historial: necesidad.historial ++ [evento]}}

      permitidos == [] ->
        {:error,
         "La necesidad #{necesidad.id} ya está #{necesidad.estado}; no se puede cerrar ni modificar de nuevo"}

      true ->
        {:error,
         "Transición no permitida para #{necesidad.id}: #{necesidad.estado} -> #{nuevo} " <>
           "(desde #{necesidad.estado} puede pasar a: #{Enum.join(permitidos, ", ")})"}
    end
  end

  @doc """
  Indica si la necesidad cumple los filtros (`zona`, `tipo`, `prioridad`,
  `estado`, `lugar`). Un filtro ausente no restringe.
  """
  def cumple?(%__MODULE__{} = necesidad, filtros) do
    Enum.all?(filtros, fn
      {"zona", valor} ->
        necesidad.zona == valor

      {"lugar", valor} ->
        necesidad.lugar == valor

      {"tipo", valor} ->
        necesidad.tipo == Comun.normalizar(Codigos.traducir("tipo_necesidad", valor))

      {"prioridad", valor} ->
        necesidad.prioridad == Comun.normalizar(Codigos.traducir("prioridad", valor))

      {"estado", valor} ->
        necesidad.estado == Comun.normalizar(valor)

      {_otro, _valor} ->
        true
    end)
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
