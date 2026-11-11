# Muestra y exporta la base de datos de códigos (Emergencias.Dominio.Codigos).
#
#   elixir codigos.exs            -> todas las tablas en pantalla + CODIGOS.md + datos/codigos.csv
#   elixir codigos.exs especie    -> solo una tabla en pantalla
#
# CODIGOS.md se lee en VS Code u Obsidian; datos/codigos.csv se abre en Excel (separador ;).

Code.require_file("cargar.exs", __DIR__)
Cargar.codigo()

defmodule ScriptCodigos do
  alias Emergencias.Dominio.Codigos

  def main([]) do
    Util2.mostrar(Codigos.formato_todas(), :mensaje)
    File.write!("CODIGOS.md", Codigos.markdown())
    File.write!("datos/codigos.csv", Codigos.csv())
    Util2.mostrar("\nGenerados: CODIGOS.md y datos/codigos.csv", :mensaje)
  end

  def main([tabla | _]) do
    case Codigos.formato_tabla(String.downcase(tabla)) do
      {:ok, texto} -> Util2.mostrar(texto, :mensaje)
      {:error, motivo} -> Util2.mostrar(motivo, :error)
    end
  end
end

ScriptCodigos.main(System.argv())
