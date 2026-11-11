defmodule Emergencias.Dominio.Mascota do
  @moduledoc """
  Reporte de una mascota perdida o encontrada.

  Estados: `activa` → `posible_coincidencia` → `resuelta` (final).

  ## Puntaje de similitud (0 a 100)

  Solo se comparan reportes de la **misma especie**, uno perdido y otro encontrado:

  | Atributo         | Puntos                                                |
  |------------------|-------------------------------------------------------|
  | Misma zona       | 30                                                    |
  | Color            | 25 si es igual, 12 si comparten alguna palabra        |
  | Tamaño           | 15 si es igual                                        |
  | Nombre           | 20 si ambos lo conocen y coincide                     |
  | Características  | 5 por cada palabra en común (máximo 10)               |

  Con 50 puntos o más se considera una **posible coincidencia**.
  """

  alias Emergencias.Dominio.Comun
  alias Emergencias.Dominio.Codigos

  defstruct [
    :id,
    :tipo,
    :especie,
    :nombre,
    :color,
    :tamano,
    :caracteristicas,
    :zona,
    :contacto,
    :estado,
    :reportado_por,
    :fecha,
    :coincidencia,
    :resuelta_por,
    :barrio,
    :direccion
  ]

  @tipos %{
    "lost" => "perdida",
    "perdida" => "perdida",
    "found" => "encontrada",
    "encontrada" => "encontrada"
  }
  @tamanos ~w(pequena mediana grande)
  @estados ~w(activa posible_coincidencia resuelta)
  @umbral 50
  @desconocidos ["", "desconocido", "desconocida", "sin_nombre", "-"]

  def estados, do: @estados
  def umbral, do: @umbral

  @doc """
  Crea un reporte activo. Acepta códigos (MT1, ES01, CO01, TA2, B01).
  Especie: ES01 perro, ES02 gato, ES03 otro. Color: CO01 negro, CO02 blanco,
  CO03 café, CO04 gris, CO05 otro. Con "otro" se escribe cuál en `extras`.
  `extras`: especie_otra, color_otro, barrio, direccion.
  """
  def crear(
        id,
        tipo,
        especie,
        nombre,
        color,
        tamano,
        zona,
        contacto,
        caracteristicas,
        usuario,
        extras \\ %{}
      ) do
    with {:ok, tipo} <- validar_tipo(Codigos.traducir("tipo_reporte", tipo)),
         {:ok, especie} <- Comun.requerido(especie, "La especie"),
         {:ok, especie} <- Codigos.con_otro("especie", especie, extras["especie_otra"]),
         {:ok, color} <- Comun.requerido(color, "El color"),
         {:ok, color} <- Codigos.con_otro("color", color, extras["color_otro"]),
         {:ok, tamano} <- Comun.en_lista(Codigos.traducir("tamano", tamano), @tamanos, "Tamaño"),
         {:ok, zona, barrio} <- Codigos.ubicacion(zona, extras["barrio"]),
         {:ok, zona} <- Comun.codigo(zona, "Zona"),
         {:ok, contacto} <- Comun.requerido(contacto, "El contacto") do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         especie: Comun.normalizar(especie),
         nombre: nombre_conocido(nombre),
         color: Comun.normalizar(color),
         tamano: tamano,
         caracteristicas: String.trim(caracteristicas || ""),
         zona: zona,
         contacto: contacto,
         estado: "activa",
         reportado_por: usuario,
         fecha: Comun.ahora(),
         barrio: barrio,
         direccion: Comun.opcional(extras["direccion"])
       }}
    end
  end

  defp validar_tipo(tipo) do
    case Map.fetch(@tipos, Comun.normalizar(tipo)) do
      {:ok, valor} ->
        {:ok, valor}

      :error ->
        {:error,
         "Tipo de reporte inválido '#{tipo}'. Use MT1/perdida/lost o MT2/encontrada/found"}
    end
  end

  @doc """
  Lee desde teclado un reporte de mascota (con `Util2` del curso).
  `usuario` queda como quien la reportó.
  """
  def ingresar(usuario) do
    Util2.mostrar("\nIngrese los datos del reporte de mascota (código o valor):\n", :mensaje)

    tipo = Util2.ingresar("Tipo de reporte (#{Codigos.opciones("tipo_reporte")}): ", :texto)
    especie = Util2.ingresar("Especie (#{Codigos.opciones("especie")}): ", :texto)
    especie_otra = preguntar_otro("especie", especie, "¿Cuál especie? ")
    nombre = Util2.ingresar("Nombre (vacío si no se conoce): ", :texto)
    color = Util2.ingresar("Color (#{Codigos.opciones("color")}): ", :texto)
    color_otro = preguntar_otro("color", color, "¿Cuál color? ")
    tamano = Util2.ingresar("Tamaño (#{Codigos.opciones("tamano")}): ", :texto)
    Util2.mostrar(elem(Codigos.formato_tabla("barrio"), 1), :mensaje)

    barrio =
      Util2.ingresar("Barrio (código B01..., o el nombre de uno nuevo; vacío si no se sabe): ", :texto)

    zona = Util2.ingresar("Zona (vacío = la del barrio; obligatoria si el barrio es nuevo): ", :texto)
    direccion = Util2.ingresar("Dirección o referencia (opcional): ", :texto)
    contacto = Util2.ingresar("Contacto: ", :texto)
    caracteristicas = Util2.ingresar("Características: ", :texto)

    crear(nil, tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas, usuario, %{
      "especie_otra" => especie_otra,
      "color_otro" => color_otro,
      "barrio" => barrio,
      "direccion" => direccion
    })
  end

  # Si se eligió "otro" (ES03 o CO05), pregunta cuál.
  defp preguntar_otro(tabla, entrada, pregunta) do
    if Comun.normalizar(Codigos.traducir(tabla, entrada)) == "otro",
      do: Util2.ingresar(pregunta, :texto),
      else: nil
  end

  @doc "Representación del reporte como texto."
  def to_string(%__MODULE__{} = m) do
    caracteristicas = if m.caracteristicas in [nil, ""], do: "", else: " | #{m.caracteristicas}"
    pareja = if m.coincidencia, do: " (con #{m.coincidencia})", else: ""

    "#{m.id} | #{m.tipo} | #{m.especie} | #{m.nombre || "sin nombre"} | #{m.color} | #{m.tamano} | " <>
      "zona #{m.zona}#{lugar(m)} | contacto #{m.contacto}#{caracteristicas} | #{m.estado}#{pareja}"
  end

  defp lugar(m) do
    barrio = if m.barrio, do: " barrio #{Codigos.nombre_barrio(m.barrio)}", else: ""
    direccion = if m.direccion, do: " (#{m.direccion})", else: ""
    barrio <> direccion
  end

  defp nombre_conocido(nombre) do
    limpio = String.trim(nombre || "")
    if Comun.normalizar(limpio) in @desconocidos, do: nil, else: limpio
  end

  @doc """
  Puntaje de similitud entre un reporte perdido y uno encontrado.
  Retorna `{puntaje, razones}`.
  """
  def puntaje(%__MODULE__{} = perdida, %__MODULE__{} = encontrada) do
    if perdida.especie != encontrada.especie do
      {0, ["especie distinta"]}
    else
      [
        criterio(perdida.zona == encontrada.zona, 30, "misma zona"),
        puntos_color(perdida.color, encontrada.color),
        criterio(perdida.tamano == encontrada.tamano, 15, "mismo tamaño"),
        puntos_nombre(perdida.nombre, encontrada.nombre),
        puntos_caracteristicas(perdida.caracteristicas, encontrada.caracteristicas)
      ]
      |> Enum.reduce({0, ["misma especie"]}, fn {puntos, razon}, {total, razones} ->
        {total + puntos, if(razon, do: razones ++ [razon], else: razones)}
      end)
    end
  end

  defp criterio(true, puntos, razon), do: {puntos, razon}
  defp criterio(false, _puntos, _razon), do: {0, nil}

  defp puntos_color(igual, igual), do: {25, "mismo color"}

  defp puntos_color(a, b) do
    if comunes(Comun.palabras(a), Comun.palabras(b)) > 0,
      do: {12, "color parecido"},
      else: {0, nil}
  end

  defp puntos_nombre(nil, _otro), do: {0, nil}
  defp puntos_nombre(_uno, nil), do: {0, nil}

  defp puntos_nombre(a, b),
    do: criterio(Comun.normalizar(a) == Comun.normalizar(b), 20, "mismo nombre")

  defp puntos_caracteristicas(a, b) do
    case comunes(Enum.uniq(Comun.palabras(a)), Enum.uniq(Comun.palabras(b))) do
      0 -> {0, nil}
      n -> {min(n * 5, 10), "#{n} característica(s) en común"}
    end
  end

  @doc "**Recursiva.** Cuenta cuántas palabras de la primera lista están en la segunda."
  def comunes([], _otras), do: 0

  def comunes([palabra | resto], otras),
    do: if(palabra in otras, do: 1, else: 0) + comunes(resto, otras)

  @doc "Indica si el reporte sigue abierto (se puede emparejar)."
  def abierta?(%__MODULE__{estado: estado}), do: estado != "resuelta"

  @doc "Filtros: `especie`, `zona`, `estado`, `tipo`."
  def cumple?(%__MODULE__{} = mascota, filtros) do
    Enum.all?(filtros, fn
      {"especie", valor} ->
        case Comun.normalizar(Codigos.traducir("especie", valor)) do
          # ES03 = otro: todas las que no son perro ni gato
          "otro" -> mascota.especie not in ["perro", "gato"]
          especie -> mascota.especie == especie
        end

      {"zona", valor} ->
        mascota.zona == valor

      {"barrio", valor} ->
        mascota.barrio == String.upcase(valor)

      {"estado", valor} ->
        mascota.estado == Comun.normalizar(valor)

      {"tipo", valor} ->
        mascota.tipo == tipo_filtro(valor)

      {_otro, _valor} ->
        true
    end)
  end

  defp tipo_filtro(valor) do
    valor = Comun.normalizar(Codigos.traducir("tipo_reporte", valor))
    Map.get(@tipos, valor, valor)
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
