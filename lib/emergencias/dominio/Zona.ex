defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Zonas afectadas organizadas como un **árbol**: zona → sectores → puntos de atención.

      %Zona{codigo: "centro", tipo: "zona", hijos: [
        %Zona{codigo: "sector3", tipo: "sector", hijos: [
          %Zona{codigo: "punto3", tipo: "punto", hijos: []}
        ]}
      ]}

  Todas las operaciones sobre el árbol son **recursivas** (insertar, buscar,
  actualizar, recolectar códigos, acumular estadísticas y dibujar). Cada nodo
  guarda las personas afectadas registradas directamente en él; las
  estadísticas suman el nodo y todos sus descendientes.
  """

  alias Emergencias.Dominio.Comun
  alias Emergencias.Anexos.Codigos

  defstruct [:codigo, :nombre, :tipo, :nivel, :personas, :padre, :creada, hijos: []]

  @niveles ~w(critico alto medio bajo)
  @gravedad %{"critico" => 4, "alto" => 3, "medio" => 2, "bajo" => 1}
  @tipo_hijo %{"zona" => "sector", "sector" => "punto"}

  @doc "Niveles de afectación válidos."
  def niveles, do: @niveles

  @doc """
  Crea un nodo validando sus datos. Sin `padre` es una zona; con padre será
  sector o punto (el tipo exacto se decide al insertarlo en el árbol).

      Zona.crear("centro", "Zona Centro", "critico", 1200)
      Zona.crear("sector3", "Sector 3", "alto", 300, "centro")
  """
  def crear(codigo, nombre, nivel, personas, padre \\ nil) do
    with {:ok, codigo} <- Comun.codigo(codigo, "Código de zona"),
         {:ok, nombre} <- Comun.requerido(nombre, "Nombre de la zona"),
         {:ok, nivel} <-
           Comun.en_lista(Codigos.traducir("nivel", nivel), @niveles, "Nivel de afectación"),
         {:ok, personas} <- Comun.entero_no_negativo(personas, "Personas afectadas"),
         {:ok, padre} <- validar_padre(padre) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         tipo: "zona",
         nivel: nivel,
         personas: personas,
         padre: padre,
         creada: Comun.ahora()
       }}
    end
  end

  defp validar_padre(padre) when padre in [nil, ""], do: {:ok, nil}
  defp validar_padre(padre), do: Comun.codigo(padre, "Código del padre")

  @doc """
  Lee desde teclado los datos de una zona, sector o punto (con `Util2` del curso).

      Zona.ingresar()
  """
  def ingresar do
    Util2.mostrar("\nIngrese los datos de la zona, sector o punto:\n", :mensaje)

    crear(
      Util2.ingresar("Código: ", :texto),
      Util2.ingresar("Nombre: ", :texto),
      Util2.ingresar("Nivel de afectación (#{Codigos.opciones("nivel")}): ", :texto),
      Util2.ingresar("Personas afectadas: ", :entero),
      Util2.ingresar("Código del padre (vacío si es una zona): ", :texto)
    )
  end

  @doc "Representación de un nodo como texto (sin sus hijos)."
  def to_string(%__MODULE__{} = n) do
    "[#{n.tipo}] #{n.codigo}: #{n.nombre} | nivel #{n.nivel} | #{n.personas} personas afectadas"
  end

  @doc "Valida un nivel de afectación."
  def validar_nivel(nivel),
    do: Comun.en_lista(Codigos.traducir("nivel", nivel), @niveles, "Nivel de afectación")

  # ---------------------------------------------------------------------------
  # Recursión 1: insertar un nodo debajo de su padre
  # ---------------------------------------------------------------------------

  @doc """
  Inserta `nodo` en el bosque `arboles`. Sin padre queda como zona raíz; con
  padre, queda como sector (si el padre es zona) o como punto (si es sector).
  """
  def insertar(arboles, nil, nodo) do
    with {:ok, codigo} <- Comun.zona(nodo.codigo, "Código de zona principal"),
         do: {:ok, arboles ++ [%{nodo | codigo: codigo, tipo: "zona"}]}
  end

  def insertar(arboles, padre, nodo) do
    with :ok <- no_reservado(nodo.codigo),
         resultado <- insertar_en(arboles, padre, nodo),
         do: respuesta_insertar(resultado, padre)
  end

  # Un sector o punto no puede usar el código de una zona principal.
  defp no_reservado(codigo) do
    if Comun.normalizar(codigo) in Comun.zonas(),
      do: {:error, "'#{codigo}' está reservado para una zona principal; use otro código"},
      else: :ok
  end

  defp respuesta_insertar(resultado, padre) do
    case resultado do
      {:ok, nuevos} -> {:ok, nuevos}
      :no_encontrado -> {:error, "La zona o sector padre '#{padre}' no existe"}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp insertar_en([], _padre, _nodo), do: :no_encontrado

  defp insertar_en([%__MODULE__{codigo: padre} = actual | resto], padre, nodo) do
    case Map.get(@tipo_hijo, actual.tipo) do
      nil ->
        {:error, "'#{padre}' es un punto de atención y no puede contener otros nodos"}

      tipo ->
        {:ok, [%{actual | hijos: actual.hijos ++ [%{nodo | tipo: tipo}]} | resto]}
    end
  end

  defp insertar_en([actual | resto], padre, nodo) do
    case insertar_en(actual.hijos, padre, nodo) do
      {:ok, hijos} ->
        {:ok, [%{actual | hijos: hijos} | resto]}

      :no_encontrado ->
        case insertar_en(resto, padre, nodo) do
          {:ok, otros} -> {:ok, [actual | otros]}
          otro -> otro
        end

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  # ---------------------------------------------------------------------------
  # Recursión 2: buscar un nodo por código
  # ---------------------------------------------------------------------------

  @doc "Busca un nodo en cualquier nivel del bosque. Retorna el nodo o `nil`."
  def buscar([], _codigo), do: nil
  def buscar([%__MODULE__{codigo: codigo} = nodo | _resto], codigo), do: nodo
  def buscar([nodo | resto], codigo), do: buscar(nodo.hijos, codigo) || buscar(resto, codigo)

  # ---------------------------------------------------------------------------
  # Recursión 3: actualizar un nodo
  # ---------------------------------------------------------------------------

  @doc "Aplica `funcion` al nodo con `codigo`. Retorna `{:ok, arboles}` o `:no_encontrado`."
  def actualizar([], _codigo, _funcion), do: :no_encontrado

  def actualizar([%__MODULE__{codigo: codigo} = nodo | resto], codigo, funcion),
    do: {:ok, [funcion.(nodo) | resto]}

  def actualizar([nodo | resto], codigo, funcion) do
    case actualizar(nodo.hijos, codigo, funcion) do
      {:ok, hijos} ->
        {:ok, [%{nodo | hijos: hijos} | resto]}

      :no_encontrado ->
        case actualizar(resto, codigo, funcion) do
          {:ok, otros} -> {:ok, [nodo | otros]}
          :no_encontrado -> :no_encontrado
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Recursión 4: códigos de un subárbol
  # ---------------------------------------------------------------------------

  @doc "Códigos del nodo y de todos sus descendientes."
  def codigos(%__MODULE__{codigo: codigo, hijos: hijos}), do: [codigo | codigos_lista(hijos)]

  @doc "Códigos de todos los nodos de una lista de árboles."
  def codigos_lista([]), do: []
  def codigos_lista([nodo | resto]), do: codigos(nodo) ++ codigos_lista(resto)

  # ---------------------------------------------------------------------------
  # Recursión 5: estadísticas acumuladas
  # ---------------------------------------------------------------------------

  @doc """
  Estadísticas del nodo sumadas con las de todos sus descendientes:
  personas afectadas, número de sectores y de puntos, y el nivel más grave.
  """
  def estadisticas(%__MODULE__{} = nodo) do
    propias = %{
      personas: nodo.personas,
      sectores: if(nodo.tipo == "sector", do: 1, else: 0),
      puntos: if(nodo.tipo == "punto", do: 1, else: 0),
      nivel_maximo: nodo.nivel
    }

    combinar(propias, estadisticas_lista(nodo.hijos))
  end

  defp estadisticas_lista([]), do: %{personas: 0, sectores: 0, puntos: 0, nivel_maximo: nil}

  defp estadisticas_lista([nodo | resto]),
    do: combinar(estadisticas(nodo), estadisticas_lista(resto))

  defp combinar(a, b) do
    %{
      personas: a.personas + b.personas,
      sectores: a.sectores + b.sectores,
      puntos: a.puntos + b.puntos,
      nivel_maximo: mas_grave(a.nivel_maximo, b.nivel_maximo)
    }
  end

  @doc "El más grave de dos niveles (`nil` cuenta como ausencia de nivel)."
  def mas_grave(nil, otro), do: otro
  def mas_grave(uno, nil), do: uno

  def mas_grave(uno, otro),
    do: if(Map.fetch!(@gravedad, uno) >= Map.fetch!(@gravedad, otro), do: uno, else: otro)

  @doc "Peso numérico del nivel (para ordenar)."
  def gravedad(nivel), do: Map.get(@gravedad, nivel, 0)

  # ---------------------------------------------------------------------------
  # Recursión 6: representación del árbol como texto
  # ---------------------------------------------------------------------------

  @doc "Líneas de texto del árbol, con sangría según la profundidad."
  def lineas(%__MODULE__{} = nodo, profundidad \\ 0) do
    sangria = String.duplicate("    ", profundidad)

    [sangria <> "- " <> __MODULE__.to_string(nodo) | lineas_hijos(nodo.hijos, profundidad + 1)]
  end

  defp lineas_hijos([], _profundidad), do: []

  defp lineas_hijos([hijo | resto], profundidad),
    do: lineas(hijo, profundidad) ++ lineas_hijos(resto, profundidad)

  # ---------------------------------------------------------------------------
  # Persistencia (también recursiva, por los hijos)
  # ---------------------------------------------------------------------------

  def a_mapa(%__MODULE__{} = nodo) do
    nodo |> Map.from_struct() |> Map.put(:hijos, Enum.map(nodo.hijos, &a_mapa/1))
  end

  def desde_mapa(mapa) do
    nodo = Comun.desde_mapa(__MODULE__, mapa)
    %{nodo | hijos: Enum.map(nodo.hijos || [], &desde_mapa/1)}
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
