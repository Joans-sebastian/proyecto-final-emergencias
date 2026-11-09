defmodule Emergencias.Estado.GestorRecursos do
  @moduledoc """
  GenServer con el inventario de recursos (`recursos.txt`).

  ## Regla de concurrencia

  Todas las operaciones que cambian existencias (salidas, transferencias y
  sobre todo `retirar/5`) se ejecutan **dentro** de este proceso. Un GenServer
  atiende un mensaje a la vez, así que "revisar si alcanza" y "descontar" ocurren
  juntos, sin que otra solicitud se meta en medio. Si dos usuarios piden al
  mismo tiempo 30 y 25 litros de 50 disponibles, el segundo mensaje se procesa
  con el inventario ya descontado (20 litros) y se rechaza: nunca se entregan 55.
  """

  use GenServer

  alias Emergencias.Dominio.{Comun, Recurso}
  alias Emergencias.Estado.Persistente

  @archivo "recursos.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Registra un recurso nuevo. El código no se puede repetir."
  def registrar(%Recurso{} = recurso), do: GenServer.call(__MODULE__, {:registrar, recurso})

  def entrada(codigo, ubicacion, cantidad, motivo, usuario),
    do: GenServer.call(__MODULE__, {:entrada, codigo, ubicacion, cantidad, motivo, usuario})

  def salida(codigo, ubicacion, cantidad, motivo, usuario),
    do: GenServer.call(__MODULE__, {:salida, codigo, ubicacion, cantidad, motivo, usuario})

  def transferir(codigo, origen, destino, cantidad, usuario),
    do: GenServer.call(__MODULE__, {:transferir, codigo, origen, destino, cantidad, usuario})

  @doc """
  Retira `cantidad` unidades de los recursos que sirven para `tipo` (código,
  nombre o categoría), dando preferencia a la `zona` de la necesidad. Es todo o
  nada: retorna `{:ok, partes}` con lo tomado de cada ubicación, o
  `{:error, motivo}` sin tocar el inventario.
  """
  def retirar(tipo, cantidad, zona, referencia, usuario),
    do: GenServer.call(__MODULE__, {:retirar, tipo, cantidad, zona, referencia, usuario})

  @doc "Devuelve al inventario lo que se había retirado (por ejemplo, al cancelar una necesidad)."
  def devolver(partes, referencia, usuario),
    do: GenServer.call(__MODULE__, {:devolver, partes, referencia, usuario})

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})

  @impl true
  def init(:ok), do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Recurso, &1), :codigo)}

  @impl true
  def handle_call({:registrar, recurso}, _from, recursos) do
    case codigo_libre(recursos, recurso.codigo) do
      :ok -> responder_cambio(recursos, recurso)
      error -> {:reply, error, recursos}
    end
  end

  def handle_call({:entrada, codigo, ubicacion, cantidad, motivo, usuario}, _from, recursos) do
    modificar(recursos, codigo, &Recurso.entrada(&1, ubicacion, cantidad, motivo, usuario))
  end

  def handle_call({:salida, codigo, ubicacion, cantidad, motivo, usuario}, _from, recursos) do
    modificar(recursos, codigo, &Recurso.salida(&1, ubicacion, cantidad, motivo, usuario))
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad, usuario}, _from, recursos) do
    modificar(recursos, codigo, &Recurso.transferir(&1, origen, destino, cantidad, usuario))
  end

  def handle_call({:retirar, tipo, cantidad, zona, referencia, usuario}, _from, recursos) do
    candidatos = recursos |> Map.values() |> Enum.filter(&Recurso.coincide?(&1, tipo))
    fuentes = Recurso.fuentes(candidatos, zona)

    cond do
      candidatos == [] ->
        {:reply, {:error, "No hay recursos registrados de tipo '#{tipo}'"}, recursos}

      true ->
        case Recurso.planear_retiro(fuentes, cantidad) do
          {:ok, partes} ->
            nuevos =
              aplicar_partes(recursos, partes, "asignación a #{referencia}", usuario, :salida)

            Persistente.guardar(@archivo, nuevos, &Comun.a_mapa/1)
            {:reply, {:ok, partes}, nuevos}

          :insuficiente ->
            disponible = Enum.reduce(fuentes, 0, fn {_c, _u, d}, acc -> acc + d end)

            {:reply,
             {:error,
              "Inventario insuficiente de '#{tipo}': hay #{disponible} disponibles y se pidieron " <>
                "#{cantidad}. No se asignó nada"}, recursos}
        end
    end
  end

  def handle_call({:devolver, partes, referencia, usuario}, _from, recursos) do
    nuevos = aplicar_partes(recursos, partes, "devolución de #{referencia}", usuario, :entrada)
    Persistente.guardar(@archivo, nuevos, &Comun.a_mapa/1)
    {:reply, :ok, nuevos}
  end

  def handle_call({:obtener, codigo}, _from, recursos) do
    {:reply, buscar(recursos, codigo), recursos}
  end

  def handle_call({:listar, filtros}, _from, recursos) do
    lista =
      recursos
      |> Map.values()
      |> Enum.filter(fn recurso ->
        Enum.all?(filtros, fn
          {"tipo", tipo} -> Recurso.coincide?(recurso, tipo)
          {"zona", zona} -> recurso.zona == zona
          {"ubicacion", ubicacion} -> Map.has_key?(recurso.existencias, ubicacion)
          {_otro, _valor} -> true
        end)
      end)
      |> Enum.sort_by(& &1.codigo)

    {:reply, lista, recursos}
  end

  # Aplica cada parte (salida o entrada) sobre el recurso correspondiente.
  # Las partes ya fueron validadas por planear_retiro/2, por eso no pueden fallar.
  defp aplicar_partes(recursos, partes, detalle, usuario, operacion) do
    Enum.reduce(partes, recursos, fn %{
                                       "codigo" => codigo,
                                       "ubicacion" => ubicacion,
                                       "cantidad" => cantidad
                                     },
                                     acumulado ->
      recurso = Map.fetch!(acumulado, codigo)

      {:ok, actualizado} =
        case operacion do
          :salida ->
            Recurso.salida(recurso, ubicacion, cantidad, detalle, usuario, "asignacion")

          :entrada ->
            Recurso.entrada(recurso, ubicacion, cantidad, detalle, usuario, "devolucion")
        end

      Map.put(acumulado, codigo, actualizado)
    end)
  end

  defp modificar(recursos, codigo, funcion) do
    with {:ok, recurso} <- buscar(recursos, codigo),
         {:ok, actualizado} <- funcion.(recurso) do
      responder_cambio(recursos, actualizado)
    else
      error -> {:reply, error, recursos}
    end
  end

  defp responder_cambio(recursos, recurso) do
    nuevos = Map.put(recursos, recurso.codigo, recurso)
    Persistente.guardar(@archivo, nuevos, &Comun.a_mapa/1)
    {:reply, {:ok, recurso}, nuevos}
  end

  defp buscar(recursos, codigo) do
    case Map.fetch(recursos, codigo) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, "El recurso '#{codigo}' no existe"}
    end
  end

  defp codigo_libre(recursos, codigo) do
    if Map.has_key?(recursos, String.trim(to_string(codigo))),
      do:
        {:error,
         "Ya existe un recurso con el código '#{codigo}' (use entrada_recurso para agregar existencias)"},
      else: :ok
  end
end
