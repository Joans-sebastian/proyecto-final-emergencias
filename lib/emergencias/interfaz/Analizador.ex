defmodule Emergencias.Interfaz.Analizador do
  @moduledoc """
  Convierte una línea escrita por el usuario en `{comando, argumentos, opciones}`.

      iex> Emergencias.Interfaz.Analizador.analizar(~s(registrar_necesidad agua 30 critica centro "Punto de atención" lugar=A01))
      {:ok, "registrar_necesidad", ["agua", "30", "critica", "centro", "Punto de atención"], %{"lugar" => "A01"}}

  - Los textos con espacios van entre comillas dobles.
  - `clave=valor` (sin comillas al inicio) es una opción; el valor también
    puede ir entre comillas: `caracteristicas="collar rojo"`.
  """

  @doc "Analiza una línea. Retorna `{:ok, comando | nil, argumentos, opciones}` o `{:error, motivo}`."
  def analizar(linea) do
    case tokenizar(linea) do
      {:ok, []} ->
        {:ok, nil, [], %{}}

      {:ok, [{comando, _comillas} | resto]} ->
        {argumentos, opciones} = separar(resto, [], %{})
        {:ok, Emergencias.Permisos.canonico(String.downcase(comando)), argumentos, opciones}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc """
  **Recursiva.** Separa la línea en palabras, respetando las comillas. Cada
  palabra queda como `{texto, empieza_con_comillas?}`.
  """
  def tokenizar(linea), do: tokenizar(String.graphemes(linea), "", false, nil, [])

  # Argumentos: caracteres pendientes, palabra actual, ¿dentro de comillas?,
  # cómo empezó la palabra (nil = no hay palabra, :comillas o :normal), palabras listas.
  defp tokenizar([], _palabra, true, _inicio, _palabras),
    do: {:error, "Falta cerrar las comillas"}

  defp tokenizar([], palabra, false, inicio, palabras),
    do: {:ok, Enum.reverse(emitir(palabra, inicio, palabras))}

  defp tokenizar(["\"" | resto], palabra, comillas, inicio, palabras),
    do: tokenizar(resto, palabra, not comillas, inicio || :comillas, palabras)

  defp tokenizar([espacio | resto], palabra, false, inicio, palabras)
       when espacio in [" ", "\t", "\r", "\n"],
       do: tokenizar(resto, "", false, nil, emitir(palabra, inicio, palabras))

  defp tokenizar([caracter | resto], palabra, comillas, inicio, palabras),
    do: tokenizar(resto, palabra <> caracter, comillas, inicio || :normal, palabras)

  defp emitir(_palabra, nil, palabras), do: palabras
  defp emitir(palabra, inicio, palabras), do: [{palabra, inicio == :comillas} | palabras]

  # **Recursiva.** Separa argumentos posicionales de opciones clave=valor.
  defp separar([], argumentos, opciones), do: {Enum.reverse(argumentos), opciones}

  defp separar([{texto, false} | resto], argumentos, opciones) do
    case Regex.run(~r/^([a-z_]+)=(.*)$/s, texto) do
      [_, clave, valor] -> separar(resto, argumentos, Map.put(opciones, clave, valor))
      nil -> separar(resto, [texto | argumentos], opciones)
    end
  end

  defp separar([{texto, true} | resto], argumentos, opciones),
    do: separar(resto, [texto | argumentos], opciones)
end
