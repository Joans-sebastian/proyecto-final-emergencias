defmodule Emergencias.Servicios do
  @moduledoc """
  Operaciones que coordinan **varios gestores** a la vez (ingreso a un
  albergue, estado de una zona, resumen global, recursos críticos).

  Cada gestor es dueño de sus datos; este módulo no guarda estado, solo
  combina las respuestas.
  """

  alias Emergencias.Dominio.{Albergue, Necesidad, Recurso, Zona}

  alias Emergencias.Estado.{
    GestorAlbergues,
    GestorMascotas,
    GestorMensajes,
    GestorNecesidades,
    GestorPersonas,
    GestorRecursos,
    GestorZonas
  }

  @doc "Verifica que la zona (o sector o punto) esté registrada."
  def validar_zona(codigo) do
    case GestorZonas.obtener(codigo) do
      {:ok, _nodo} -> :ok
      error -> error
    end
  end

  @doc """
  Ingreso de una persona a un albergue: la persona debe estar registrada y
  poder pasar a `en_albergue`. Si el albergue acepta el ingreso pero luego no
  se puede actualizar a la persona, se deshace el ingreso.
  """
  def ingresar_a_albergue(codigo, documento, usuario) do
    with {:ok, persona} <- GestorPersonas.obtener(documento),
         :ok <- no_esta_en_otro(persona, codigo),
         {:ok, _} <- Emergencias.Dominio.Persona.validar_transicion(persona, "en_albergue"),
         {:ok, albergue} <- GestorAlbergues.ingresar(codigo, documento, usuario) do
      case GestorPersonas.cambiar_estado(
             documento,
             "en_albergue",
             usuario,
             "ingreso a #{codigo}",
             %{albergue: codigo}
           ) do
        {:ok, persona} ->
          {:ok, albergue, persona}

        {:error, motivo} ->
          GestorAlbergues.salir(codigo, documento, usuario)
          {:error, motivo}
      end
    end
  end

  defp no_esta_en_otro(%{albergue: codigo, estado: "en_albergue"} = persona, codigo),
    do: {:error, "#{persona.nombre} ya está registrada en el albergue #{codigo}"}

  defp no_esta_en_otro(%{albergue: actual, estado: "en_albergue"}, _codigo) when actual != nil,
    do: {:error, "La persona ya está en el albergue #{actual}; registre primero su salida"}

  defp no_esta_en_otro(_persona, _codigo), do: :ok

  @doc "Salida de un albergue: la persona queda `localizada` y sin albergue."
  def salir_de_albergue(codigo, documento, usuario) do
    with {:ok, _persona} <- GestorPersonas.obtener(documento),
         {:ok, albergue} <- GestorAlbergues.salir(codigo, documento, usuario) do
      case GestorPersonas.cambiar_estado(
             documento,
             "localizada",
             usuario,
             "salida de #{codigo}",
             %{albergue: nil}
           ) do
        {:ok, persona} -> {:ok, albergue, persona}
        {:error, _motivo} -> {:ok, albergue, nil}
      end
    end
  end

  @doc """
  Estado de una zona: el subárbol, las estadísticas acumuladas (recursivas) y
  cuántas necesidades, recursos, albergues, personas y mascotas hay en la zona
  o en cualquiera de sus sectores y puntos.
  """
  def estado_zona(codigo) do
    with {:ok, nodo} <- GestorZonas.obtener(codigo) do
      codigos = nodo |> Zona.codigos() |> MapSet.new()

      en_zona = fn lista, campo ->
        Enum.filter(lista, &MapSet.member?(codigos, Map.get(&1, campo)))
      end

      necesidades = en_zona.(GestorNecesidades.listar(), :zona)

      {:ok,
       %{
         nodo: nodo,
         estadisticas: Zona.estadisticas(nodo),
         necesidades: necesidades,
         pendientes: Enum.filter(necesidades, &(&1.estado == "pendiente")),
         recursos: en_zona.(GestorRecursos.listar(), :zona),
         albergues: en_zona.(GestorAlbergues.listar(), :zona),
         personas: en_zona.(GestorPersonas.buscar(%{}), :zona),
         mascotas: en_zona.(GestorMascotas.listar(), :zona)
       }}
    end
  end

  @doc "Datos del resumen global de la emergencia."
  def resumen do
    arboles = GestorZonas.arboles()
    necesidades = GestorNecesidades.listar()
    personas = GestorPersonas.buscar(%{})
    mensajes = GestorMensajes.listar()
    mascotas = GestorMascotas.listar()
    albergues = GestorAlbergues.listar()

    %{
      zonas: Enum.map(arboles, &{&1, Zona.estadisticas(&1)}),
      recursos: GestorRecursos.listar(),
      necesidades_por_estado: contar(necesidades, & &1.estado),
      pendientes_por_prioridad:
        necesidades |> Enum.filter(&(&1.estado == "pendiente")) |> contar(& &1.prioridad),
      personas_por_estado: contar(personas, & &1.estado),
      mensajes_por_estado: contar(mensajes, & &1.estado),
      mascotas_por_estado: contar(mascotas, & &1.estado),
      albergues: albergues,
      ocupacion_total: albergues |> Enum.map(&Albergue.ocupacion/1) |> Enum.sum(),
      capacidad_total: albergues |> Enum.map(& &1.capacidad) |> Enum.sum(),
      sesiones: Emergencias.Sesiones.activas()
    }
  end

  @doc """
  Recursos críticos: los que tienen `umbral` unidades o menos, y los tipos de
  necesidad pendiente cuya demanda supera lo disponible.
  """
  def recursos_criticos(umbral) do
    recursos = GestorRecursos.listar()
    pendientes = GestorNecesidades.listar(%{"estado" => "pendiente"})

    escasos =
      recursos
      |> Enum.filter(&(Recurso.total(&1) <= umbral))
      |> Enum.sort_by(&Recurso.total/1)

    deficit =
      pendientes
      |> Enum.group_by(& &1.tipo)
      |> Enum.map(fn {tipo, lista} ->
        demanda = lista |> Enum.map(&Necesidad.faltante/1) |> Enum.sum()

        disponible =
          recursos
          |> Enum.filter(&Recurso.coincide?(&1, tipo))
          |> Enum.map(&Recurso.total/1)
          |> Enum.sum()

        %{
          tipo: tipo,
          demanda: demanda,
          disponible: disponible,
          necesidades: Enum.map(lista, & &1.id)
        }
      end)
      |> Enum.filter(&(&1.demanda > &1.disponible))
      |> Enum.sort_by(&(&1.disponible - &1.demanda))

    %{escasos: escasos, deficit: deficit}
  end

  defp contar(lista, clave), do: lista |> Enum.frequencies_by(clave) |> Enum.sort()
end
