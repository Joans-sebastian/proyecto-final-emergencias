defmodule Emergencias.Demostracion do
  @moduledoc """
  Demostración automática del flujo del enunciado, con varios usuarios en
  paralelo. Usa la carpeta `datos_demo/` (se borra al empezar) para no tocar `datos/`.

      mix run demostracion.exs
  """

  alias Emergencias.{Sesion, Sesiones}
  alias Emergencias.Estado.GestorNecesidades

  @doc "Los pasos de la demostración (el QUÉ). Cada paso está implementado abajo (el CÓMO)."
  def main do
    preparar_datos_limpios()
    u = conectar_usuarios()
    registrar_zonas(u)
    mostrar_permisos(u)
    registrar_necesidades_y_recurso(u)
    conflicto_concurrente(u)
    prueba_de_estres(u)
    atender_por_prioridad(u)
    familiares_y_albergue(u)
    mascotas(u)
    resumen(u)
    supervision(u)
    bitacora(u)
    terminar()
  end

  # ---------------------------------------------------------------------------
  # Pasos
  # ---------------------------------------------------------------------------

  defp preparar_datos_limpios do
    Logger.configure(level: :warning)
    Application.stop(:emergencias)
    Application.put_env(:emergencias, :directorio_datos, "datos_demo")
    File.rm_rf!("datos_demo")
    {:ok, _} = Application.ensure_all_started(:emergencias)
  end

  defp conectar_usuarios do
    titulo("1. Conexión de usuarios (registro automático)")

    usuarios = %{
      admin: conectar(["admin", "admin123", "administrador", "centro"]),
      laura: conectar(["laura", "1234", "coordinador", "centro"]),
      pedro: conectar(["pedro", "1234", "coordinador", "centro"]),
      ana: conectar(["ana", "1234", "ciudadano", "norte"]),
      carlos: conectar(["carlos", "1234", "voluntario", "norte"]),
      maria: conectar(["maria", "1234", "ciudadano", "norte"])
    }

    Util2.mostrar("\nIntento con contraseña incorrecta:", :mensaje)
    mostrar(Sesiones.conectar(["laura", "clave_mala"]))
    usuarios
  end

  defp registrar_zonas(u) do
    titulo("2. Zonas, sectores y puntos de atención (árbol recursivo)")
    ejecutar(u.laura, ~s(registrar_zona centro "Zona Centro" critico 1200))
    ejecutar(u.laura, ~s(registrar_zona sector3 "Sector 3" alto 300 padre=centro))

    ejecutar(
      u.laura,
      ~s(registrar_zona punto3 "Punto de atención sector 3" alto 40 padre=sector3)
    )

    ejecutar(u.laura, ~s(registrar_zona norte "Zona Norte" alto 800))
    ejecutar(u.laura, "listar_zonas")
  end

  defp mostrar_permisos(u) do
    titulo("3. Permisos por rol")
    ejecutar(u.ana, "registrar_recurso R003 agua 10 litros bodega")
  end

  defp registrar_necesidades_y_recurso(u) do
    titulo("4. Necesidades y un recurso compartido")
    ejecutar(u.laura, ~s(registrar_necesidad agua 30 critica centro "Punto de atención sector 3"))
    ejecutar(u.pedro, ~s(registrar_necesidad agua 25 alta centro "Albergue temporal del parque"))
    ejecutar(u.laura, "registrar_recurso R001 agua 50 litros centro_acopio")
  end

  defp conflicto_concurrente(u) do
    titulo("5. CONFLICTO CONCURRENTE: Laura y Pedro asignan AL MISMO TIEMPO (30 + 25 > 50)")

    [{u.laura, "asignar_recurso N001 agua 30"}, {u.pedro, "asignar_recurso N002 agua 25"}]
    |> Enum.map(fn {sesion, linea} ->
      Task.async(fn -> {linea, Sesion.ejecutar(sesion, linea)} end)
    end)
    |> Task.await_many()
    |> Enum.each(fn {linea, resultado} ->
      Util2.mostrar("\n> #{linea}", :mensaje)
      mostrar(resultado)
    end)

    ejecutar(u.laura, "listar_recursos")

    Util2.mostrar(
      "\nNunca se asignan 55 litros: el GestorRecursos procesa un retiro a la vez.",
      :mensaje
    )
  end

  defp prueba_de_estres(u) do
    titulo("6. Prueba de estrés: 30 usuarios piden 5 raciones a la vez y solo hay 100")
    ejecutar(u.laura, "registrar_recurso R002 alimentos 100 raciones centro_acopio")

    sesiones =
      for i <- 1..30 do
        {:ok, pid, _usuario, _mensaje} =
          Sesiones.conectar(["vol#{i}", "1234", "coordinador", "centro"])

        {:ok, _} =
          Sesion.ejecutar(pid, ~s(registrar_necesidad alimentos 5 media centro "Familia #{i}"))

        pid
      end

    exitosas =
      sesiones
      |> Enum.zip(GestorNecesidades.listar(%{"tipo" => "alimentos"}))
      |> Enum.map(fn {pid, n} ->
        Task.async(fn -> Sesion.ejecutar(pid, "asignar_recurso #{n.id} alimentos 5") end)
      end)
      |> Task.await_many()
      |> Enum.count(&match?({:ok, _}, &1))

    Util2.mostrar(
      "Asignaciones confirmadas: #{exitosas} (#{exitosas * 5} raciones) | rechazadas: #{30 - exitosas}",
      :mensaje
    )

    Enum.each(1..30, &Sesiones.desconectar("vol#{&1}"))
    ejecutar(u.laura, "listar_recursos tipo=alimentos")
  end

  defp atender_por_prioridad(u) do
    titulo("7. Prioridad: atender_siguiente atiende primero la más urgente")
    ejecutar(u.laura, "entrada_recurso R001 centro_acopio 40")
    ejecutar(u.laura, "necesidades_pendientes")
    ejecutar(u.laura, "atender_siguiente tipo=agua")
    ejecutar(u.laura, "cerrar_necesidad N001")
    ejecutar(u.laura, "cerrar_necesidad N001")
    ejecutar(u.laura, "asignar_recurso N001 agua 5")
  end

  defp familiares_y_albergue(u) do
    titulo("8. Personas, albergue y mensajes entre familiares")
    ejecutar(u.ana, ~s(reportar_persona 1094 "Andrés López" norte localizada edad=34))
    ejecutar(u.laura, ~s(registrar_albergue A01 "Albergue Norte" norte 150))
    ejecutar(u.carlos, "registrar_ingreso A01 1094")
    ejecutar(u.carlos, "registrar_ingreso A01 1094")

    ejecutar(
      u.maria,
      ~s(enviar_mensaje 1094 "Andrés, estamos bien, te buscamos en el Albergue Norte")
    )

    ejecutar(u.maria, "listar_mensajes 1094")
    ejecutar(u.carlos, "marcar_mensaje M001 entregado")
    ejecutar(u.maria, "historial_persona 1094")
  end

  defp mascotas(u) do
    titulo("9. Mascotas: coincidencias por puntaje")

    ejecutar(
      u.ana,
      ~s(reportar_mascota perdida perro "Luna" negro mediana norte 3001112233 caracteristicas="collar rojo, oreja caída")
    )

    ejecutar(
      u.carlos,
      ~s(reportar_mascota encontrada perro desconocido negro mediana norte 3004445566 caracteristicas="collar rojo, asustada")
    )

    ejecutar(
      u.carlos,
      "reportar_mascota encontrada gato desconocido gris pequena centro 3007778899"
    )

    ejecutar(u.carlos, "buscar_coincidencias")
    ejecutar(u.laura, "confirmar_coincidencia MA001 MA002")
    ejecutar(u.laura, "confirmar_coincidencia MA001 MA002")
  end

  defp resumen(u) do
    titulo("10. Resumen global del coordinador")
    ejecutar(u.laura, "estado_zona centro")
    ejecutar(u.laura, "resumen")
    ejecutar(u.laura, "recursos_criticos")
  end

  defp supervision(u) do
    titulo("11. Supervisión: se cae el GestorRecursos y el Supervisor lo reinicia con sus datos")
    ejecutar(u.admin, "simular_falla recursos")
    ejecutar(u.laura, "listar_recursos")
  end

  defp bitacora(u) do
    titulo("12. Bitácora de actividad")
    # La bitácora escribe con cast; se espera un momento a que termine.
    Process.sleep(100)
    ejecutar(u.admin, "actividad laura n=5")
  end

  defp terminar do
    Enum.each(Sesiones.activas(), &Sesiones.desconectar/1)

    Util2.mostrar(
      "\nDemo terminada. Los archivos de texto generados están en datos_demo/.",
      :mensaje
    )
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp titulo(texto), do: Util2.mostrar("\n=== #{texto} ===", :mensaje)

  defp conectar(argumentos) do
    {:ok, pid, _usuario, mensaje} = Sesiones.conectar(argumentos)
    Util2.mostrar("conectar #{hd(argumentos)} -> #{mensaje}", :mensaje)
    pid
  end

  defp ejecutar(sesion, linea) do
    %{usuario: u} = Sesion.info(sesion)
    Util2.mostrar("\n#{u.username}@#{u.tipo}> #{linea}", :mensaje)
    mostrar(Sesion.ejecutar(sesion, linea))
  end

  defp mostrar({:ok, texto}), do: Util2.mostrar(texto, :mensaje)
  defp mostrar({:error, texto}), do: Util2.mostrar("ERROR: " <> texto, :mensaje)
end
