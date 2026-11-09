defmodule Emergencias.Web.Servidor do
  @moduledoc """
  Servidor HTTP mínimo con `:gen_tcp` (solo acepta conexiones de este equipo).

  Un proceso escucha y, por cada conexión, inicia **otro proceso** que lee la
  petición, la responde con `Web.Rutas` y cierra. Así varios navegadores se
  atienden al mismo tiempo.
  """

  # :transient = el Supervisor lo reinicia si falla, pero no si termina normalmente
  # (por ejemplo, cuando el puerto ya está ocupado y no tiene sentido reintentar).
  use Task, restart: :transient

  require Logger

  alias Emergencias.Web.Rutas

  @opciones [:binary, packet: :raw, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]

  @doc "Inicia el proceso que escucha en `puerto`."
  def start_link(puerto), do: Task.start_link(__MODULE__, :escuchar, [puerto])

  @doc "Indica si el puerto está libre en este equipo."
  def puerto_libre?(puerto) do
    case :gen_tcp.listen(puerto, @opciones) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _motivo} ->
        false
    end
  end

  @doc false
  def escuchar(puerto) do
    case :gen_tcp.listen(puerto, @opciones) do
      {:ok, socket} ->
        aceptar(socket)

      {:error, motivo} ->
        Logger.error("La página web no pudo usar el puerto #{puerto}: #{inspect(motivo)}")
    end
  end

  # **Recursiva.** Acepta una conexión, la entrega a un proceso nuevo y espera la siguiente.
  defp aceptar(socket) do
    {:ok, cliente} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.start(fn -> atender(cliente) end)
    :gen_tcp.controlling_process(cliente, pid)
    aceptar(socket)
  end

  defp atender(cliente) do
    case leer(cliente, "") do
      {:ok, metodo, ruta, cuerpo} ->
        {estado, tipo, contenido} = Rutas.responder(metodo, ruta, cuerpo)
        :gen_tcp.send(cliente, respuesta(estado, tipo, contenido))

      :error ->
        :ok
    end

    :gen_tcp.close(cliente)
  end

  # **Recursiva.** Junta los datos hasta tener los encabezados y todo el cuerpo.
  defp leer(cliente, datos) do
    case String.split(datos, "\r\n\r\n", parts: 2) do
      [cabecera, cuerpo] ->
        {metodo, ruta, largo} = analizar(cabecera)

        if byte_size(cuerpo) >= largo,
          do: {:ok, metodo, ruta, binary_part(cuerpo, 0, largo)},
          else: recibir_mas(cliente, datos)

      [_incompleto] ->
        recibir_mas(cliente, datos)
    end
  end

  defp recibir_mas(cliente, datos) do
    case :gen_tcp.recv(cliente, 0, 5_000) do
      {:ok, nuevos} -> leer(cliente, datos <> nuevos)
      {:error, _motivo} -> :error
    end
  end

  defp analizar(cabecera) do
    [linea | encabezados] = String.split(cabecera, "\r\n")
    [metodo, ruta | _] = String.split(linea, " ")

    largo =
      Enum.find_value(encabezados, 0, fn encabezado ->
        case String.split(encabezado, ":", parts: 2) do
          [nombre, valor] ->
            if String.downcase(nombre) == "content-length",
              do: String.to_integer(String.trim(valor))

          _ ->
            nil
        end
      end)

    {metodo, ruta, largo}
  end

  defp respuesta(estado, tipo, contenido) do
    [
      "HTTP/1.1 #{estado}\r\n",
      "Content-Type: #{tipo}\r\n",
      "Content-Length: #{byte_size(contenido)}\r\n",
      "Connection: close\r\n\r\n",
      contenido
    ]
  end
end
