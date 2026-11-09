defmodule Emergencias.Dominio.Mensaje do
  @moduledoc """
  Mensaje para una persona afectada o su familia (comunicación entre familiares).
  Se identifica por `documento`, el dato de referencia de la persona destinataria.
  Estados: `pendiente` y `entregado`.
  """

  alias Emergencias.Dominio.Comun

  defstruct [
    :id,
    :documento,
    :destinatario,
    :remitente,
    :contenido,
    :fecha,
    :estado,
    :entregado_en
  ]

  @estados ~w(pendiente entregado)

  @doc "Crea un mensaje pendiente."
  def crear(id, documento, destinatario, remitente, contenido) do
    with {:ok, documento} <- Comun.codigo(documento, "Documento del destinatario"),
         {:ok, contenido} <- Comun.requerido(contenido, "El contenido del mensaje") do
      {:ok,
       %__MODULE__{
         id: id,
         documento: documento,
         destinatario: destinatario,
         remitente: remitente,
         contenido: contenido,
         fecha: Comun.ahora(),
         estado: "pendiente"
       }}
    end
  end

  @doc """
  Lee desde teclado un mensaje para un familiar (con `Util2` del curso).
  `usuario` queda como remitente; el gestor completa el nombre del destinatario.
  """
  def ingresar(usuario) do
    Util2.mostrar("\nIngrese los datos del mensaje para el familiar:\n", :mensaje)

    crear(
      nil,
      Util2.ingresar("Documento de la persona destinataria: ", :texto),
      nil,
      usuario,
      Util2.ingresar("Mensaje: ", :texto)
    )
  end

  @doc "Representación del mensaje como texto."
  def to_string(%__MODULE__{} = m) do
    entregado = if m.entregado_en, do: " el #{m.entregado_en}", else: ""

    "#{m.id} | #{m.fecha} | de @#{m.remitente} para #{m.destinatario} (doc #{m.documento}) | " <>
      "#{m.estado}#{entregado} | \"#{m.contenido}\""
  end

  @doc "Marca el mensaje como entregado o pendiente."
  def marcar(%__MODULE__{} = mensaje, estado) do
    with {:ok, estado} <- Comun.en_lista(estado, @estados, "Estado del mensaje") do
      cond do
        estado == mensaje.estado ->
          {:error, "El mensaje #{mensaje.id} ya está #{estado}"}

        estado == "entregado" ->
          {:ok, %{mensaje | estado: "entregado", entregado_en: Comun.ahora()}}

        true ->
          {:ok, %{mensaje | estado: "pendiente", entregado_en: nil}}
      end
    end
  end

  defimpl String.Chars do
    # Permite mostrar el struct con interpolación o con Kernel.to_string/1.
    def to_string(entidad), do: @for.to_string(entidad)
  end
end
