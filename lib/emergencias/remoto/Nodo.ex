defmodule Emergencias.Remoto.Nodo do
  @moduledoc """
  Inicia el nodo de Erlang desde el script, como en la guía "Aplicaciones
  distribuidas": `Node.start/2` + `Node.set_cookie/1`.

  - Sin IP se usan **nombres cortos** (`:shortnames`), que sirven en la misma
    máquina: `servidor@EQUIPO`.
  - Con IP se usan **nombres completos** (`:longnames`), para máquinas distintas
    en la misma red: `:"servidor@192.168.1.20"`. Todos los nodos que se conectan
    deben usar el mismo tipo de nombre.
  - La cookie es la del archivo `my_cookie` (se crea con `elixir cookie.exs`) o,
    si no existe, `:emergencias_quindio`. Los nodos solo se conectan si sus
    cookies coinciden.
  - Los puertos de distribución quedan en el rango 9000-9100, para poder
    abrirlos en el firewall junto con el 4369 de EPMD.
  - Si EPMD no está activo, se intenta iniciar con `epmd -daemon`.
  """

  @cookie_fija :emergencias_quindio
  @archivo_cookie "my_cookie"
  @puerto_minimo 9000
  @puerto_maximo 9100

  @doc """
  Inicia este nodo con el nombre `prefijo` (más un sufijo al azar si
  `unico: true`, como los cajeros). `ip` = nil usa nombres cortos.
  Retorna `{:ok, nodo}` o `{:error, mensaje}`.
  """
  def iniciar(prefijo, ip \\ nil, opciones \\ []) do
    if Node.alive?() do
      poner_cookie()
      {:ok, node()}
    else
      nombre = nombre_nodo(prefijo, ip, Keyword.get(opciones, :unico, false))
      tipo = if ip, do: :longnames, else: :shortnames
      fijar_puertos()
      arrancar(nombre, tipo, :primer_intento)
    end
  end

  @doc """
  Nombre del nodo servidor según los argumentos del script.

      iex> Emergencias.Remoto.Nodo.nodo_servidor(["192.168.1.20"])
      :"servidor@192.168.1.20"

      iex> Emergencias.Remoto.Nodo.nodo_servidor(["central@10.0.0.5"])
      :"central@10.0.0.5"
  """
  def nodo_servidor([]), do: String.to_atom("servidor@#{equipo()}")

  def nodo_servidor([direccion | _]) do
    if String.contains?(direccion, "@"),
      do: String.to_atom(direccion),
      else: String.to_atom("servidor@#{direccion}")
  end

  @doc """
  IP con la que el cliente se anuncia según los argumentos del script:

  - sin argumentos: nil (servidor en este equipo, nombres cortos);
  - `[servidor, ip]`: la IP que escribió el usuario;
  - `[servidor]`: la primera IPv4 de la red local de este equipo.

      iex> Emergencias.Remoto.Nodo.ip_cliente([])
      nil

      iex> Emergencias.Remoto.Nodo.ip_cliente(["192.168.1.20", "192.168.1.21"])
      "192.168.1.21"
  """
  def ip_cliente([]), do: nil
  def ip_cliente([_servidor, ip | _]), do: ip

  def ip_cliente([servidor]) do
    if usa_nombre_corto?(servidor), do: nil, else: ip_local()
  end

  @doc "Nombre de red de este equipo (la parte después de @ en los nombres cortos)."
  def equipo do
    {:ok, nombre} = :inet.gethostname()
    nombre |> List.to_string() |> String.split(".") |> hd()
  end

  @doc "Primera IPv4 de la red local (no 127.x ni 169.254.x), o \"127.0.0.1\" si no hay red."
  def ip_local do
    {:ok, interfaces} = :inet.getifaddrs()

    interfaces
    |> Enum.flat_map(fn {_nombre, datos} -> Keyword.get_values(datos, :addr) end)
    |> Enum.find(&ip_de_red?/1)
    |> case do
      nil -> "127.0.0.1"
      ip -> ip |> :inet.ntoa() |> List.to_string()
    end
  end

  @doc "Cookie que usan todos los nodos del proyecto."
  def cookie do
    case File.read(@archivo_cookie) do
      {:ok, texto} when byte_size(texto) > 0 -> texto |> String.trim() |> String.to_atom()
      _ -> @cookie_fija
    end
  end

  @doc "Mensaje para el usuario cuando Node.start/2 falla."
  def mensaje_sin_nodo do
    "No se pudo iniciar el nodo. Verifique que epmd esté corriendo (epmd -daemon) " <>
      "y que el nombre no esté en uso (epmd -names)."
  end

  # Si EPMD no está activo, Node.start/2 falla: se inicia EPMD y se intenta otra vez.
  defp arrancar(nombre, tipo, intento) do
    case Node.start(nombre, tipo) do
      {:ok, _} ->
        poner_cookie()
        {:ok, node()}

      {:error, _motivo} when intento == :primer_intento ->
        iniciar_epmd()
        arrancar(nombre, tipo, :segundo_intento)

      {:error, _motivo} ->
        {:error, mensaje_sin_nodo()}
    end
  end

  defp poner_cookie, do: Node.set_cookie(cookie())

  defp nombre_nodo(prefijo, ip, unico) do
    base = if unico, do: "#{prefijo}_#{sufijo()}", else: "#{prefijo}"
    if ip, do: String.to_atom("#{base}@#{ip}"), else: String.to_atom(base)
  end

  # Cada cliente necesita un nombre de nodo distinto, porque puede haber varios a la vez.
  defp sufijo, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  defp fijar_puertos do
    :application.set_env(:kernel, :inet_dist_listen_min, @puerto_minimo)
    :application.set_env(:kernel, :inet_dist_listen_max, @puerto_maximo)
  end

  defp iniciar_epmd do
    case ruta_epmd() do
      nil ->
        :ok

      epmd ->
        System.cmd(epmd, ["-daemon"], stderr_to_stdout: true)
        Process.sleep(500)
        if not epmd_activo?(epmd), do: lanzar_epmd(epmd)
    end
  end

  defp epmd_activo?(epmd) do
    {_salida, codigo} = System.cmd(epmd, ["-names"], stderr_to_stdout: true)
    codigo == 0
  end

  # Plan B: en algunos equipos `epmd -daemon` no queda activo; se lanza directamente.
  defp lanzar_epmd(epmd) do
    Port.open({:spawn_executable, epmd}, [:nouse_stdio])
    Process.sleep(1000)
  end

  # epmd viene con Erlang, pero en Windows no siempre está en el PATH.
  defp ruta_epmd do
    System.find_executable("epmd") ||
      :code.root_dir()
      |> List.to_string()
      |> Path.join("erts-*/bin/epmd*")
      |> Path.wildcard()
      |> List.first()
  end

  defp usa_nombre_corto?(servidor) do
    destino = servidor |> String.split("@") |> List.last()
    destino in [equipo(), "localhost"]
  end

  defp ip_de_red?({127, _, _, _}), do: false
  defp ip_de_red?({169, 254, _, _}), do: false
  defp ip_de_red?({_, _, _, _}), do: true
  defp ip_de_red?(_ipv6), do: false
end
