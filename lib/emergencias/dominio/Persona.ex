defmodule Emergencias.Dominio.Persona do
  @moduledoc """
  Persona afectada, para ayudar a que sus familiares la localicen.

  Estados: sin_informacion, reportada, localizada, trasladada, en_albergue y
  reunificada. `reunificada` es final. Cada cambio de estado queda en el
  historial con fecha, usuario y detalle.
  """

  alias Emergencias.Dominio.Comun
  alias Emergencias.Anexos.Codigos

  defstruct [
    :id,
    :documento,
    :nombre,
    :edad,
    :zona,
    :estado,
    :albergue,
    :registrada_por,
    :creada,
    :tipo_documento,
    :barrio,
    :direccion,
    historial: []
  ]

  @estados ~w(sin_informacion reportada localizada trasladada en_albergue reunificada)
  @transiciones %{
    "sin_informacion" => ~w(reportada localizada trasladada en_albergue reunificada),
    "reportada" => ~w(localizada trasladada en_albergue reunificada),
    "localizada" => ~w(trasladada en_albergue reunificada),
    "trasladada" => ~w(localizada en_albergue reunificada),
    "en_albergue" => ~w(localizada trasladada reunificada),
    "reunificada" => []
  }

  def estados, do: @estados

  @doc "Crea el registro de una persona. Acepta códigos (PE3, B01). `extras`: tipo_doc, barrio, direccion."
  def crear(id, documento, nombre, zona, estado, edad, usuario, extras \\ %{}) do
    with {:ok, documento} <- Comun.codigo(documento, "Documento o dato de referencia"),
         {:ok, nombre} <- Comun.requerido(nombre, "El nombre"),
         {:ok, zona, barrio} <- Codigos.ubicacion(zona, extras["barrio"]),
         {:ok, zona} <- Comun.codigo(zona, "Zona"),
         {:ok, estado} <-
           Comun.en_lista(
             Codigos.traducir("estado_persona", estado),
             @estados,
             "Estado de la persona"
           ),
         {:ok, tipo_documento} <- validar_tipo_documento(extras["tipo_doc"]),
         {:ok, edad} <- validar_edad(edad) do
      {:ok,
       %__MODULE__{
         id: id,
         documento: documento,
         nombre: nombre,
         zona: zona,
         estado: estado,
         edad: edad,
         registrada_por: usuario,
         creada: Comun.ahora(),
         tipo_documento: tipo_documento,
         barrio: barrio,
         direccion: Comun.opcional(extras["direccion"]),
         historial: [Comun.evento(nil, estado, usuario, "registro")]
       }}
    end
  end

  # Tipo de documento opcional (CC, TI...).
  defp validar_tipo_documento(entrada) do
    case Comun.opcional(entrada) do
      nil ->
        {:ok, nil}

      texto ->
        validos = Enum.map(Codigos.filas("tipo_doc"), & &1.valor)
        Comun.en_lista(Codigos.traducir("tipo_doc", texto), validos, "Tipo de documento")
    end
  end

  defp validar_edad(nil), do: {:ok, nil}
  defp validar_edad(""), do: {:ok, nil}

  defp validar_edad(edad) do
    case Comun.entero_no_negativo(edad, "La edad") do
      {:ok, n} when n <= 130 -> {:ok, n}
      {:ok, n} -> {:error, "La edad #{n} no es válida"}
      error -> error
    end
  end

  @doc """
  Lee desde teclado los datos de una persona afectada (con `Util2` del curso).
  `usuario` queda como quien la registró.
  """
  def ingresar(usuario) do
    Util2.mostrar("\nIngrese los datos de la persona afectada (código o valor):\n", :mensaje)

    tipo_doc = Util2.ingresar("Tipo de documento (#{Codigos.opciones("tipo_doc")}): ", :texto)
    documento = Util2.ingresar("Número de documento o dato de referencia: ", :texto)
    nombre = Util2.ingresar("Nombre: ", :texto)
    edad = Comun.opcional(Util2.ingresar("Edad (vacío si no se sabe): ", :texto))
    Util2.mostrar(elem(Codigos.formato_tabla("barrio"), 1), :mensaje)
    barrio =
      Util2.ingresar("Barrio (código B01..., o el nombre de uno nuevo; vacío si no se sabe): ", :texto)

    zona = Util2.ingresar("Zona (vacío = la del barrio; obligatoria si el barrio es nuevo): ", :texto)
    direccion = Util2.ingresar("Dirección o referencia (opcional): ", :texto)
    Util2.mostrar(elem(Codigos.formato_tabla("estado_persona"), 1), :mensaje)
    estado = Util2.ingresar("Estado (código o valor): ", :texto)

    crear(nil, documento, nombre, zona, estado, edad, usuario, %{
      "tipo_doc" => tipo_doc,
      "barrio" => barrio,
      "direccion" => direccion
    })
  end

  @doc "Representación de la persona como texto."
  def to_string(%__MODULE__{} = p) do
    edad = if p.edad, do: "#{p.edad} años", else: "edad sin dato"
    albergue = if p.albergue, do: " (albergue #{p.albergue})", else: ""
    tipo_doc = if p.tipo_documento, do: "#{p.tipo_documento} ", else: ""
    barrio = if p.barrio, do: " barrio #{Codigos.nombre_barrio(p.barrio)}", else: ""
    direccion = if p.direccion, do: " (#{p.direccion})", else: ""

    "#{p.id} | doc #{tipo_doc}#{p.documento} | #{p.nombre} | #{edad} | " <>
      "zona #{p.zona}#{barrio}#{direccion} | #{p.estado}#{albergue}"
  end

  @doc "Valida que la persona pueda pasar al estado `nuevo`."
  def validar_transicion(%__MODULE__{} = persona, nuevo) do
    nuevo = Comun.normalizar(Codigos.traducir("estado_persona", nuevo))
    permitidos = Map.fetch!(@transiciones, persona.estado)

    cond do
      nuevo not in @estados ->
        {:error, "Estado inválido '#{nuevo}'. Valores permitidos: #{Enum.join(@estados, ", ")}"}

      nuevo == persona.estado ->
        {:error, "#{persona.nombre} ya está en estado #{nuevo}"}

      nuevo in permitidos ->
        {:ok, nuevo}

      true ->
        {:error,
         "Transición no permitida para #{persona.nombre}: #{persona.estado} -> #{nuevo}" <>
           if(permitidos == [], do: " (es un estado final)", else: "")}
    end
  end

  @doc "Cambia el estado y lo anota en el historial. `cambios` permite actualizar otros campos."
  def cambiar_estado(%__MODULE__{} = persona, nuevo, usuario, detalle \\ "", cambios \\ %{}) do
    with {:ok, nuevo} <- validar_transicion(persona, nuevo) do
      evento = Comun.evento(persona.estado, nuevo, usuario, detalle)

      {:ok,
       persona
       |> Map.merge(cambios)
       |> Map.merge(%{estado: nuevo, historial: persona.historial ++ [evento]})}
    end
  end

  @doc "Filtros de búsqueda: `nombre` (contiene), `documento`, `zona`, `estado` (código o valor), `barrio`."
  def cumple?(%__MODULE__{} = persona, filtros) do
    Enum.all?(filtros, fn
      {"nombre", valor} ->
        String.contains?(Comun.normalizar(persona.nombre), Comun.normalizar(valor))

      {"documento", valor} ->
        persona.documento == valor

      {"zona", valor} ->
        persona.zona == valor

      {"estado", valor} ->
        persona.estado == Comun.normalizar(Codigos.traducir("estado_persona", valor))

      {"barrio", valor} ->
        persona.barrio == String.upcase(valor)

      {_otro, _valor} ->
        true
    end)
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
