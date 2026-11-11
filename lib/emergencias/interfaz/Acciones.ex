defmodule Emergencias.Interfaz.Acciones do
  @moduledoc """
  Catálogo de acciones que muestran las interfaces gráficas (ventanas
  emergentes y página web), agrupadas por sección. Cada acción se convierte en
  una línea de comando y se ejecuta en la sesión del usuario, igual que en la consola.

  Una acción es un mapa con `texto`, `comando`, `campos` (obligatorios, en
  orden) y `opcionales` (`clave=valor`). Un campo puede tener `opciones`
  (lista cerrada) u `oculto: true` (contraseña).

  Con códigos: `{:codigos, tabla}` = lista cerrada; `{:sugerir, tabla}` = lista
  donde también se puede escribir.
  """

  alias Emergencias.Permisos
  alias Emergencias.Dominio.Codigos
  alias Emergencias.Dominio.Necesidad

  @doc "Secciones con sus acciones, en el orden en que se muestran."
  def grupos do
    [
      {"Zonas",
       [
         accion(
           "Registrar zona, sector o punto",
           "registrar_zona",
           [
             "Código",
             "Nombre",
             {"Nivel de afectación", {:codigos, "nivel"}},
             "Personas afectadas"
           ],
           [{"padre", "Código del padre (vacío si es una zona)"}]
         ),
         accion("Ver árbol de zonas", "listar_zonas"),
         accion("Estado de una zona", "estado_zona", ["Código de la zona"]),
         accion("Actualizar zona", "actualizar_zona", ["Código"], [
           {"nivel", "Nuevo nivel", {:codigos, "nivel"}},
           {"personas", "Personas afectadas"}
         ])
       ]},
      {"Necesidades",
       [
         accion(
           "Registrar necesidad",
           "registrar_necesidad",
           [
             {"Tipo", {:codigos, "tipo_necesidad"}},
             "Cantidad",
             {"Prioridad", {:codigos, "prioridad"}},
             "Zona",
             "Descripción"
           ],
           [{"lugar", "Albergue asociado (opcional)"}]
         ),
         accion("Necesidades pendientes", "necesidades_pendientes"),
         accion("Buscar necesidades", "listar_necesidades", [], [
           {"zona", "Zona"},
           {"tipo", "Tipo", {:codigos, "tipo_necesidad"}},
           {"prioridad", "Prioridad", {:codigos, "prioridad"}},
           {"estado", "Estado", Necesidad.estados()}
         ]),
         accion("Asignar recurso", "asignar_recurso", [
           "Id de la necesidad (N001)",
           "Tipo o código del recurso",
           "Cantidad"
         ]),
         accion("Atender la más urgente", "atender_siguiente", [], [
           {"tipo", "Tipo de necesidad", {:codigos, "tipo_necesidad"}}
         ]),
         accion("Iniciar atención", "iniciar_atencion", ["Id de la necesidad"]),
         accion("Marcar como atendida", "cerrar_necesidad", ["Id de la necesidad"]),
         accion("Cancelar necesidad", "cancelar_necesidad", ["Id de la necesidad"])
       ]},
      {"Recursos",
       [
         accion(
           "Registrar recurso",
           "registrar_recurso",
           [
             "Código",
             "Nombre (agua, alimentos, ...)",
             "Cantidad",
             "Unidad de medida",
             "Ubicación (centro de apoyo)"
           ],
           [{"zona", "Zona (vacío = su zona)"}, {"categoria", "Categoría (opcional)"}]
         ),
         accion("Ver recursos", "listar_recursos", [], [{"tipo", "Tipo"}, {"zona", "Zona"}]),
         accion(
           "Entrada de inventario",
           "entrada_recurso",
           ["Código del recurso", "Ubicación", "Cantidad"],
           [{"motivo", "Motivo"}]
         ),
         accion(
           "Salida de inventario",
           "salida_recurso",
           ["Código del recurso", "Ubicación", "Cantidad"],
           [{"motivo", "Motivo"}]
         ),
         accion("Transferir entre centros", "transferir_recurso", [
           "Código del recurso",
           "Origen",
           "Destino",
           "Cantidad"
         ]),
         accion("Historial de un recurso", "historial_recurso", ["Código del recurso"]),
         accion("Recursos críticos", "recursos_criticos", [], [
           {"umbral", "Umbral (por defecto 20)"}
         ])
       ]},
      {"Familiares",
       [
         accion(
           "Reportar persona afectada",
           "reportar_persona",
           [
             "Número de documento o dato de referencia",
             "Nombre",
             {"Zona o código de barrio", {:sugerir, "barrio"}},
             {"Estado", {:codigos, "estado_persona"}}
           ],
           [
             {"tipo_doc", "Tipo de documento", {:codigos, "tipo_doc"}},
             {"edad", "Edad"},
             {"direccion", "Dirección o referencia"},
             {"barrio", "Barrio: código (B01...) o nombre de uno nuevo"}
           ]
         ),
         accion("Buscar persona por documento", "buscar_persona", ["Documento"]),
         accion("Buscar personas por estado o barrio", "buscar_persona", [], [
           {"nombre", "Nombre (o parte)"},
           {"estado", "Estado", {:codigos, "estado_persona"}},
           {"barrio", "Barrio", {:codigos, "barrio"}},
           {"zona", "Zona"}
         ])
         |> con_id("buscar_personas"),
         accion(
           "Actualizar estado de una persona",
           "actualizar_persona",
           ["Documento", {"Nuevo estado", {:codigos, "estado_persona"}}],
           [{"detalle", "Detalle (opcional)"}]
         ),
         accion("Historial de una persona", "historial_persona", ["Documento"]),
         accion("Enviar mensaje a un familiar", "enviar_mensaje", [
           "Documento de la persona",
           "Mensaje"
         ]),
         accion("Ver mensajes de una persona", "listar_mensajes", ["Documento"]),
         accion("Marcar mensaje", "marcar_mensaje", [
           "Id del mensaje (M001)",
           {"Estado", ["entregado", "pendiente"]}
         ])
       ]},
      {"Mascotas",
       [
         accion(
           "Reportar mascota",
           "reportar_mascota",
           [
             {"Tipo de reporte", {:codigos, "tipo_reporte"}},
             {"Especie", {:codigos, "especie"}},
             "Nombre (o desconocido)",
             {"Color", {:codigos, "color"}},
             {"Tamaño", {:codigos, "tamano"}},
             {"Zona o código de barrio", {:sugerir, "barrio"}},
             "Contacto"
           ],
           [
             {"caracteristicas", "Características"},
             {"direccion", "Dirección o referencia"},
             {"especie_otra", "Si la especie es ES03 (otro): ¿cuál?"},
             {"color_otro", "Si el color es CO05 (otro): ¿cuál?"},
             {"barrio", "Barrio: código (B01...) o nombre de uno nuevo"}
           ]
         ),
         accion("Ver reportes", "listar_mascotas", [], [
           {"especie", "Especie", {:codigos, "especie"}},
           {"barrio", "Barrio", {:codigos, "barrio"}},
           {"zona", "Zona"}
         ]),
         accion("Buscar coincidencias", "buscar_coincidencias"),
         accion("Confirmar coincidencia", "confirmar_coincidencia", [
           "Id del reporte perdido",
           "Id del reporte encontrado"
         ])
       ]},
      {"Albergues",
       [
         accion("Registrar albergue", "registrar_albergue", [
           "Código",
           "Nombre",
           "Zona",
           "Capacidad máxima"
         ]),
         accion("Ver albergues", "listar_albergues"),
         accion("Consultar albergue", "consultar_albergue", ["Código del albergue"]),
         accion("Registrar ingreso", "registrar_ingreso", ["Código del albergue", "Documento"]),
         accion("Registrar salida", "registrar_salida", ["Código del albergue", "Documento"]),
         accion("Reporte de ocupación", "reporte_albergues")
       ]},
      {"Códigos",
       [
         accion("Índice de tablas de códigos", "codigos"),
         accion("Registrar barrio (recibe B01, B02...)", "registrar_barrio", [
           "Nombre del barrio",
           "Zona"
         ]),
         accion("Ver una tabla de códigos", "codigos", [
           {"Tabla", Codigos.nombres() ++ ["todas"]}
         ])
         |> con_id("codigos_tabla")
       ]},
      {"Reportes y usuarios",
       [
         accion("Resumen global", "resumen"),
         accion("Mi actividad", "actividad"),
         accion("Usuarios conectados", "sesiones"),
         accion("Usuarios registrados", "listar_usuarios"),
         accion(
           "Crear usuario",
           "registrar_usuario",
           [
             "Usuario (sin espacios)",
             "*Contraseña",
             {"Tipo", {:codigos, "rol"}},
             "Zona principal"
           ],
           [{"nombre", "Nombre completo"}]
         ),
         accion("Simular falla de un gestor", "simular_falla", [
           {"Gestor",
            ~w(recursos necesidades zonas personas mensajes mascotas albergues usuarios)}
         ])
       ]}
    ]
  end

  @doc "Secciones con solo las acciones que permite el rol del usuario (sin secciones vacías)."
  def grupos_permitidos(usuario) do
    grupos()
    |> Enum.map(fn {grupo, acciones} ->
      {grupo, Enum.filter(acciones, &Permisos.permitido?(usuario, &1.comando))}
    end)
    |> Enum.reject(fn {_grupo, acciones} -> acciones == [] end)
  end

  @doc "Lista plana de las acciones que permite el rol del usuario."
  def permitidas(usuario), do: usuario |> grupos_permitidos() |> Enum.flat_map(&elem(&1, 1))

  @doc "Busca una acción por su `id` (normalmente el mismo comando)."
  def buscar(id) do
    case grupos() |> Enum.flat_map(&elem(&1, 1)) |> Enum.find(&(&1.id == id)) do
      nil -> :error
      accion -> {:ok, accion}
    end
  end

  @doc """
  Arma la línea de comando con los valores en el orden de los campos
  (primero los obligatorios y después los opcionales).
  """
  def armar(accion, valores) do
    {obligatorios, opcionales} = Enum.split(valores, length(accion.campos))
    claves = Enum.map(accion.opcionales, & &1.clave)
    armar_comando(accion.comando, obligatorios, Enum.zip(claves, opcionales))
  end

  @doc """
  Arma la línea de comando. Cada valor va entre comillas para respetar los
  espacios. Retorna `{:ok, linea}` o `{:error, motivo}`.

      iex> Emergencias.Interfaz.Acciones.armar_comando("buscar_persona", ["1094"], [])
      {:ok, ~s(buscar_persona "1094")}
  """
  def armar_comando(comando, obligatorios, opcionales) do
    if Enum.any?(obligatorios, &(String.trim(&1) == "")) do
      {:error, "Complete todos los campos obligatorios"}
    else
      extras =
        for {clave, valor} <- opcionales,
            String.trim(valor) != "",
            do: ~s(#{clave}="#{limpiar(valor)}")

      {:ok, Enum.join([comando | Enum.map(obligatorios, &~s("#{limpiar(&1)}"))] ++ extras, " ")}
    end
  end

  @doc """
  Texto de un campo para las ventanas: `*` = oculto, `|` separa las opciones.

      iex> Emergencias.Interfaz.Acciones.texto_ventana(%{etiqueta: "Tamaño", oculto: false, nombres: ["TA1 – pequena", "TA2 – mediana"]})
      "Tamaño|TA1 – pequena|TA2 – mediana"
  """
  def texto_ventana(%{etiqueta: etiqueta, oculto: true}), do: "*" <> etiqueta
  def texto_ventana(%{etiqueta: etiqueta, nombres: []}), do: etiqueta

  def texto_ventana(%{etiqueta: etiqueta, nombres: nombres}),
    do: Enum.join([etiqueta | nombres], "|")

  # ---------------------------------------------------------------------------
  # Construcción del catálogo
  # ---------------------------------------------------------------------------

  defp accion(texto, comando, campos \\ [], opcionales \\ []) do
    %{
      id: comando,
      texto: texto,
      comando: comando,
      campos: Enum.map(campos, &campo/1),
      opcionales: Enum.map(opcionales, &opcional/1)
    }
  end

  # Para dos acciones con el mismo comando y distintos campos.
  defp con_id(accion, id), do: %{accion | id: id}

  # opciones = lo que se envía, nombres = lo que se ve.
  defp campo({etiqueta, {modo, tabla}}) when modo in [:codigos, :sugerir] do
    {codigos, nombres} = Codigos.etiquetas(tabla) |> Enum.unzip()
    base(etiqueta, codigos, nombres) |> Map.merge(%{libre: modo == :sugerir, tabla: tabla})
  end

  defp campo({etiqueta, opciones}), do: base(etiqueta, opciones, opciones)
  defp campo("*" <> etiqueta), do: %{base(etiqueta, [], []) | oculto: true}
  defp campo(etiqueta), do: base(etiqueta, [], [])

  defp base(etiqueta, opciones, nombres),
    do: %{
      etiqueta: etiqueta,
      opciones: opciones,
      nombres: nombres,
      oculto: false,
      libre: false,
      tabla: nil
    }

  defp opcional({clave, etiqueta}), do: Map.put(campo(etiqueta), :clave, clave)

  defp opcional({clave, etiqueta, opciones}),
    do: Map.put(campo({etiqueta, opciones}), :clave, clave)

  defp limpiar(valor), do: valor |> String.replace("\"", "'") |> String.trim()
end
