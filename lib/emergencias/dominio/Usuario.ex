defmodule Emergencias.Dominio.Usuario do
  @moduledoc """
  Usuario que participa en la coordinación de la emergencia.

  - Campos: `username`, `hash` y `sal` (la contraseña nunca se guarda en texto
    plano), `nombre`, `tipo`, `zona` y fecha de `creado`.
  - Los tipos son niveles de permiso acumulativos:
    ciudadano (1) < voluntario (2) < coordinador (3) < administrador (4).
  """

  alias Emergencias.Dominio.Comun
  alias Emergencias.Anexos.Codigos

  defstruct [:username, :hash, :sal, :nombre, :tipo, :zona, :creado]

  @tipos ~w(ciudadano voluntario coordinador administrador)
  @niveles %{"ciudadano" => 1, "voluntario" => 2, "coordinador" => 3, "administrador" => 4}

  @doc "Tipos de usuario válidos."
  def tipos, do: @tipos

  @doc "Nivel de permiso de un usuario o de un tipo de usuario (0 si no existe)."
  def nivel(%__MODULE__{tipo: tipo}), do: nivel(tipo)
  def nivel(tipo) when is_binary(tipo), do: Map.get(@niveles, tipo, 0)

  @doc "Tipo de usuario que corresponde a un nivel."
  def tipo_de_nivel(nivel), do: Enum.find(@tipos, &(@niveles[&1] == nivel))

  @doc """
  Crea un usuario validando sus datos. Retorna `{:ok, usuario}` o `{:error, motivo}`.

      Usuario.crear("laura", "1234", "coordinador", "centro", "Laura Gómez")
  """
  def crear(username, password, tipo, zona, nombre \\ nil) do
    with {:ok, username} <- validar_username(username),
         :ok <- validar_password(password),
         {:ok, tipo} <- Comun.en_lista(Codigos.traducir("rol", tipo), @tipos, "Tipo de usuario"),
         {:ok, zona} <- Comun.en_lista(zona, Comun.zonas() ++ ["general"], "Zona principal") do
      sal = :crypto.strong_rand_bytes(8) |> Base.encode16()

      {:ok,
       %__MODULE__{
         username: username,
         sal: sal,
         hash: hash(sal, password),
         nombre: nombre_completo(nombre, username),
         tipo: tipo,
         zona: zona,
         creado: Comun.ahora()
       }}
    end
  end

  @doc """
  Lee desde teclado los datos de un usuario (con `Util2` del curso) y lo crea.

      Usuario.ingresar()
  """
  def ingresar do
    Util2.mostrar("\nIngrese los datos del usuario:\n", :mensaje)

    crear(
      Util2.ingresar("Nombre de usuario: ", :texto),
      Util2.ingresar("Contraseña: ", :texto),
      Util2.ingresar("Tipo (#{Codigos.opciones("rol")}): ", :texto),
      Util2.ingresar("Zona principal: ", :texto),
      Util2.ingresar("Nombre completo: ", :texto)
    )
  end

  @doc "Representación del usuario como texto (sin datos de la contraseña)."
  def to_string(%__MODULE__{} = u),
    do: "@#{u.username} | #{u.nombre} | rol #{u.tipo} | zona #{u.zona} | desde #{u.creado}"

  @doc "Indica si `password` es la contraseña del usuario."
  def password_correcta?(%__MODULE__{sal: sal, hash: guardado}, password)
      when is_binary(password),
      do: hash(sal, password) == guardado

  def password_correcta?(_usuario, _password), do: false

  @doc "Clave con la que se busca un usuario (minúsculas, sin espacios a los lados)."
  def clave(username), do: username |> Kernel.to_string() |> String.trim() |> String.downcase()

  defp hash(sal, password), do: :crypto.hash(:sha256, sal <> password) |> Base.encode16()

  defp validar_username(username) do
    limpio = clave(username)

    if Regex.match?(~r/^[a-z0-9_.\-]{3,30}$/, limpio),
      do: {:ok, limpio},
      else:
        {:error,
         "El nombre de usuario debe tener entre 3 y 30 caracteres, sin espacios (letras, números, punto, guion o guion bajo), por ejemplo: joan.vargas. El nombre completo va en su propio campo"}
  end

  defp validar_password(password) when is_binary(password) and byte_size(password) >= 4, do: :ok
  defp validar_password(_password), do: {:error, "La contraseña debe tener al menos 4 caracteres"}

  defp nombre_completo(nombre, username) do
    case nombre |> Kernel.to_string() |> String.trim() do
      "" -> username
      limpio -> limpio
    end
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
