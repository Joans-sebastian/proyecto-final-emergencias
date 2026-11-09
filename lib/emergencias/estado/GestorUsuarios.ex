defmodule Emergencias.Estado.GestorUsuarios do
  @moduledoc """
  GenServer con los usuarios registrados (`usuarios.txt`).

  `conectar/5` es una sola operación atómica: si el usuario no existe lo
  registra y, si existe, valida la contraseña. Al estar dentro del GenServer,
  dos conexiones simultáneas con el mismo nombre nuevo no pueden registrarlo dos veces.
  """

  use GenServer

  alias Emergencias.Dominio.{Comun, Usuario}
  alias Emergencias.Estado.Persistente

  @archivo "usuarios.txt"

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Conecta un usuario. Retorna `{:ok, usuario, :registrado | :autenticado}` o
  `{:error, motivo}`. Sin tipo ni zona, un usuario nuevo queda como ciudadano
  de la zona `general`.
  """
  def conectar(username, password, tipo \\ nil, zona \\ nil, nombre \\ nil) do
    GenServer.call(__MODULE__, {:conectar, username, password, tipo, zona, nombre})
  end

  @doc "Registra un usuario ya creado (lo usa el administrador). El nombre no se puede repetir."
  def registrar(%Usuario{} = usuario), do: GenServer.call(__MODULE__, {:registrar, usuario})

  def obtener(username), do: GenServer.call(__MODULE__, {:obtener, Usuario.clave(username)})
  def listar, do: GenServer.call(__MODULE__, :listar)

  @impl true
  def init(:ok),
    do: {:ok, Persistente.cargar(@archivo, &Comun.desde_mapa(Usuario, &1), :username)}

  @impl true
  def handle_call({:conectar, username, password, tipo, zona, nombre}, _from, usuarios) do
    case Map.fetch(usuarios, Usuario.clave(username)) do
      {:ok, usuario} ->
        if Usuario.password_correcta?(usuario, password) do
          {:reply, {:ok, usuario, :autenticado}, usuarios}
        else
          {:reply, {:error, "Contraseña incorrecta para el usuario #{usuario.username}"},
           usuarios}
        end

      :error ->
        case Usuario.crear(username, password, tipo || "ciudadano", zona || "general", nombre) do
          {:ok, usuario} ->
            nuevos = Map.put(usuarios, usuario.username, usuario)
            Persistente.guardar(@archivo, nuevos, &Comun.a_mapa/1)
            {:reply, {:ok, usuario, :registrado}, nuevos}

          {:error, motivo} ->
            {:reply, {:error, motivo}, usuarios}
        end
    end
  end

  def handle_call({:registrar, usuario}, _from, usuarios) do
    if Map.has_key?(usuarios, usuario.username) do
      {:reply, {:error, "El usuario #{usuario.username} ya existe"}, usuarios}
    else
      nuevos = Map.put(usuarios, usuario.username, usuario)
      Persistente.guardar(@archivo, nuevos, &Comun.a_mapa/1)
      {:reply, {:ok, usuario}, nuevos}
    end
  end

  def handle_call({:obtener, clave}, _from, usuarios) do
    respuesta =
      case Map.fetch(usuarios, clave) do
        {:ok, usuario} -> {:ok, usuario}
        :error -> {:error, "El usuario #{clave} no existe"}
      end

    {:reply, respuesta, usuarios}
  end

  def handle_call(:listar, _from, usuarios),
    do: {:reply, usuarios |> Map.values() |> Enum.sort_by(& &1.username), usuarios}
end
