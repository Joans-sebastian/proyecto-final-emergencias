defmodule Emergencias.Sesiones do
  @moduledoc """
  Conexión y desconexión de usuarios (`conectar` / `desconectar`).

  - Si el usuario no existe, se registra automáticamente.
  - Si existe, se valida la contraseña.
  - Al conectarse se inicia su proceso `Emergencias.Sesion` bajo el
    `DynamicSupervisor`. Si ya tenía una sesión abierta, se reutiliza.
  """

  alias Emergencias.{Sesion, Permisos}
  alias Emergencias.Estado.{Bitacora, GestorUsuarios}

  @doc """
  Convierte los datos de un formulario de inicio de sesión (ventanas o web) en
  los argumentos de `conectar/2`. Los campos vacíos quedan en `nil` para que no
  cambien de posición.

      iex> Emergencias.Sesiones.desde_formulario(["ana", "1234", "", "norte", "Ana López"])
      {["ana", "1234", nil, "norte"], %{"nombre" => "Ana López"}}
  """
  def desde_formulario([usuario, contrasena, tipo, zona, nombre]) do
    opcional = &Emergencias.Dominio.Comun.opcional/1

    {[usuario || "", contrasena || "", opcional.(tipo), opcional.(zona)],
     %{"nombre" => opcional.(nombre)}}
  end

  @doc """
  `conectar usuario contraseña [tipo] [zona] [nombre="Nombre completo"]`.
  Retorna `{:ok, pid, usuario, mensaje}` o `{:error, motivo}`.
  """
  def conectar(argumentos, opciones \\ %{})

  def conectar([username, password | resto], opciones) do
    tipo = Enum.at(resto, 0)
    zona = Enum.at(resto, 1)
    nombre = Map.get(opciones, "nombre") || nombre_posicional(Enum.drop(resto, 2))

    case GestorUsuarios.conectar(username, password, tipo, zona, nombre) do
      {:ok, usuario, modo} ->
        {:ok, pid} = iniciar(usuario)
        Bitacora.registrar(usuario.username, "conectar (#{modo})", :ok)
        {:ok, pid, usuario, mensaje_bienvenida(usuario, modo, tipo)}

      {:error, motivo} ->
        Bitacora.registrar(Emergencias.Dominio.Usuario.clave(username), "conectar", :error)
        {:error, motivo}
    end
  end

  def conectar(_argumentos, _opciones),
    do: {:error, "Uso: #{Permisos.uso("conectar")}"}

  @doc "Inicia (o reutiliza) el proceso de sesión del usuario."
  def iniciar(usuario) do
    case DynamicSupervisor.start_child(Emergencias.SupervisorSesiones, {Sesion, usuario}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @doc "Cierra la sesión del usuario."
  def desconectar(username) do
    case Registry.lookup(Emergencias.RegistroSesiones, username) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Emergencias.SupervisorSesiones, pid)
        Bitacora.registrar(username, "desconectar", :ok)
        {:ok, "Sesión de #{username} cerrada. ¡Hasta pronto!"}

      [] ->
        {:error, "El usuario #{username} no tiene una sesión abierta"}
    end
  end

  @doc "Nombres de los usuarios con sesión abierta."
  def activas do
    Emergencias.RegistroSesiones
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  defp nombre_posicional([]), do: nil
  defp nombre_posicional(palabras), do: Enum.join(palabras, " ")

  defp mensaje_bienvenida(usuario, :registrado, _tipo) do
    "Usuario nuevo registrado y conectado: #{usuario.nombre} (@#{usuario.username}), " <>
      "rol #{usuario.tipo}, zona #{usuario.zona}. Escriba ayuda para ver sus comandos."
  end

  defp mensaje_bienvenida(usuario, :autenticado, tipo) do
    aviso =
      if tipo && Emergencias.Dominio.Comun.normalizar(tipo) != usuario.tipo,
        do: " (el usuario ya existía: se conserva su rol registrado)",
        else: ""

    "Bienvenido de nuevo, #{usuario.nombre} (@#{usuario.username}). Rol #{usuario.tipo}, zona #{usuario.zona}#{aviso}."
  end
end
