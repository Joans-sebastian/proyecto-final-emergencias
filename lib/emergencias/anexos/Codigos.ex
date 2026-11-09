defmodule Emergencias.Anexos.Codigos do
  @moduledoc """
  **Base de datos de códigos** del sistema: tablas `código → valor` para
  escribir los registros de forma corta y sin errores de ortografía.

  En lugar de escribir `perro` se puede escribir `ES01`; en lugar de
  `localizada`, `PE3`. Los dos caminos funcionan: si lo escrito es un código
  se traduce a su valor y, si no, se deja igual para que la entidad lo valide
  como siempre. Los registros guardan el **valor** (no el código), así los
  datos anteriores siguen sirviendo.

  ## Pensamiento computacional

  - **Abstracción:** cada tabla es solo `{código, valor, descripción}`; no
    importa si es una especie, un color o un estado.
  - **Descomposición:** una función para cada tarea pequeña (buscar, traducir,
    ubicar, dibujar la tabla, exportar).
  - **Reconocimiento de patrones:** la misma función `traducir/2` sirve para
    todas las tablas y la misma `formato_tabla/1` dibuja cualquiera.
  - **Algoritmos:** `buscar/2` y `ancho_columnas/2` son **recursivas**.

  ## Uso

      iex> Emergencias.Anexos.Codigos.traducir("especie", "es01")
      "perro"
      iex> Emergencias.Anexos.Codigos.traducir("especie", "gato")
      "gato"
      iex> Emergencias.Anexos.Codigos.ubicacion("", "B01")
      {:ok, "centro", "B01"}

  En la consola: `codigos` (lista de tablas) o `codigos especie` (una tabla).
  Para estudiarlas: `elixir codigos.exs` genera `CODIGOS.md` y `datos/codigos.csv`.
  """

  alias Emergencias.Dominio.Comun

  # ---------------------------------------------------------------------------
  # Datos: cada tabla es {nombre, título, dónde se usa, filas}
  # Cada fila es {código, valor, descripción}. En barrios, la descripción es
  # la zona a la que pertenece y se agrega la ciudad.
  # ---------------------------------------------------------------------------

  @tablas [
    {"tipo_reporte", "Tipo de reporte de mascota", "reportar_mascota (1.er dato)",
     [
       {"MT1", "perdida", "La mascota se perdió (la busca su familia)"},
       {"MT2", "encontrada", "Alguien encontró una mascota"}
     ]},
    {"especie", "Especie de la mascota", "reportar_mascota (2.º dato) y filtro especie=",
     [
       {"ES01", "perro", "Canino"},
       {"ES02", "gato", "Felino"},
       {"ES03", "ave", "Loro, perico, canario, gallina"},
       {"ES04", "conejo", "Conejo"},
       {"ES05", "roedor", "Hámster, cuy, ratón"},
       {"ES06", "tortuga", "Tortuga"},
       {"ES07", "caballo", "Caballo, burro, mula"},
       {"ES08", "otra", "Otra especie"}
     ]},
    {"color", "Color de la mascota", "reportar_mascota (4.º dato)",
     [
       {"CO01", "negro", "Pelaje negro"},
       {"CO02", "blanco", "Pelaje blanco"},
       {"CO03", "cafe", "Café o marrón"},
       {"CO04", "gris", "Gris"},
       {"CO05", "amarillo", "Amarillo, dorado o crema"},
       {"CO06", "naranja", "Naranja o rojizo"},
       {"CO07", "blanco negro", "Manchas blancas y negras"},
       {"CO08", "blanco cafe", "Manchas blancas y cafés"},
       {"CO09", "atigrado", "Rayas tipo tigre"},
       {"CO10", "tricolor", "Tres colores"}
     ]},
    {"tamano", "Tamaño de la mascota", "reportar_mascota (5.º dato)",
     [
       {"TA1", "pequena", "Menos de 10 kg"},
       {"TA2", "mediana", "Entre 10 y 25 kg"},
       {"TA3", "grande", "Más de 25 kg"}
     ]},
    {"estado_persona", "Estado de una persona afectada",
     "reportar_persona (4.º dato), actualizar_persona y filtro estado=",
     [
       {"PE1", "sin_informacion", "No se sabe nada de la persona"},
       {"PE2", "reportada", "Un familiar reportó que la busca"},
       {"PE3", "localizada", "Se sabe dónde está"},
       {"PE4", "trasladada", "Fue llevada a otro lugar (hospital, otra ciudad)"},
       {"PE5", "en_albergue", "Está en un albergue"},
       {"PE6", "reunificada", "Se reunió con su familia (estado final)"}
     ]},
    {"tipo_doc", "Tipo de documento de la persona", "reportar_persona [tipo_doc=..]",
     [
       {"CC", "cedula", "Cédula de ciudadanía"},
       {"TI", "tarjeta_identidad", "Tarjeta de identidad (menores)"},
       {"RC", "registro_civil", "Registro civil (niños)"},
       {"CE", "cedula_extranjeria", "Cédula de extranjería"},
       {"PA", "pasaporte", "Pasaporte"},
       {"SD", "sin_documento", "No tiene o no se conoce (use un dato de referencia)"}
     ]},
    {"barrio", "Barrios y su zona", "reportar_mascota / reportar_persona [barrio=..]",
     [
       {"B01", "Centro", "centro", "Armenia"},
       {"B02", "Granada", "centro", "Armenia"},
       {"B03", "La Clarita", "centro", "Armenia"},
       {"B04", "Los Quindos", "sur", "Armenia"},
       {"B05", "La Patria", "sur", "Armenia"},
       {"B06", "Puerto Espejo", "sur", "Armenia"},
       {"B07", "La Castellana", "norte", "Armenia"},
       {"B08", "Laureles", "norte", "Armenia"},
       {"B09", "El Bosque", "este", "Armenia"},
       {"B10", "Galán", "oeste", "Armenia"},
       {"B11", "Centro Calarcá", "este", "Calarcá"},
       {"B12", "Centro Circasia", "norte", "Circasia"}
     ]},
    {"tipo_necesidad", "Tipo de necesidad", "registrar_necesidad (1.er dato) y filtro tipo=",
     [
       {"NT01", "agua", "Agua potable (litros o botellas)"},
       {"NT02", "alimentos", "Mercados, raciones"},
       {"NT03", "medicamentos", "Medicinas"},
       {"NT04", "primeros_auxilios", "Botiquines, curaciones"},
       {"NT05", "refugio", "Carpas, cobijas, colchonetas"},
       {"NT06", "transporte", "Vehículos para trasladar personas o carga"},
       {"NT07", "rescate", "Personas atrapadas"},
       {"NT08", "otra", "Otra necesidad"}
     ]},
    {"prioridad", "Prioridad de una necesidad",
     "registrar_necesidad (3.er dato) y filtro prioridad=",
     [
       {"PR1", "critica", "Riesgo para la vida, atender ya"},
       {"PR2", "alta", "Atender en pocas horas"},
       {"PR3", "media", "Atender en el día"},
       {"PR4", "baja", "Puede esperar"}
     ]},
    {"nivel", "Nivel de afectación de una zona",
     "registrar_zona (3.er dato) y actualizar_zona nivel=",
     [
       {"NV1", "critico", "Daños graves, muchas personas afectadas"},
       {"NV2", "alto", "Daños importantes"},
       {"NV3", "medio", "Daños moderados"},
       {"NV4", "bajo", "Daños leves"}
     ]},
    {"rol", "Rol del usuario", "conectar / registrar_usuario (tipo)",
     [
       {"RO1", "ciudadano", "Reporta y consulta"},
       {"RO2", "voluntario", "Atiende necesidades y albergues"},
       {"RO3", "coordinador", "Registra zonas, recursos y asigna"},
       {"RO4", "administrador", "Todo, incluso usuarios"}
     ]}
  ]

  @nombres Enum.map(@tablas, fn {nombre, _t, _u, _f} -> nombre end)

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  @doc "Nombres de todas las tablas."
  def nombres, do: @nombres

  @doc "Filas de una tabla como mapas `%{codigo, valor, descripcion}` (barrio: `zona` y `ciudad`)."
  def filas(nombre) do
    case List.keyfind(@tablas, nombre, 0) do
      {_n, _t, _u, filas} -> Enum.map(filas, &fila_a_mapa/1)
      nil -> []
    end
  end

  defp fila_a_mapa({codigo, valor, zona, ciudad}),
    do: %{codigo: codigo, valor: valor, descripcion: "zona #{zona}", zona: zona, ciudad: ciudad}

  defp fila_a_mapa({codigo, valor, descripcion}),
    do: %{codigo: codigo, valor: valor, descripcion: descripcion}

  @doc """
  **Recursiva.** Busca un código (sin importar mayúsculas) en una lista de filas.

      iex> Emergencias.Anexos.Codigos.buscar(Emergencias.Anexos.Codigos.filas("tamano"), "ta2").valor
      "mediana"
  """
  def buscar([], _codigo), do: nil

  def buscar([fila | resto], codigo) do
    if fila.codigo == mayusculas(codigo), do: fila, else: buscar(resto, codigo)
  end

  @doc """
  Si `entrada` es un código de la tabla retorna su valor; si no, la deja igual
  (así se puede escribir el código **o** el valor).
  """
  def traducir(_tabla, nil), do: nil

  def traducir(tabla, entrada) do
    case buscar(filas(tabla), entrada) do
      nil -> entrada
      fila -> fila.valor
    end
  end

  @doc """
  Barrio opcional: vacío → `{:ok, nil}`; código válido → `{:ok, código}`.

      iex> Emergencias.Anexos.Codigos.barrio("b07")
      {:ok, "B07"}
  """
  def barrio(entrada) do
    case Comun.opcional(entrada) do
      nil ->
        {:ok, nil}

      texto ->
        case buscar(filas("barrio"), texto) do
          nil ->
            {:error,
             "Barrio inválido '#{texto}'. Códigos: #{Enum.map_join(filas("barrio"), ", ", & &1.codigo)} " <>
               "(escriba: codigos barrio)"}

          fila ->
            {:ok, fila.codigo}
        end
    end
  end

  @doc """
  Decide la zona y el barrio de un registro:

  - Si en la zona se escribió un código de barrio (`B04`), se usa la zona de ese barrio.
  - Si la zona está vacía y hay barrio, se toma la zona del barrio.
  - Si no, la zona queda como se escribió (puede ser un sector o un punto).

      iex> Emergencias.Anexos.Codigos.ubicacion("B04", nil)
      {:ok, "sur", "B04"}
      iex> Emergencias.Anexos.Codigos.ubicacion("sector3", "B02")
      {:ok, "sector3", "B02"}
  """
  def ubicacion(zona, barrio_entrada) do
    zona = Comun.opcional(zona)
    barrio_en_zona = zona && buscar(filas("barrio"), zona)

    with {:ok, barrio} <- barrio(barrio_entrada) do
      cond do
        barrio_en_zona -> {:ok, barrio_en_zona.zona, barrio || barrio_en_zona.codigo}
        zona -> {:ok, zona, barrio}
        barrio -> {:ok, buscar(filas("barrio"), barrio).zona, barrio}
        true -> {:ok, "", nil}
      end
    end
  end

  @doc "Nombre legible de un barrio: `B02` → `Granada (Armenia)`."
  def nombre_barrio(nil), do: nil

  def nombre_barrio(codigo) do
    case buscar(filas("barrio"), codigo) do
      nil -> codigo
      fila -> "#{fila.valor} (#{fila.ciudad})"
    end
  end

  @doc """
  Opciones cortas para las preguntas de `ingresar`:

      iex> Emergencias.Anexos.Codigos.opciones("tamano")
      "TA1=pequena, TA2=mediana, TA3=grande"
  """
  def opciones(tabla), do: Enum.map_join(filas(tabla), ", ", &"#{&1.codigo}=#{&1.valor}")

  @doc """
  Opciones para las listas de la web y de las ventanas: `{código, etiqueta}`.
  La etiqueta lleva el código, una raya `–` y el valor.

      iex> Emergencias.Anexos.Codigos.etiquetas("tamano") |> hd()
      {"TA1", "TA1 – pequena"}
      iex> Emergencias.Anexos.Codigos.etiquetas("barrio") |> hd()
      {"B01", "B01 – Centro (zona centro, Armenia)"}
  """
  def etiquetas("barrio"),
    do:
      Enum.map(filas("barrio"), fn f ->
        {f.codigo, "#{f.codigo} – #{f.valor} (zona #{f.zona}, #{f.ciudad})"}
      end)

  def etiquetas(tabla), do: Enum.map(filas(tabla), &{&1.codigo, "#{&1.codigo} – #{&1.valor}"})

  # ---------------------------------------------------------------------------
  # Presentación (tablas de texto)
  # ---------------------------------------------------------------------------

  @doc "Índice de tablas para el comando `codigos`."
  def indice do
    lineas =
      Enum.map(@tablas, fn {nombre, titulo, uso, filas} ->
        "  #{String.pad_trailing(nombre, 15)} #{String.pad_trailing(titulo, 34)} " <>
          "#{length(filas)} códigos | se usa en: #{uso}"
      end)

    Enum.join(
      ["BASE DE DATOS DE CÓDIGOS (escriba: codigos <tabla>, o codigos todas)" | lineas] ++
        [
          "",
          "Puede escribir el código o el valor. Ejemplo:",
          "  reportar_mascota MT1 ES01 Luna CO01 TA2 B07 3001112233 caracteristicas=\"collar rojo\""
        ],
      "\n"
    )
  end

  @doc "Una tabla dibujada con bordes, lista para la consola."
  def formato_tabla(nombre) do
    case List.keyfind(@tablas, nombre, 0) do
      nil ->
        {:error, "Tabla desconocida '#{nombre}'. Tablas: #{Enum.join(@nombres, ", ")}"}

      {_n, titulo, uso, _f} ->
        {encabezado, filas} = columnas(nombre)
        {:ok, "#{titulo} (#{nombre}) — se usa en: #{uso}\n" <> dibujar(encabezado, filas)}
    end
  end

  @doc "Todas las tablas, una tras otra."
  def formato_todas do
    Enum.map_join(@nombres, "\n\n", fn nombre -> elem(formato_tabla(nombre), 1) end)
  end

  defp columnas("barrio"),
    do:
      {["Código", "Barrio", "Zona", "Ciudad"],
       Enum.map(filas("barrio"), &[&1.codigo, &1.valor, &1.zona, &1.ciudad])}

  defp columnas(nombre),
    do:
      {["Código", "Valor", "Descripción"],
       Enum.map(filas(nombre), &[&1.codigo, &1.valor, &1.descripcion])}

  defp dibujar(encabezado, filas) do
    anchos = ancho_columnas([encabezado | filas], Enum.map(encabezado, fn _ -> 0 end))
    borde = "+" <> Enum.map_join(anchos, "+", &String.duplicate("-", &1 + 2)) <> "+"

    linea = fn celdas ->
      "| " <>
        (Enum.zip(celdas, anchos)
         |> Enum.map_join(" | ", fn {celda, ancho} -> String.pad_trailing(celda, ancho) end)) <>
        " |"
    end

    Enum.join([borde, linea.(encabezado), borde] ++ Enum.map(filas, linea) ++ [borde], "\n")
  end

  @doc "**Recursiva.** Ancho máximo de cada columna recorriendo las filas."
  def ancho_columnas([], anchos), do: anchos

  def ancho_columnas([fila | resto], anchos) do
    nuevos = Enum.zip_with(fila, anchos, fn celda, ancho -> max(String.length(celda), ancho) end)
    ancho_columnas(resto, nuevos)
  end

  # ---------------------------------------------------------------------------
  # Exportar (para estudiar las tablas fuera del programa)
  # ---------------------------------------------------------------------------

  @doc "Todas las tablas en Markdown (para `CODIGOS.md`)."
  def markdown do
    secciones =
      Enum.map(@tablas, fn {nombre, titulo, uso, _f} ->
        {encabezado, filas} = columnas(nombre)

        tabla =
          Enum.map_join(
            [encabezado, Enum.map(encabezado, fn _ -> "---" end) | filas],
            "\n",
            fn c ->
              "| " <> Enum.join(c, " | ") <> " |"
            end
          )

        "## #{titulo} (`#{nombre}`)\n\nSe usa en: #{uso}\n\n" <> tabla
      end)

    Enum.join(
      [
        "# Base de datos de códigos\n\n" <>
          "Generado con `elixir codigos.exs` desde `lib/emergencias/anexos/Codigos.ex`.\n" <>
          "En cada registro puede escribir el **código** o el **valor**; se guarda el valor.\n\n" <>
          "Ejemplos:\n\n" <>
          "```\n" <>
          "reportar_mascota MT1 ES01 Luna CO01 TA2 B07 3001112233 caracteristicas=\"collar rojo\"\n" <>
          "reportar_persona 1094 \"Andrés López\" B04 PE3 edad=34 tipo_doc=CC\n" <>
          "registrar_necesidad NT01 30 PR1 centro \"Punto de atención sector 3\"\n" <>
          "listar_mascotas especie=ES01\n" <>
          "```"
        | secciones
      ],
      "\n\n"
    ) <> "\n"
  end

  @doc "Todas las tablas en CSV (`tabla;codigo;valor;descripcion`), para abrir en Excel."
  def csv do
    lineas =
      Enum.flat_map(@nombres, fn nombre ->
        Enum.map(filas(nombre), fn f ->
          detalle =
            if nombre == "barrio", do: "#{f.descripcion} - #{f.ciudad}", else: f.descripcion

          Enum.join([nombre, f.codigo, f.valor, detalle], ";")
        end)
      end)

    Enum.join(["tabla;codigo;valor;descripcion" | lineas], "\n") <> "\n"
  end

  defp mayusculas(texto), do: texto |> to_string() |> String.trim() |> String.upcase()
end
