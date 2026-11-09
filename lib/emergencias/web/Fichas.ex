defmodule Emergencias.Web.Fichas do
  @moduledoc """
  Agent que relaciona cada navegador (un token aleatorio) con el usuario
  conectado. El navegador envía su token en cada petición.
  """

  use Agent

  def start_link(_opciones), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Crea un token para `username`."
  def crear(username) do
    token = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    Agent.update(__MODULE__, &Map.put(&1, token, username))
    token
  end

  @doc "Usuario dueño del token. Retorna `{:ok, username}` o `:error`."
  def usuario(token), do: Agent.get(__MODULE__, &Map.fetch(&1, token))

  @doc "Elimina el token (al cerrar sesión)."
  def borrar(token), do: Agent.update(__MODULE__, &Map.delete(&1, token))
end
