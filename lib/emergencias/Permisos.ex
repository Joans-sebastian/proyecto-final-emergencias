defmodule Emergencias.Permisos do
  @moduledoc """
  Catálogo de comandos con el **rol mínimo** que puede ejecutarlos.

  Los roles son acumulativos: 1 ciudadano < 2 voluntario < 3 coordinador <
  4 administrador. Un coordinador puede hacer todo lo de un voluntario, etc.
  """

  alias Emergencias.Dominio.Usuario

  # {comando, nivel mínimo, uso, descripción, grupo}
  @comandos [
    {"conectar", 0, "conectar usuario contraseña [tipo] [zona] [nombre=\"Nombre completo\"]",
     "Conecta (y registra si no existe)", "Sesión"},
    {"desconectar", 0, "desconectar", "Cierra la sesión", "Sesión"},
    {"ayuda", 1, "ayuda [comando]", "Muestra la ayuda", "Sesión"},
    {"quien_soy", 1, "quien_soy", "Muestra su usuario y rol", "Sesión"},
    {"actividad", 1, "actividad [usuario] [n=20]",
     "Actividad registrada (la suya; el administrador puede ver la de cualquiera)", "Sesión"},
    {"sesiones", 3, "sesiones", "Usuarios conectados en este momento", "Sesión"},
    {"listar_usuarios", 4, "listar_usuarios", "Usuarios registrados", "Sesión"},
    {"registrar_usuario", 4, "registrar_usuario usuario contraseña tipo zona [nombre=\"..\"]",
     "Crea un usuario con el rol indicado", "Sesión"},
    {"registrar_zona", 3, "registrar_zona codigo nombre nivel [personas] [padre=codigo]",
     "Registra zona; con padre= registra sector (dentro de zona) o punto (dentro de sector)",
     "Zonas"},
    {"actualizar_zona", 3, "actualizar_zona codigo [nivel=..] [personas=..]",
     "Actualiza nivel o personas afectadas", "Zonas"},
    {"listar_zonas", 1, "listar_zonas", "Árbol de zonas, sectores y puntos", "Zonas"},
    {"estado_zona", 1, "estado_zona codigo",
     "Estado y estadísticas acumuladas de una zona y sus sectores", "Zonas"},
    {"registrar_necesidad", 1,
     "registrar_necesidad tipo cantidad prioridad zona descripcion [lugar=codigo]",
     "Registra una necesidad", "Necesidades"},
    {"listar_necesidades", 1, "listar_necesidades [zona=..] [tipo=..] [prioridad=..] [estado=..]",
     "Lista necesidades ordenadas por prioridad", "Necesidades"},
    {"necesidades_pendientes", 1, "necesidades_pendientes",
     "Necesidades pendientes por prioridad", "Necesidades"},
    {"asignar_recurso", 3, "asignar_recurso id_necesidad tipo|codigo_recurso cantidad",
     "Asigna recursos a una necesidad", "Necesidades"},
    {"atender_siguiente", 3, "atender_siguiente [tipo=..]",
     "Atiende la necesidad pendiente más urgente que alcance a cubrir el inventario",
     "Necesidades"},
    {"iniciar_atencion", 2, "iniciar_atencion id_necesidad", "asignada -> en_atencion",
     "Necesidades"},
    {"cerrar_necesidad", 2, "cerrar_necesidad id_necesidad", "Marca la necesidad como atendida",
     "Necesidades"},
    {"cancelar_necesidad", 3, "cancelar_necesidad id_necesidad",
     "Cancela (y devuelve los recursos asignados)", "Necesidades"},
    {"registrar_recurso", 3,
     "registrar_recurso codigo nombre cantidad unidad ubicacion [categoria=..] [zona=..]",
     "Registra un recurso en un centro de apoyo", "Recursos"},
    {"entrada_recurso", 3, "entrada_recurso codigo ubicacion cantidad [motivo=\"..\"]",
     "Entrada de inventario", "Recursos"},
    {"salida_recurso", 3, "salida_recurso codigo ubicacion cantidad [motivo=\"..\"]",
     "Salida de inventario", "Recursos"},
    {"transferir_recurso", 3, "transferir_recurso codigo origen destino cantidad",
     "Transfiere entre centros de apoyo", "Recursos"},
    {"listar_recursos", 1, "listar_recursos [tipo=..] [zona=..] [ubicacion=..]",
     "Disponibilidad de recursos", "Recursos"},
    {"historial_recurso", 2, "historial_recurso codigo", "Historial de movimientos", "Recursos"},
    {"recursos_criticos", 3, "recursos_criticos [umbral=20]",
     "Recursos escasos o que no alcanzan para las necesidades pendientes", "Recursos"},
    {"reportar_persona", 1,
     "reportar_persona documento nombre zona|barrio estado [edad=..] [tipo_doc=CC] [barrio=B01] [direccion=\"..\"]",
     "Registra una persona afectada", "Familiares"},
    {"actualizar_persona", 2, "actualizar_persona documento estado [detalle=\"..\"]",
     "Cambia el estado de una persona", "Familiares"},
    {"buscar_persona", 1,
     "buscar_persona documento | buscar_persona [nombre=..] [zona=..] [estado=..] [barrio=..]",
     "Busca personas", "Familiares"},
    {"historial_persona", 1, "historial_persona documento", "Historial de estados de una persona",
     "Familiares"},
    {"enviar_mensaje", 1, "enviar_mensaje documento \"contenido\"",
     "Deja un mensaje para la persona", "Familiares"},
    {"listar_mensajes", 1, "listar_mensajes documento", "Mensajes para la persona", "Familiares"},
    {"marcar_mensaje", 2, "marcar_mensaje id_mensaje entregado|pendiente", "Marca un mensaje",
     "Familiares"},
    {"reportar_mascota", 1,
     "reportar_mascota tipo especie nombre color tamaño zona|barrio contacto [caracteristicas=\"..\"] [barrio=B01] [direccion=\"..\"]",
     "Reporta una mascota perdida o encontrada", "Mascotas"},
    {"listar_mascotas", 1,
     "listar_mascotas [especie=..] [zona=..] [estado=..] [tipo=..] [barrio=..]",
     "Lista reportes de mascotas", "Mascotas"},
    {"buscar_coincidencias", 2, "buscar_coincidencias",
     "Calcula posibles coincidencias perdida/encontrada", "Mascotas"},
    {"confirmar_coincidencia", 3, "confirmar_coincidencia id_perdida id_encontrada",
     "Confirma la coincidencia y cierra ambos", "Mascotas"},
    {"registrar_albergue", 3, "registrar_albergue codigo nombre zona capacidad",
     "Registra un albergue", "Albergues"},
    {"consultar_albergue", 1, "consultar_albergue codigo",
     "Ocupación, cupos, recursos y necesidades del albergue", "Albergues"},
    {"listar_albergues", 1, "listar_albergues", "Lista de albergues", "Albergues"},
    {"reporte_albergues", 2, "reporte_albergues", "Albergues de mayor a menor ocupación",
     "Albergues"},
    {"registrar_ingreso", 2, "registrar_ingreso codigo_albergue documento",
     "Ingreso de una persona", "Albergues"},
    {"registrar_salida", 2, "registrar_salida codigo_albergue documento", "Salida de una persona",
     "Albergues"},
    {"resumen", 3, "resumen", "Resumen global de la emergencia", "Reportes"},
    {"simular_falla", 4, "simular_falla gestor",
     "Simula la falla de un gestor para mostrar la supervisión", "Reportes"},
    {"codigos", 1, "codigos [tabla|todas]",
     "Base de datos de códigos para escribir los registros (ES01=perro, PE3=localizada...)",
     "Códigos"},
    {"registrar_barrio", 1, "registrar_barrio \"nombre del barrio\" zona",
     "Registra un barrio a mano con su zona; recibe B01, el siguiente B02 y así", "Códigos"}
    # Espacio para los comandos de los módulos que se agreguen más adelante:
    # {"nuevo_comando", nivel, "uso", "descripción", "Grupo"},
  ]

  @tabla Map.new(@comandos, fn {comando, nivel, uso, descripcion, grupo} ->
           {comando, %{nivel: nivel, uso: uso, descripcion: descripcion, grupo: grupo}}
         end)

  # Nombres en inglés del enunciado (1.4.10), aceptados como alias de los comandos en español.
  @alias_ingles %{
    "connect" => "conectar",
    "disconnect" => "desconectar",
    "help" => "ayuda",
    "register_zone" => "registrar_zona",
    "register_need" => "registrar_necesidad",
    "list_needs" => "listar_necesidades",
    "assign_resource" => "asignar_recurso",
    "register_resource" => "registrar_recurso",
    "list_resources" => "listar_recursos",
    "transfer_resource" => "transferir_recurso",
    "report_person" => "reportar_persona",
    "find_person" => "buscar_persona",
    "send_family_message" => "enviar_mensaje",
    "list_family_messages" => "listar_mensajes",
    "report_pet" => "reportar_mascota",
    "match_pets" => "buscar_coincidencias",
    "register_shelter" => "registrar_albergue",
    "check_shelter" => "consultar_albergue",
    "register_entry" => "registrar_ingreso",
    "register_exit" => "registrar_salida",
    "summary" => "resumen",
    "critical_resources" => "recursos_criticos",
    "pending_needs" => "necesidades_pendientes",
    "codes" => "codigos"
  }

  @doc "Nombre en español de un comando (acepta también los nombres en inglés del enunciado)."
  def canonico(comando), do: Map.get(@alias_ingles, comando, comando)

  @doc "Indica si el comando existe."
  def existe?(comando), do: Map.has_key?(@tabla, comando)
  def permitido?(usuario, comando), do: Usuario.nivel(usuario) >= @tabla[comando].nivel
  def rol_minimo(comando), do: Usuario.tipo_de_nivel(@tabla[comando].nivel) || "cualquiera"
  def uso(comando), do: @tabla[comando].uso

  @doc "Ayuda con los comandos que puede usar `usuario` (nil = antes de conectarse)."
  def ayuda(usuario) do
    nivel = if usuario, do: Usuario.nivel(usuario), else: 0

    lineas =
      @comandos
      |> Enum.filter(fn {_c, minimo, _u, _d, _g} -> minimo <= nivel end)
      |> Enum.chunk_by(fn {_c, _n, _u, _d, grupo} -> grupo end)
      |> Enum.flat_map(fn [{_, _, _, _, grupo} | _] = grupo_comandos ->
        [
          "",
          "#{grupo}:"
          | Enum.map(grupo_comandos, fn {_c, _n, uso, descripcion, _g} ->
              "  #{uso}\n      #{descripcion}"
            end)
        ]
      end)

    pie =
      if usuario,
        do: [
          "",
          "Escriba exit para salir. Textos con espacios entre comillas: \"Albergue Norte\"."
        ],
        else: ["", "Conéctese primero. Ejemplo: conectar laura 1234 coordinador centro"]

    Enum.join(
      [
        "Comandos disponibles" <> if(usuario, do: " para el rol #{usuario.tipo}", else: "")
        | lineas
      ] ++ pie,
      "\n"
    )
  end

  @doc "Ayuda de un solo comando."
  def ayuda_comando(comando) do
    case Map.fetch(@tabla, String.downcase(comando)) do
      {:ok, info} ->
        {:ok, "#{info.uso}\n  #{info.descripcion}\n  Rol mínimo: #{rol_minimo(comando)}"}

      :error ->
        {:error, "Comando desconocido '#{comando}'"}
    end
  end
end
