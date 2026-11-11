defmodule Emergencias.Anexos.Codigos do
  @moduledoc """
  Tablas de códigos para registrar más rápido: se puede escribir `ES01` o `perro`.
  Se guarda siempre el valor.

  Especie y color solo aceptan sus códigos. Con "otro" (`ES03`, `CO05`) se
  escribe cuál es en `especie_otra=` o `color_otro=`. Los barrios no están
  aquí: se registran a mano (`Emergencias.Anexos.Barrios`) y reciben B01, B02...

      iex> Emergencias.Anexos.Codigos.traducir("especie", "es01")
      "perro"
  """

  alias Emergencias.Anexos.Barrios
  alias Emergencias.Dominio.Comun

  # Cada tabla: {nombre, título, dónde se usa, filas}. Fila: {código, valor, descripción}.
  # La tabla de barrios se arma con los barrios registrados (ver tablas/0).

  @tablas [
    {"tipo_reporte", "Tipo de reporte de mascota", "reportar_mascota (1.er dato)",
     [
       {"MT1", "perdida", "La mascota se perdió (la busca su familia)"},
       {"MT2", "encontrada", "Alguien encontró una mascota"}
     ]},
    {"especie", "Especie de la mascota", "reportar_mascota (2.º dato) y filtro especie=",
     [
       {"ES01", "perro", "Perro"},
       {"ES02", "gato", "Gato"},
       {"ES03", "otro", "Otra especie: escriba cuál en especie_otra="}
     ]},
    {"color", "Color de la mascota", "reportar_mascota (4.º dato)",
     [
       {"CO01", "negro", "Negro"},
       {"CO02", "blanco", "Blanco"},
       {"CO03", "cafe", "Café"},
       {"CO04", "gris", "Gris"},
       {"CO05", "otro", "Otro color: escriba cuál en color_otro="}
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

  # Campo opcional donde se escribe el valor cuando se elige "otro".
  @campo_otro %{"especie" => "especie_otra", "color" => "color_otro"}
  @texto_otro %{"especie" => "otra especie", "color" => "otro color"}

  # Todas las tablas: las fijas y la de barrios registrados (cambia al registrar uno).
  defp tablas do
    barrios =
      Enum.map(Barrios.listar(), fn b -> {b.codigo, b.nombre, b.zona, :barrio} end)

    @tablas ++
      [
        {"barrio", "Barrios registrados y su zona",
         "registrar_barrio, reportar_mascota / reportar_persona [barrio=..]", barrios}
      ]
  end

  @doc "Nombres de todas las tablas."
  def nombres, do: Enum.map(tablas(), fn {nombre, _t, _u, _f} -> nombre end)

  @doc "Filas de una tabla como mapas."
  def filas(nombre) do
    case List.keyfind(tablas(), nombre, 0) do
      {_n, _t, _u, filas} -> Enum.map(filas, &fila_a_mapa/1)
      nil -> []
    end
  end

  defp fila_a_mapa({codigo, nombre, zona, :barrio}),
    do: %{codigo: codigo, valor: nombre, descripcion: "zona #{zona}", zona: zona}

  defp fila_a_mapa({codigo, valor, descripcion}),
    do: %{codigo: codigo, valor: valor, descripcion: descripcion}

  @doc """
  Especie y color: solo se aceptan los códigos de la tabla (o su valor). Si se
  elige "otro" (`ES03` o `CO05`), se guarda lo que se escribió en `otro`.

      iex> Emergencias.Anexos.Codigos.con_otro("especie", "ES01", nil)
      {:ok, "perro"}
      iex> Emergencias.Anexos.Codigos.con_otro("especie", "es03", "Iguana")
      {:ok, "iguana"}
      iex> Emergencias.Anexos.Codigos.con_otro("color", "CO05", "")
      {:error, "Eligió CO05 (otro color): escriba cuál en color_otro=.."}
  """
  def con_otro(tabla, entrada, otro) do
    valor = Comun.normalizar(traducir(tabla, entrada))
    validos = Enum.map(filas(tabla), & &1.valor)

    cond do
      valor == "otro" ->
        case Comun.opcional(otro) do
          nil ->
            codigo = Enum.find(filas(tabla), &(&1.valor == "otro")).codigo

            {:error,
             "Eligió #{codigo} (#{@texto_otro[tabla]}): escriba cuál en #{@campo_otro[tabla]}=.."}

          texto ->
            {:ok, Comun.normalizar(texto)}
        end

      valor in validos ->
        {:ok, valor}

      true ->
        {:error, "#{String.capitalize(tabla)} no válida: '#{entrada}'. Use: #{opciones(tabla)}"}
    end
  end

  @doc """
  Recursiva. Busca un código en las filas (sin importar mayúsculas).

      iex> Emergencias.Anexos.Codigos.buscar(Emergencias.Anexos.Codigos.filas("tamano"), "ta2").valor
      "mediana"
  """
  def buscar([], _codigo), do: nil

  def buscar([fila | resto], codigo) do
    if fila.codigo == mayusculas(codigo), do: fila, else: buscar(resto, codigo)
  end

  @doc "Si es un código retorna su valor; si no, lo deja igual."
  def traducir(_tabla, nil), do: nil

  def traducir(tabla, entrada) do
    case buscar(filas(tabla), entrada) do
      nil -> entrada
      fila -> fila.valor
    end
  end

  @doc """
  Valida el barrio (opcional). Acepta un código registrado (`B01`) o el nombre
  de un barrio nuevo: si es nuevo, lo registra con `zona` y le da el siguiente
  código (B01, B02...).

      iex> Emergencias.Anexos.Codigos.barrio(nil, "centro")
      {:ok, nil}
  """
  def barrio(entrada, zona) do
    case Comun.opcional(entrada) do
      nil ->
        {:ok, nil}

      texto ->
        cond do
          fila = buscar(filas("barrio"), texto) ->
            {:ok, fila.codigo}

          Regex.match?(~r/^B\d+$/i, texto) ->
            {:error,
             "El barrio #{String.upcase(texto)} no está registrado. Registrados: #{registrados()} " <>
               "(para uno nuevo: registrar_barrio \"nombre\" zona)"}

          Comun.opcional(zona) == nil ->
            {:error, "Barrio nuevo '#{texto}': escriba también la zona para registrarlo"}

          true ->
            with {:ok, b, _} <- Barrios.registrar(texto, zona), do: {:ok, b.codigo}
        end
    end
  end

  defp registrados do
    case filas("barrio") do
      [] -> "ninguno"
      lista -> Enum.map_join(lista, ", ", & &1.codigo)
    end
  end

  @doc """
  Retorna la zona y el barrio. Si hay barrio y no zona, usa la zona del barrio.
  En la zona también se puede escribir el código de un barrio (`B01`).

      iex> Emergencias.Anexos.Codigos.ubicacion("sector3", nil)
      {:ok, "sector3", nil}
  """
  def ubicacion(zona, barrio_entrada) do
    zona = Comun.opcional(zona)
    barrio_en_zona = zona && buscar(filas("barrio"), zona)

    cond do
      barrio_en_zona ->
        with {:ok, barrio} <- barrio(barrio_entrada, barrio_en_zona.zona),
             do: {:ok, barrio_en_zona.zona, barrio || barrio_en_zona.codigo}

      true ->
        with {:ok, barrio} <- barrio(barrio_entrada, zona) do
          cond do
            zona -> {:ok, zona, barrio}
            barrio -> {:ok, buscar(filas("barrio"), barrio).zona, barrio}
            true -> {:ok, "", nil}
          end
        end
    end
  end

  @doc "B01 -> La Castellana (zona norte)."
  def nombre_barrio(nil), do: nil

  def nombre_barrio(codigo) do
    case buscar(filas("barrio"), codigo) do
      nil -> codigo
      fila -> "#{fila.valor} (zona #{fila.zona})"
    end
  end

  @doc """
  Códigos para las preguntas de `ingresar`.

      iex> Emergencias.Anexos.Codigos.opciones("tamano")
      "TA1=pequena, TA2=mediana, TA3=grande"
  """
  def opciones(tabla), do: Enum.map_join(filas(tabla), ", ", &"#{&1.codigo}=#{&1.valor}")

  @doc """
  Opciones de las listas de la web y las ventanas.

      iex> Emergencias.Anexos.Codigos.etiquetas("tamano") |> hd()
      {"TA1", "TA1 – pequena"}
  """
  def etiquetas("barrio"),
    do:
      Enum.map(filas("barrio"), fn f ->
        {f.codigo, "#{f.codigo} – #{f.valor} (zona #{f.zona})"}
      end)

  def etiquetas(tabla), do: Enum.map(filas(tabla), &{&1.codigo, "#{&1.codigo} – #{&1.valor}"})

  # --- Mostrar tablas ---

  @doc "Lista de tablas (comando `codigos`)."
  def indice do
    lineas =
      Enum.map(tablas(), fn {nombre, titulo, uso, filas} ->
        "  #{String.pad_trailing(nombre, 15)} #{String.pad_trailing(titulo, 34)} " <>
          "#{length(filas)} códigos | se usa en: #{uso}"
      end)

    Enum.join(
      ["BASE DE DATOS DE CÓDIGOS (escriba: codigos <tabla>, o codigos todas)" | lineas] ++
        [
          "",
          "Puede escribir el código o el valor. Ejemplos:",
          "  registrar_barrio \"La Castellana\" norte      (recibe B01, el siguiente B02...)",
          "  reportar_mascota MT1 ES01 Luna CO01 TA2 B01 3001112233 caracteristicas=\"collar rojo\"",
          "  reportar_mascota MT2 ES03 desconocido CO05 TA1 norte 3001 especie_otra=conejo color_otro=atigrado"
        ],
      "\n"
    )
  end

  @doc "Dibuja una tabla con bordes."
  def formato_tabla(nombre) do
    case List.keyfind(tablas(), nombre, 0) do
      nil ->
        {:error, "Tabla desconocida '#{nombre}'. Tablas: #{Enum.join(nombres(), ", ")}"}

      {_n, titulo, uso, _f} ->
        {encabezado, filas} = columnas(nombre)
        {:ok, "#{titulo} (#{nombre}) — se usa en: #{uso}\n" <> dibujar(encabezado, filas)}
    end
  end

  @doc "Todas las tablas, una tras otra."
  def formato_todas do
    Enum.map_join(nombres(), "\n\n", fn nombre -> elem(formato_tabla(nombre), 1) end)
  end

  defp columnas("barrio"),
    do:
      {["Código", "Barrio", "Zona"],
       Enum.map(filas("barrio"), &[&1.codigo, &1.valor, &1.zona])}

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

  @doc "Recursiva. Calcula el ancho de cada columna."
  def ancho_columnas([], anchos), do: anchos

  def ancho_columnas([fila | resto], anchos) do
    nuevos = Enum.zip_with(fila, anchos, fn celda, ancho -> max(String.length(celda), ancho) end)
    ancho_columnas(resto, nuevos)
  end

  # --- Exportar ---

  @doc "Tablas en Markdown (CODIGOS.md)."
  def markdown do
    secciones =
      Enum.map(tablas(), fn {nombre, titulo, uso, _f} ->
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
          "registrar_barrio \"La Castellana\" norte\n" <>
          "reportar_mascota MT1 ES01 Luna CO01 TA2 B01 3001112233 caracteristicas=\"collar rojo\"\n" <>
          "reportar_mascota MT2 ES03 desconocido CO05 TA1 norte 3001 especie_otra=conejo color_otro=atigrado\n" <>
          "reportar_persona 1094 \"Andrés López\" B01 PE3 edad=34 tipo_doc=CC\n" <>
          "registrar_necesidad NT01 30 PR1 centro \"Punto de atención sector 3\"\n" <>
          "listar_mascotas especie=ES01\n" <>
          "```"
        | secciones
      ],
      "\n\n"
    ) <> "\n"
  end

  @doc "Tablas en CSV para Excel."
  def csv do
    lineas =
      Enum.flat_map(nombres(), fn nombre ->
        Enum.map(filas(nombre), fn f ->
          Enum.join([nombre, f.codigo, f.valor, f.descripcion], ";")
        end)
      end)

    Enum.join(["tabla;codigo;valor;descripcion" | lineas], "\n") <> "\n"
  end

  defp mayusculas(texto), do: texto |> to_string() |> String.trim() |> String.upcase()
end
