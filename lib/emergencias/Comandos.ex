defmodule Emergencias.Comandos do
  @moduledoc """
  Intérprete de comandos. Se ejecuta dentro del proceso `Emergencias.Sesion`
  del usuario y siempre retorna `{:ok, texto}` o `{:error, texto}`.

  - `ejecutar/2`: una línea escrita (`registrar_necesidad agua 30 ...`).
  - `registrar/2`: un struct ya creado, por ejemplo con `Necesidad.ingresar/2`.

  Los dos caminos revisan el permiso del rol y validan antes de cambiar el estado.
  """

  alias Emergencias.{Permisos, Servicios, Sesiones}
  alias Emergencias.Anexos.{Barrios, Codigos}
  alias Emergencias.Interfaz.{Formato, Analizador}

  alias Emergencias.Dominio.{
    Albergue,
    Comun,
    Mascota,
    Mensaje,
    Necesidad,
    Persona,
    Recurso,
    Usuario,
    Zona
  }

  alias Emergencias.Estado.{
    Bitacora,
    GestorAlbergues,
    GestorMascotas,
    GestorMensajes,
    GestorNecesidades,
    GestorPersonas,
    GestorRecursos,
    GestorUsuarios,
    GestorZonas
  }

  @gestores %{
    "usuarios" => GestorUsuarios,
    "zonas" => GestorZonas,
    "recursos" => GestorRecursos,
    "necesidades" => GestorNecesidades,
    "personas" => GestorPersonas,
    "mensajes" => GestorMensajes,
    "mascotas" => GestorMascotas,
    "albergues" => GestorAlbergues
  }

  # Comando al que corresponde registrar cada tipo de struct (para el permiso).
  @comando_de %{
    Usuario => "registrar_usuario",
    Zona => "registrar_zona",
    Necesidad => "registrar_necesidad",
    Recurso => "registrar_recurso",
    Persona => "reportar_persona",
    Mensaje => "enviar_mensaje",
    Mascota => "reportar_mascota",
    Albergue => "registrar_albergue"
  }

  @doc "Ejecuta una línea de comando en nombre de `usuario`."
  def ejecutar(linea, %Usuario{} = usuario) do
    proteger(fn ->
      case Analizador.analizar(linea) do
        {:ok, nil, _argumentos, _opciones} ->
          {:ok, ""}

        {:ok, comando, argumentos, opciones} ->
          autorizar(comando, usuario, fn -> despachar(comando, argumentos, opciones, usuario) end)

        {:error, motivo} ->
          {:error, motivo}
      end
    end)
  end

  @doc """
  Registra un struct del dominio (zona, necesidad, recurso, persona, mensaje,
  mascota, albergue o usuario) en nombre de `usuario`.
  """
  def registrar(%modulo{} = entidad, %Usuario{} = usuario) do
    case Map.fetch(@comando_de, modulo) do
      {:ok, comando} ->
        proteger(fn -> autorizar(comando, usuario, fn -> guardar(entidad, usuario) end) end)

      :error ->
        {:error, "No se puede registrar #{inspect(modulo)}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Permisos y errores inesperados
  # ---------------------------------------------------------------------------

  defp autorizar(comando, usuario, accion) do
    cond do
      not Permisos.existe?(comando) ->
        {:error, "Comando desconocido '#{comando}'. Escriba ayuda para ver la lista."}

      comando in ["conectar", "desconectar"] ->
        {:error, "#{comando} se usa directamente en la consola"}

      not Permisos.permitido?(usuario, comando) ->
        {:error,
         "Permiso denegado: el rol #{usuario.tipo} no puede usar '#{comando}' " <>
           "(requiere #{Permisos.rol_minimo(comando)} o superior)"}

      true ->
        accion.()
    end
  end

  defp proteger(funcion) do
    funcion.()
  rescue
    error -> {:error, "Error inesperado al ejecutar el comando: #{Exception.message(error)}"}
  catch
    :exit, _razon ->
      {:error, "Un servicio no respondió (puede estar reiniciándose). Intente de nuevo."}
  end

  # ---------------------------------------------------------------------------
  # Registro de entidades (lo usan los comandos escritos y los datos de ingresar/2)
  # ---------------------------------------------------------------------------

  defp guardar(%Usuario{} = nuevo, _u) do
    with {:ok, nuevo} <- GestorUsuarios.registrar(nuevo),
         do: {:ok, "Usuario registrado: " <> Usuario.to_string(nuevo)}
  end

  defp guardar(%Zona{} = nodo, _u) do
    with {:ok, nodo} <- GestorZonas.registrar(nodo) do
      donde = if nodo.padre, do: " dentro de #{nodo.padre}", else: ""
      {:ok, "Registrado " <> Zona.to_string(nodo) <> donde}
    end
  end

  defp guardar(%Necesidad{} = n, u) do
    with :ok <- Servicios.validar_zona(n.zona),
         :ok <- validar_lugar(n.lugar),
         {:ok, n} <- GestorNecesidades.registrar(%{n | responsable: u.username}) do
      {:ok, "Necesidad registrada: " <> Necesidad.to_string(n)}
    end
  end

  defp guardar(%Recurso{} = r, _u) do
    with :ok <- Servicios.validar_zona(r.zona),
         {:ok, r} <- GestorRecursos.registrar(r) do
      {:ok, "Recurso registrado: " <> Recurso.to_string(r)}
    end
  end

  defp guardar(%Persona{} = p, _u) do
    with :ok <- Servicios.validar_zona(p.zona),
         {:ok, p} <- GestorPersonas.registrar(p) do
      {:ok, "Persona registrada: " <> Persona.to_string(p)}
    end
  end

  defp guardar(%Mensaje{} = m, u) do
    destinatario =
      case GestorPersonas.obtener(m.documento) do
        {:ok, p} -> p.nombre
        {:error, _} -> "persona no registrada aún"
      end

    with {:ok, m} <-
           GestorMensajes.enviar(%{m | destinatario: destinatario, remitente: u.username}) do
      {:ok, "Mensaje guardado: " <> Mensaje.to_string(m)}
    end
  end

  defp guardar(%Mascota{} = m, _u) do
    with :ok <- Servicios.validar_zona(m.zona),
         {:ok, m} <- GestorMascotas.reportar(m) do
      {:ok, "Reporte registrado: " <> Mascota.to_string(m)}
    end
  end

  defp guardar(%Albergue{} = a, _u) do
    with :ok <- Servicios.validar_zona(a.zona),
         {:ok, a} <- GestorAlbergues.registrar(a) do
      {:ok, "Albergue registrado: " <> Albergue.to_string(a)}
    end
  end

  # ---------------------------------------------------------------------------
  # Sesión y usuarios
  # ---------------------------------------------------------------------------

  defp despachar("ayuda", [], _op, u), do: {:ok, Permisos.ayuda(u)}
  defp despachar("ayuda", [comando | _], _op, _u), do: Permisos.ayuda_comando(comando)
  defp despachar("quien_soy", [], _op, u), do: {:ok, Usuario.to_string(u)}

  defp despachar("sesiones", [], _op, _u),
    do: {:ok, Formato.lista("Usuarios conectados", Sesiones.activas(), &("@" <> &1))}

  defp despachar("listar_usuarios", [], _op, _u),
    do:
      {:ok, Formato.lista("Usuarios registrados", GestorUsuarios.listar(), &Usuario.to_string/1)}

  defp despachar("registrar_usuario", [username, password, tipo, zona], op, u) do
    with {:ok, nuevo} <- Usuario.crear(username, password, tipo, zona, op["nombre"]),
         do: guardar(nuevo, u)
  end

  defp despachar("actividad", argumentos, op, u) do
    with {:ok, cantidad} <- Comun.entero_positivo(Map.get(op, "n", "20"), "n"),
         {:ok, objetivo} <- objetivo_actividad(argumentos, u) do
      titulo = "Actividad " <> if(objetivo, do: "de @#{objetivo}", else: "de todos los usuarios")
      {:ok, Formato.lista(titulo, Bitacora.listar(objetivo, cantidad), & &1)}
    end
  end

  # ---------------------------------------------------------------------------
  # Zonas
  # ---------------------------------------------------------------------------

  defp despachar("registrar_zona", [codigo, nombre, nivel | resto], op, u) do
    personas = List.first(resto) || Map.get(op, "personas", "0")

    with {:ok, nodo} <- Zona.crear(codigo, nombre, nivel, personas, op["padre"]),
         do: guardar(nodo, u)
  end

  defp despachar("actualizar_zona", [codigo], op, _u) do
    with {:ok, nodo} <- GestorZonas.actualizar(codigo, op),
         do: {:ok, "Actualizado " <> Zona.to_string(nodo)}
  end

  defp despachar("listar_zonas", [], _op, _u), do: {:ok, Formato.zonas(GestorZonas.arboles())}

  defp despachar("estado_zona", [codigo], _op, _u) do
    with {:ok, e} <- Servicios.estado_zona(codigo) do
      {:ok,
       Enum.join(
         [
           "Estado de #{e.nodo.tipo} #{e.nodo.codigo} (#{e.nodo.nombre})",
           "  " <> Formato.estadisticas(e.estadisticas),
           "  Necesidades: #{length(e.necesidades)} (pendientes: #{length(e.pendientes)})",
           "  Recursos: #{length(e.recursos)} | Albergues: #{length(e.albergues)} | " <>
             "Personas registradas: #{length(e.personas)} | Reportes de mascotas: #{length(e.mascotas)}",
           "",
           Enum.join(Zona.lineas(e.nodo), "\n"),
           "",
           Formato.lista("Necesidades pendientes", e.pendientes, &Necesidad.to_string/1)
         ],
         "\n"
       )}
    end
  end

  # ---------------------------------------------------------------------------
  # Necesidades
  # ---------------------------------------------------------------------------

  defp despachar("registrar_necesidad", [tipo, cantidad, prioridad, zona | descripcion], op, u)
       when descripcion != [] do
    texto = Enum.join(descripcion, " ")

    with {:ok, n} <-
           Necesidad.crear(nil, tipo, cantidad, prioridad, zona, texto, u.username, op["lugar"]),
         do: guardar(n, u)
  end

  defp despachar("listar_necesidades", [], op, _u) do
    with {:ok, filtros} <- filtros(op, ~w(zona tipo prioridad estado lugar)) do
      {:ok,
       Formato.lista(
         "Necesidades (por prioridad)",
         GestorNecesidades.listar(filtros),
         &Necesidad.to_string/1
       )}
    end
  end

  defp despachar("necesidades_pendientes", [], _op, _u) do
    lista = GestorNecesidades.listar(%{"estado" => "pendiente"})

    {:ok,
     Formato.lista("Necesidades pendientes (más urgente primero)", lista, &Necesidad.to_string/1)}
  end

  defp despachar("asignar_recurso", [id, tipo, cantidad], _op, u) do
    with {:ok, n, partes} <- GestorNecesidades.asignar(id, tipo, cantidad, u.username) do
      {:ok,
       "Asignado a #{n.id}: #{Formato.partes(partes)}. Estado: #{n.estado} (#{n.asignada}/#{n.cantidad})"}
    end
  end

  defp despachar("atender_siguiente", [], op, u) do
    with {:ok, n, partes} <- GestorNecesidades.atender_siguiente(op["tipo"], u.username) do
      {:ok,
       "Se atendió la necesidad más urgente que se podía cubrir:\n  #{Necesidad.to_string(n)}\n" <>
         "  Recursos: #{Formato.partes(partes)}"}
    end
  end

  defp despachar("iniciar_atencion", [id], _op, u), do: cambiar_necesidad(id, "en_atencion", u)
  defp despachar("cerrar_necesidad", [id], _op, u), do: cambiar_necesidad(id, "atendida", u)
  defp despachar("cancelar_necesidad", [id], _op, u), do: cambiar_necesidad(id, "cancelada", u)

  # ---------------------------------------------------------------------------
  # Recursos
  # ---------------------------------------------------------------------------

  defp despachar("registrar_recurso", [codigo, nombre, cantidad, unidad, ubicacion], op, u) do
    zona = Map.get(op, "zona", u.zona)

    with {:ok, r} <-
           Recurso.crear(
             codigo,
             nombre,
             cantidad,
             unidad,
             ubicacion,
             op["categoria"],
             zona,
             u.username
           ),
         do: guardar(r, u)
  end

  defp despachar("entrada_recurso", [codigo, ubicacion, cantidad], op, u) do
    with {:ok, r} <-
           GestorRecursos.entrada(
             codigo,
             ubicacion,
             cantidad,
             Map.get(op, "motivo", ""),
             u.username
           ),
         do: {:ok, "Entrada registrada: " <> Recurso.to_string(r)}
  end

  defp despachar("salida_recurso", [codigo, ubicacion, cantidad], op, u) do
    with {:ok, r} <-
           GestorRecursos.salida(
             codigo,
             ubicacion,
             cantidad,
             Map.get(op, "motivo", ""),
             u.username
           ),
         do: {:ok, "Salida registrada: " <> Recurso.to_string(r)}
  end

  defp despachar("transferir_recurso", [codigo, origen, destino, cantidad], _op, u) do
    with {:ok, r} <- GestorRecursos.transferir(codigo, origen, destino, cantidad, u.username),
         do: {:ok, "Transferencia realizada: " <> Recurso.to_string(r)}
  end

  defp despachar("listar_recursos", [], op, _u) do
    with {:ok, filtros} <- filtros(op, ~w(tipo zona ubicacion)),
         do:
           {:ok, Formato.lista("Recursos", GestorRecursos.listar(filtros), &Recurso.to_string/1)}
  end

  defp despachar("historial_recurso", [codigo], _op, _u) do
    with {:ok, r} <- GestorRecursos.obtener(codigo) do
      {:ok,
       Recurso.to_string(r) <>
         "\n" <> Formato.lista("Movimientos", r.movimientos, &Formato.movimiento/1)}
    end
  end

  defp despachar("recursos_criticos", [], op, _u) do
    with {:ok, umbral} <- Comun.entero_no_negativo(Map.get(op, "umbral", "20"), "umbral") do
      %{escasos: escasos, deficit: deficit} = Servicios.recursos_criticos(umbral)

      {:ok,
       Formato.lista("Recursos con #{umbral} unidades o menos", escasos, &Recurso.to_string/1) <>
         "\n" <>
         Formato.lista("Tipos con demanda pendiente mayor que el inventario", deficit, fn d ->
           "#{d.tipo}: se necesitan #{d.demanda}, hay #{d.disponible} " <>
             "(faltan #{d.demanda - d.disponible}) | #{Enum.join(d.necesidades, ", ")}"
         end)}
    end
  end

  # ---------------------------------------------------------------------------
  # Personas y mensajes entre familiares
  # ---------------------------------------------------------------------------

  defp despachar("reportar_persona", [documento, nombre, zona, estado], op, u) do
    extras = Map.take(op, ~w(tipo_doc barrio direccion))

    with {:ok, p} <-
           Persona.crear(nil, documento, nombre, zona, estado, op["edad"], u.username, extras),
         do: guardar(p, u)
  end

  defp despachar("actualizar_persona", [documento, estado], op, u) do
    with {:ok, p} <-
           GestorPersonas.cambiar_estado(
             documento,
             estado,
             u.username,
             Map.get(op, "detalle", "")
           ),
         do: {:ok, "Estado actualizado: " <> Persona.to_string(p)}
  end

  defp despachar("buscar_persona", [documento], _op, _u) do
    with {:ok, p} <- GestorPersonas.obtener(documento) do
      pendientes = documento |> GestorMensajes.listar() |> Enum.count(&(&1.estado == "pendiente"))
      {:ok, Persona.to_string(p) <> "\n  Mensajes pendientes para esta persona: #{pendientes}"}
    end
  end

  defp despachar("buscar_persona", [], op, _u) when map_size(op) > 0 do
    with {:ok, filtros} <- filtros(op, ~w(nombre documento zona estado barrio)),
         do:
           {:ok,
            Formato.lista(
              "Personas encontradas",
              GestorPersonas.buscar(filtros),
              &Persona.to_string/1
            )}
  end

  defp despachar("historial_persona", [documento], _op, _u) do
    with {:ok, p} <- GestorPersonas.obtener(documento) do
      {:ok,
       Persona.to_string(p) <>
         "\n" <> Formato.lista("Historial de estados", p.historial, &Formato.evento/1)}
    end
  end

  defp despachar("enviar_mensaje", [documento | contenido], _op, u) when contenido != [] do
    with {:ok, m} <- Mensaje.crear(nil, documento, nil, u.username, Enum.join(contenido, " ")),
         do: guardar(m, u)
  end

  defp despachar("listar_mensajes", [documento], _op, _u),
    do:
      {:ok,
       Formato.lista(
         "Mensajes para #{documento}",
         GestorMensajes.listar(documento),
         &Mensaje.to_string/1
       )}

  defp despachar("marcar_mensaje", [id, estado], _op, _u) do
    with {:ok, m} <- GestorMensajes.marcar(id, estado),
         do: {:ok, "Mensaje actualizado: " <> Mensaje.to_string(m)}
  end

  # ---------------------------------------------------------------------------
  # Mascotas
  # ---------------------------------------------------------------------------

  defp despachar(
         "reportar_mascota",
         [tipo, especie, nombre, color, tamano, zona, contacto],
         op,
         u
       ) do
    with {:ok, m} <-
           Mascota.crear(
             nil,
             tipo,
             especie,
             nombre,
             color,
             tamano,
             zona,
             contacto,
             op["caracteristicas"],
             u.username,
             Map.take(op, ~w(especie_otra color_otro barrio direccion))
           ),
         do: guardar(m, u)
  end

  defp despachar("listar_mascotas", [], op, _u) do
    with {:ok, filtros} <- filtros(op, ~w(especie zona estado tipo barrio)),
         do:
           {:ok,
            Formato.lista(
              "Reportes de mascotas",
              GestorMascotas.listar(filtros),
              &Mascota.to_string/1
            )}
  end

  defp despachar("buscar_coincidencias", [], _op, _u) do
    {:ok, parejas} = GestorMascotas.buscar_coincidencias()

    ayuda =
      if parejas != [],
        do: "\nPara cerrar una: confirmar_coincidencia id_perdida id_encontrada",
        else: ""

    {:ok,
     Formato.lista(
       "Posibles coincidencias (puntaje >= #{Mascota.umbral()})",
       parejas,
       &Formato.pareja/1
     ) <> ayuda}
  end

  defp despachar("confirmar_coincidencia", [id_a, id_b], _op, u) do
    with {:ok, a, b, puntaje} <- GestorMascotas.confirmar(id_a, id_b, u.username) do
      {:ok,
       "Coincidencia confirmada (puntaje #{puntaje}). Reportes cerrados:\n  " <>
         Mascota.to_string(a) <> "\n  " <> Mascota.to_string(b)}
    end
  end

  # ---------------------------------------------------------------------------
  # Albergues
  # ---------------------------------------------------------------------------

  defp despachar("registrar_albergue", [codigo, nombre, zona, capacidad], _op, u) do
    with {:ok, a} <- Albergue.crear(codigo, nombre, zona, capacidad), do: guardar(a, u)
  end

  defp despachar("consultar_albergue", [codigo], _op, _u) do
    with {:ok, a} <- GestorAlbergues.obtener(codigo) do
      ocupantes =
        a.ocupantes
        |> Util2.ordenar()
        |> Enum.map(fn documento ->
          case GestorPersonas.obtener(documento) do
            {:ok, p} -> "#{p.documento} #{p.nombre}"
            _ -> documento
          end
        end)

      {:ok,
       Enum.join(
         [
           Albergue.to_string(a),
           Formato.lista("Personas alojadas", ocupantes, & &1),
           Formato.lista(
             "Recursos en el albergue",
             GestorRecursos.listar(%{"ubicacion" => a.codigo}),
             &Recurso.to_string/1
           ),
           Formato.lista(
             "Necesidades del albergue",
             GestorNecesidades.listar(%{"lugar" => a.codigo}),
             &Necesidad.to_string/1
           )
         ],
         "\n"
       )}
    end
  end

  defp despachar("listar_albergues", [], _op, _u),
    do: {:ok, Formato.lista("Albergues", GestorAlbergues.listar(), &Albergue.to_string/1)}

  defp despachar("reporte_albergues", [], _op, _u) do
    lista = Util2.ordenar(GestorAlbergues.listar(), :asc, &{-Albergue.porcentaje(&1), &1.codigo})

    {:ok,
     Formato.lista(
       "Albergues por nivel de ocupación (mayor primero)",
       lista,
       &Albergue.to_string/1
     )}
  end

  defp despachar("registrar_ingreso", [codigo, documento], _op, u) do
    with {:ok, a, p} <- Servicios.ingresar_a_albergue(codigo, documento, u.username),
         do: {:ok, "Ingreso registrado: #{p.nombre} -> #{a.nombre}. " <> Albergue.to_string(a)}
  end

  defp despachar("registrar_salida", [codigo, documento], _op, u) do
    with {:ok, a, _p} <- Servicios.salir_de_albergue(codigo, documento, u.username),
         do: {:ok, "Salida registrada del documento #{documento}. " <> Albergue.to_string(a)}
  end

  # ---------------------------------------------------------------------------
  # Reportes y supervisión
  # ---------------------------------------------------------------------------

  defp despachar("resumen", [], _op, _u), do: {:ok, Formato.resumen(Servicios.resumen())}

  defp despachar("simular_falla", [nombre], _op, _u) do
    case Map.fetch(@gestores, Comun.normalizar(nombre)) do
      {:ok, modulo} ->
        anterior = Process.whereis(modulo)
        Process.exit(anterior, :kill)
        nuevo = esperar_reinicio(modulo, anterior, 20)

        {:ok,
         "Se forzó la caída de #{inspect(modulo)} (#{inspect(anterior)}). El Supervisor lo reinició " <>
           "como #{inspect(nuevo)} y recargó sus datos desde el archivo de texto."}

      :error ->
        {:error,
         "Gestor desconocido. Use: #{@gestores |> Map.keys() |> Util2.ordenar() |> Enum.join(", ")}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Espacio para los comandos de los módulos que se agreguen más adelante.
  # Agregue aquí sus cláusulas de despachar/4 (y el comando en Permisos).
  # ---------------------------------------------------------------------------

  # Anexo: base de datos de códigos (Emergencias.Anexos.Codigos).
  defp despachar("codigos", [], _op, _u), do: {:ok, Codigos.indice()}
  defp despachar("codigos", ["todas"], _op, _u), do: {:ok, Codigos.formato_todas()}
  defp despachar("codigos", [tabla], _op, _u), do: Codigos.formato_tabla(String.downcase(tabla))

  # Anexo: barrios registrados a mano (Emergencias.Anexos.Barrios). La zona es
  # el último dato; el nombre puede ir entre comillas o en varias palabras.
  defp despachar("registrar_barrio", argumentos, _op, _u) when length(argumentos) >= 2 do
    {palabras, [zona]} = Enum.split(argumentos, -1)

    case Barrios.registrar(Enum.join(palabras, " "), zona) do
      {:ok, b, :nuevo} ->
        {:ok, "Barrio registrado: #{b.codigo} – #{b.nombre} (zona #{b.zona})"}

      {:ok, b, :existente} ->
        {:ok, "Ese barrio ya estaba registrado: #{b.codigo} – #{b.nombre} (zona #{b.zona})"}

      error ->
        error
    end
  end

  # Cualquier comando conocido con argumentos que no encajan con ninguna cláusula.
  defp despachar(comando, _argumentos, _op, _u), do: {:error, "Uso: #{Permisos.uso(comando)}"}

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp cambiar_necesidad(id, estado, u) do
    with {:ok, n} <- GestorNecesidades.cambiar_estado(id, estado, u.username) do
      devolucion =
        if estado == "cancelada",
          do: " (los recursos asignados volvieron al inventario)",
          else: ""

      {:ok, "Necesidad actualizada#{devolucion}: " <> Necesidad.to_string(n)}
    end
  end

  defp objetivo_actividad([], u),
    do: {:ok, if(u.tipo == "administrador", do: nil, else: u.username)}

  defp objetivo_actividad([otro | _], %{tipo: "administrador"}), do: {:ok, Usuario.clave(otro)}

  defp objetivo_actividad([otro | _], u) do
    if Usuario.clave(otro) == u.username,
      do: {:ok, u.username},
      else: {:error, "Solo el administrador puede ver la actividad de otros usuarios"}
  end

  defp validar_lugar(nil), do: :ok

  defp validar_lugar(codigo) do
    case GestorAlbergues.obtener(codigo) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "El lugar '#{codigo}' no es un albergue registrado"}
    end
  end

  defp filtros(opciones, permitidos) do
    case Map.keys(opciones) -- permitidos do
      [] ->
        {:ok, opciones}

      sobrantes ->
        {:error,
         "Filtro desconocido: #{Enum.join(sobrantes, ", ")}. Use: #{Enum.join(permitidos, ", ")}"}
    end
  end

  # **Recursiva.** Espera (poco) a que el Supervisor registre el nuevo proceso.
  defp esperar_reinicio(_modulo, _anterior, 0), do: nil

  defp esperar_reinicio(modulo, anterior, intentos) do
    case Process.whereis(modulo) do
      pid when is_pid(pid) and pid != anterior ->
        pid

      _ ->
        Process.sleep(10)
        esperar_reinicio(modulo, anterior, intentos - 1)
    end
  end
end
