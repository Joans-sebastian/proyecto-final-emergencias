defmodule Emergencias.Dominio.Comun do
  @moduledoc """
  Funciones **puras** compartidas por las entidades del dominio: validación de
  entradas, normalización de textos, generación de identificadores y conversión
  entre structs y mapas para la persistencia.

  Todas retornan tuplas `{:ok, valor}` / `{:error, motivo}` en lugar de lanzar
  excepciones para las situaciones esperadas.
  """

  @doc """
  Normaliza un valor de una lista cerrada (estados, niveles, prioridades):
  minúsculas, sin tildes y con `_` en lugar de espacios.

      iex> Emergencias.Dominio.Comun.normalizar("  Crítica ")
      "critica"
      iex> Emergencias.Dominio.Comun.normalizar("Sin información")
      "sin_informacion"
  """
  def normalizar(nil), do: ""

  def normalizar(texto) do
    texto
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, "_")
  end

  @doc "Fecha y hora local actual como texto (`AAAA-MM-DD HH:MM:SS`)."
  def ahora do
    NaiveDateTime.local_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  @doc "Convierte un texto en entero."
  def entero(valor) when is_integer(valor), do: {:ok, valor}

  def entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, "'#{texto}' no es un número entero"}
    end
  end

  def entero(_otro), do: {:error, "se esperaba un número entero"}

  @doc "Entero mayor que cero."
  def entero_positivo(valor, campo) do
    case entero(valor) do
      {:ok, n} when n > 0 -> {:ok, n}
      {:ok, n} -> {:error, "#{campo} debe ser mayor que 0 (se recibió #{n})"}
      {:error, _} -> {:error, "#{campo} debe ser un número entero (se recibió '#{valor}')"}
    end
  end

  @doc "Entero mayor o igual a cero."
  def entero_no_negativo(valor, campo) do
    case entero(valor) do
      {:ok, n} when n >= 0 -> {:ok, n}
      {:ok, n} -> {:error, "#{campo} no puede ser negativo (se recibió #{n})"}
      {:error, _} -> {:error, "#{campo} debe ser un número entero (se recibió '#{valor}')"}
    end
  end

  @doc "Texto obligatorio (no vacío)."
  def requerido(texto, campo) do
    limpio = texto |> to_string() |> String.trim()

    if limpio == "", do: {:error, "#{campo} es obligatorio"}, else: {:ok, limpio}
  end

  @doc "Código o identificador: letras, números, guion o guion bajo, sin espacios."
  def codigo(texto, campo) do
    limpio = texto |> to_string() |> String.trim()

    if Regex.match?(~r/^[A-Za-z0-9_\-]{1,40}$/, limpio) do
      {:ok, limpio}
    else
      {:error,
       "#{campo} inválido: '#{limpio}' (use letras, números, guion o guion bajo, sin espacios)"}
    end
  end

  # ---------------------------------------------------------------------------
  # Catálogo de códigos permitidos
  # ---------------------------------------------------------------------------

  @zonas ~w(sur centro norte este oeste)
  @albergues ~w(A01 A02 A03)
  @recursos ~w(R001 R002 R003)
  @centros ~w(centro_acopio bodega fundacion)

  @doc "Códigos de las zonas principales (raíces del árbol de zonas)."
  def zonas, do: @zonas

  @doc "Códigos de albergue permitidos."
  def albergues, do: @albergues

  @doc "Códigos de recurso permitidos."
  def recursos, do: @recursos

  @doc "Ubicaciones de inventario: centros de apoyo y albergues."
  def ubicaciones, do: @centros ++ @albergues

  @doc """
  Zona principal: `sur`, `centro`, `norte`, `este` u `oeste`.

      iex> Emergencias.Dominio.Comun.zona(" Norte ", "Zona")
      {:ok, "norte"}
      iex> Emergencias.Dominio.Comun.zona("zona_norte", "Zona")
      {:error, "Zona inválido: 'zona_norte'. Códigos permitidos: sur, centro, norte, este, oeste"}
  """
  def zona(texto, campo), do: en_catalogo(normalizar(texto), texto, @zonas, campo)

  @doc """
  Código de albergue: `A01`, `A02` o `A03` (acepta minúsculas).

      iex> Emergencias.Dominio.Comun.albergue("a02", "Código del albergue")
      {:ok, "A02"}
  """
  def albergue(texto, campo), do: en_catalogo(mayusculas(texto), texto, @albergues, campo)

  @doc """
  Código de recurso: `R001`, `R002` o `R003` (acepta minúsculas).

      iex> Emergencias.Dominio.Comun.recurso("R003", "Código del recurso")
      {:ok, "R003"}
  """
  def recurso(texto, campo), do: en_catalogo(mayusculas(texto), texto, @recursos, campo)

  @doc """
  Ubicación de inventario: `centro_acopio`, `bodega`, `fundacion` o un albergue.

      iex> Emergencias.Dominio.Comun.ubicacion("Bodega", "Ubicación")
      {:ok, "bodega"}
      iex> Emergencias.Dominio.Comun.ubicacion("a01", "Ubicación")
      {:ok, "A01"}
  """
  def ubicacion(texto, campo) do
    if mayusculas(texto) in @albergues,
      do: {:ok, mayusculas(texto)},
      else: en_catalogo(normalizar(texto), texto, @centros, campo, ubicaciones())
  end

  defp mayusculas(texto), do: texto |> to_string() |> String.trim() |> String.upcase()

  defp en_catalogo(valor, original, validos, campo, mostrar \\ nil) do
    if valor in validos do
      {:ok, valor}
    else
      {:error,
       "#{campo} inválido: '#{original |> to_string() |> String.trim()}'. " <>
         "Códigos permitidos: #{Enum.join(mostrar || validos, ", ")}"}
    end
  end

  @doc "Valor que debe pertenecer a una lista cerrada. Retorna el valor normalizado."
  def en_lista(valor, validos, campo) do
    normalizado = normalizar(valor)

    if normalizado in validos do
      {:ok, normalizado}
    else
      {:error, "#{campo} inválido: '#{valor}'. Valores permitidos: #{Enum.join(validos, ", ")}"}
    end
  end

  @doc """
  Genera el siguiente identificador libre con un prefijo: `N001`, `N002`, ...
  Es recursiva: si el número ya existe, prueba con el siguiente.
  """
  def siguiente_id(prefijo, existentes),
    do: generar_id(prefijo, existentes, map_size(existentes) + 1)

  defp generar_id(prefijo, existentes, numero) do
    id = prefijo <> String.pad_leading(Integer.to_string(numero), 3, "0")

    if Map.has_key?(existentes, id), do: generar_id(prefijo, existentes, numero + 1), else: id
  end

  @doc "Evento para los historiales (mapa con claves de texto, igual que al leerlo del archivo)."
  def evento(desde, hacia, usuario, detalle \\ "") do
    %{"fecha" => ahora(), "de" => desde, "a" => hacia, "usuario" => usuario, "detalle" => detalle}
  end

  @doc "Struct → mapa, para guardarlo como JSON."
  def a_mapa(struct), do: Map.from_struct(struct)

  @doc """
  Mapa leído del archivo (claves de texto) → struct. Solo toma los campos que
  existen en el struct, así un campo desconocido en el archivo no causa errores.
  """
  def desde_mapa(modulo, mapa) do
    base = struct(modulo)

    base
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.reduce(base, fn campo, acumulado ->
      case Map.fetch(mapa, Atom.to_string(campo)) do
        {:ok, valor} -> Map.put(acumulado, campo, valor)
        :error -> acumulado
      end
    end)
  end

  @doc "Convierte un texto vacío en `nil` (para campos opcionales)."
  def opcional(nil), do: nil

  def opcional(texto) do
    case String.trim(texto) do
      "" -> nil
      limpio -> limpio
    end
  end

  @doc "Palabras normalizadas de un texto (para comparar descripciones)."
  def palabras(nil), do: []

  def palabras(texto) do
    texto
    |> normalizar()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end
end
