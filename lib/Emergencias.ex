defmodule Emergencias do
  @moduledoc """
  Sistema distribuido de coordinación y gestión de emergencias
  (proyecto final de Programación III).

  `main/1` decide **qué** se ejecuta; **cómo** se hace cada modo está en su módulo:

  | Script                 | Modo        | Módulo                       |
  |------------------------|-------------|------------------------------|
  | `consola.exs`          | consola     | `Emergencias.Interfaz.Consola`   |
  | `consola.exs archivo`  | archivo     | `Emergencias.Interfaz.Consola`   |
  | `ventanas.exs`         | ventanas    | `Emergencias.Interfaz.Grafica`   |
  | `web.exs`              | web         | `Emergencias.Web`            |
  | `demostracion.exs`             | demostracion | `Emergencias.Demostracion`           |
  | `servidor.exs`         | servidor    | `Emergencias.Distribuido`    |
  | `cliente.exs`          | cliente     | `Emergencias.Distribuido`    |
  | `cliente_remoto.exs`   | (directo)   | `Emergencias.Remoto.ClienteRemoto` |
  """

  alias Emergencias.{Demostracion, Distribuido, Web}
  alias Emergencias.Interfaz.{Consola, Grafica}

  @doc """
  Punto de entrada del sistema según los argumentos.

      Emergencias.main(["consola"])
      Emergencias.main(["archivo", "ejemplos/flujo.txt"])
      Emergencias.main(["demostracion"])
  """
  def main(argumentos) do
    case argumentos do
      ["consola"] -> Consola.main()
      ["ventanas"] -> Grafica.main()
      ["web" | puerto] -> Web.main(puerto)
      ["archivo", ruta] -> Consola.ejecutar_archivo(ruta)
      ["demostracion"] -> Demostracion.main()
      ["servidor" | direccion] -> Distribuido.servidor(direccion)
      ["cliente" | servidor] -> Distribuido.cliente(servidor)
      _ -> Util2.mostrar("Modo desconocido: #{inspect(argumentos)}", :error)
    end
  end

  @doc "Conecta un usuario desde `iex -S mix`. Retorna `{:ok, sesion, usuario, mensaje}`."
  def conectar(usuario, contrasena, tipo \\ nil, zona \\ nil) do
    Emergencias.Sesiones.conectar(Enum.reject([usuario, contrasena, tipo, zona], &is_nil/1), %{})
  end

  @doc "Ejecuta un comando en una sesión. Retorna `{:ok, texto}` o `{:error, texto}`."
  def ejecutar(sesion, linea), do: Emergencias.Sesion.ejecutar(sesion, linea)
end
