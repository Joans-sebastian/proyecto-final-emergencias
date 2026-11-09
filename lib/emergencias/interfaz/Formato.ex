defmodule Emergencias.Interfaz.Formato do
  @moduledoc """
  Formato de salida para la consola (funciones puras). Cada entidad tiene su
  propio `to_string/1`; aquí quedan los formatos que combinan varias cosas:
  listas, movimientos, historiales, coincidencias y el resumen global.
  """

  alias Emergencias.Dominio.{Albergue, Recurso, Zona}

  @doc "Lista con título, una línea por elemento (usa `Util2.convertir_coleccion_mensaje/2`)."
  def lista(titulo, [], _formato), do: "#{titulo}: (sin resultados)"

  def lista(titulo, elementos, formato) do
    lineas = Util2.convertir_coleccion_mensaje(elementos, &"  #{formato.(&1)}")
    Enum.join(["#{titulo} (#{length(elementos)}):" | lineas], "\n")
  end

  @doc "Movimiento de inventario."
  def movimiento(m) do
    destino = if m["destino"], do: " -> #{m["destino"]}", else: ""
    detalle = if m["detalle"] in [nil, ""], do: "", else: " (#{m["detalle"]})"

    "#{m["fecha"]} | #{m["tipo"]} | #{m["cantidad"]} | #{m["ubicacion"]}#{destino}#{detalle} | #{m["usuario"]}"
  end

  @doc "Partes retiradas del inventario para una necesidad."
  def partes(partes),
    do:
      Enum.map_join(partes, ", ", fn p ->
        "#{p["cantidad"]} de #{p["codigo"]} en #{p["ubicacion"]}"
      end)

  @doc "Evento de un historial de estados."
  def evento(e) do
    desde = if e["de"], do: "#{e["de"]} -> ", else: ""
    detalle = if e["detalle"] in [nil, ""], do: "", else: " (#{e["detalle"]})"
    "#{e["fecha"]} | #{desde}#{e["a"]}#{detalle} | #{e["usuario"]}"
  end

  @doc "Posible coincidencia entre dos reportes de mascotas."
  def pareja(p) do
    "#{p.perdida.id} (perdida) <-> #{p.encontrada.id} (encontrada) | puntaje #{p.puntaje}/100 | " <>
      Enum.join(p.razones, ", ")
  end

  @doc "Árbol completo de zonas."
  def zonas([]), do: "No hay zonas registradas"
  def zonas(arboles), do: Enum.map_join(arboles, "\n", &(&1 |> Zona.lineas() |> Enum.join("\n")))

  @doc "Estadísticas acumuladas de una zona."
  def estadisticas(e) do
    "#{e.personas} personas afectadas (acumulado), #{e.sectores} sectores, " <>
      "#{e.puntos} puntos de atención, nivel más grave: #{e.nivel_maximo}"
  end

  @doc "Conteo `[{clave, n}]` como texto."
  def conteo([]), do: "ninguno"
  def conteo(pares), do: Enum.map_join(pares, ", ", fn {clave, n} -> "#{clave}: #{n}" end)

  @doc "Resumen global de la emergencia (datos de `Servicios.resumen/0`)."
  def resumen(r) do
    zonas =
      Enum.map(r.zonas, fn {nodo, e} ->
        "  #{nodo.codigo} (#{nodo.nombre}): " <> estadisticas(e)
      end)

    recursos = Enum.map(r.recursos, &("  " <> Recurso.to_string(&1)))
    albergues = Enum.map(r.albergues, &("  " <> Albergue.to_string(&1)))
    sesiones = if r.sesiones == [], do: "ninguno", else: Enum.join(r.sesiones, ", ")

    Enum.join(
      ["=================== RESUMEN GLOBAL DE LA EMERGENCIA ==================="] ++
        ["Zonas (#{length(r.zonas)}):" | o_ninguno(zonas)] ++
        ["Recursos restantes (#{length(r.recursos)}):" | o_ninguno(recursos)] ++
        [
          "Necesidades por estado: #{conteo(r.necesidades_por_estado)}",
          "Necesidades pendientes por prioridad: #{conteo(r.pendientes_por_prioridad)}",
          "Personas por estado: #{conteo(r.personas_por_estado)}",
          "Mensajes a familiares: #{conteo(r.mensajes_por_estado)}",
          "Reportes de mascotas: #{conteo(r.mascotas_por_estado)}",
          "Albergues (#{length(r.albergues)}), ocupación total #{r.ocupacion_total}/#{r.capacidad_total}:"
          | o_ninguno(albergues)
        ] ++
        ["Usuarios conectados: #{sesiones}", String.duplicate("=", 71)],
      "\n"
    )
  end

  defp o_ninguno([]), do: ["  ninguno"]
  defp o_ninguno(lineas), do: lineas
end
