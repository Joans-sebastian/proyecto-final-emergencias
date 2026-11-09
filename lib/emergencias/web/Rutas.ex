defmodule Emergencias.Web.Rutas do
  @moduledoc """
  Qué responde la página web en cada dirección. No usa la red, así que se
  puede probar directamente.

  | Método y ruta         | Cuerpo (JSON)                              | Respuesta                                   |
  |-----------------------|--------------------------------------------|---------------------------------------------|
  | `GET /`               | —                                          | la página (`priv/web/index.html`)           |
  | `POST /api/conectar`  | `usuario, contrasena, tipo, zona, nombre`  | `ok, token, usuario, nombre, tipo, mensaje` |
  | `POST /api/acciones`  | `token`                                    | `ok, grupos` (acciones que permite el rol)  |
  | `POST /api/accion`    | `token, comando, valores`                  | `ok, texto, linea`                          |
  | `POST /api/comando`   | `token, linea`                             | `ok, texto`                                 |
  | `POST /api/salir`     | `token`                                    | `ok, texto`                                 |
  """

  alias Emergencias.{Sesion, Sesiones}
  alias Emergencias.Interfaz.Acciones
  alias Emergencias.Web.Fichas

  @json "application/json; charset=utf-8"
  @vencida "Sesión vencida. Vuelva a iniciar sesión."

  @doc "Retorna `{estado_http, tipo_de_contenido, contenido}`."
  def responder("GET", "/", _cuerpo), do: {"200 OK", "text/html; charset=utf-8", pagina()}

  def responder("POST", "/api/conectar", cuerpo) do
    with {:ok, d} <- decodificar(cuerpo),
         formulario = [d["usuario"], d["contrasena"], d["tipo"], d["zona"], d["nombre"]],
         {argumentos, opciones} = Sesiones.desde_formulario(formulario),
         {:ok, _sesion, usuario, mensaje} <- Sesiones.conectar(argumentos, opciones) do
      json(%{
        ok: true,
        token: Fichas.crear(usuario.username),
        usuario: usuario.username,
        nombre: usuario.nombre,
        tipo: usuario.tipo,
        zona: usuario.zona,
        mensaje: mensaje
      })
    else
      error -> json_error(error)
    end
  end

  def responder("POST", "/api/acciones", cuerpo) do
    with {:ok, d} <- decodificar(cuerpo),
         {:ok, sesion} <- sesion_de(d["token"]) do
      %{usuario: usuario} = Sesion.info(sesion)

      grupos =
        for {grupo, acciones} <- Acciones.grupos_permitidos(usuario),
            do: %{grupo: grupo, acciones: acciones}

      json(%{ok: true, grupos: grupos})
    else
      error -> json_error(error)
    end
  end

  def responder("POST", "/api/accion", cuerpo) do
    with {:ok, d} <- decodificar(cuerpo),
         {:ok, sesion} <- sesion_de(d["token"]),
         {:ok, accion} <- buscar_accion(d["comando"]),
         {:ok, linea} <- Acciones.armar(accion, Enum.map(d["valores"] || [], &to_string/1)),
         {:ok, texto} <- Sesion.ejecutar(sesion, linea) do
      json(%{ok: true, texto: texto, linea: linea})
    else
      error -> json_error(error)
    end
  end

  def responder("POST", "/api/comando", cuerpo) do
    with {:ok, d} <- decodificar(cuerpo),
         {:ok, sesion} <- sesion_de(d["token"]),
         {:ok, texto} <- Sesion.ejecutar(sesion, d["linea"] || "") do
      json(%{ok: true, texto: texto})
    else
      error -> json_error(error)
    end
  end

  def responder("POST", "/api/salir", cuerpo) do
    with {:ok, d} <- decodificar(cuerpo),
         {:ok, username} <- usuario_de(d["token"]) do
      Fichas.borrar(d["token"])
      json(%{ok: true, texto: elem(Sesiones.desconectar(username), 1)})
    else
      error -> json_error(error)
    end
  end

  def responder(_metodo, _ruta, _cuerpo),
    do: {"404 Not Found", "text/plain; charset=utf-8", "No encontrado"}

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp pagina, do: :emergencias |> :code.priv_dir() |> Path.join("web/index.html") |> File.read!()

  defp decodificar(cuerpo) do
    case JSON.decode(cuerpo) do
      {:ok, datos} when is_map(datos) -> {:ok, datos}
      _ -> {:error, "Petición inválida"}
    end
  end

  defp buscar_accion(comando) do
    case Acciones.buscar(comando) do
      {:ok, accion} -> {:ok, accion}
      :error -> {:error, "Acción desconocida"}
    end
  end

  defp usuario_de(token) when is_binary(token) do
    case Fichas.usuario(token) do
      {:ok, username} -> {:ok, username}
      :error -> {:error, @vencida}
    end
  end

  defp usuario_de(_token), do: {:error, @vencida}

  defp sesion_de(token) do
    with {:ok, username} <- usuario_de(token) do
      case Registry.lookup(Emergencias.RegistroSesiones, username) do
        [{pid, _}] -> {:ok, pid}
        [] -> {:error, @vencida}
      end
    end
  end

  defp json(mapa), do: {"200 OK", @json, JSON.encode!(mapa)}
  defp json_error({:error, motivo}), do: json(%{ok: false, texto: motivo})
end
