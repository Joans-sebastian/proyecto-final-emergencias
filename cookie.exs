# Genera una cookie segura para que los nodos se puedan conectar (como cookie.exs de clase).
#
#   elixir cookie.exs        -> crea el archivo my_cookie en la carpeta del proyecto
#
# Si my_cookie existe, el servidor y los clientes usan esa cookie; si no, usan
# la cookie fija :emergencias_quindio. Copie my_cookie a todas las máquinas que
# se van a conectar: si las cookies no coinciden, Node.connect/1 devuelve false.

defmodule Cookie do
  @longitud_llave 128
  @archivo Path.join(__DIR__, "my_cookie")

  def main do
    llave = :crypto.strong_rand_bytes(@longitud_llave) |> Base.encode64()
    File.write!(@archivo, llave)
    IO.puts("Cookie guardada en #{@archivo}. Cópiela a las demás máquinas.")
  end
end

Cookie.main()
