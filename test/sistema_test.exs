defmodule SistemaTest do
  @moduledoc """
  Pruebas del sistema completo: procesos, concurrencia, supervisión y persistencia.
  No son asíncronas porque todas comparten la misma aplicación.
  """

  use ExUnit.Case, async: false

  import Emergencias.Prueba

  alias Emergencias.{Sesion, Sesiones}
  alias Emergencias.Estado.{GestorNecesidades, GestorRecursos}

  setup do
    reiniciar()
    coordinador = sesion("laura", "coordinador")

    preparar(coordinador, [
      ~s(registrar_zona centro "Zona Centro" critico 1000),
      ~s(registrar_zona norte "Zona Norte" alto 500)
    ])

    %{coordinador: coordinador}
  end

  describe "usuarios y permisos" do
    test "conectar registra si no existe y valida la contraseña si existe" do
      assert {:ok, _pid, u, mensaje} = Sesiones.conectar(["nuevo", "abcd"])
      assert u.tipo == "ciudadano"
      assert mensaje =~ "registrado"
      assert {:error, mensaje} = Sesiones.conectar(["nuevo", "mala"])
      assert mensaje =~ "Contraseña incorrecta"
      assert {:ok, _pid, _u, mensaje} = Sesiones.conectar(["nuevo", "abcd"])
      assert mensaje =~ "Bienvenido"
    end

    test "un ciudadano no puede registrar recursos y un comando desconocido se informa" do
      ciudadano = sesion("ana", "ciudadano")

      assert {:error, mensaje} =
               Sesion.ejecutar(ciudadano, "registrar_recurso R001 agua 5 litros centro_acopio")

      assert mensaje =~ "Permiso denegado"
      assert {:error, mensaje} = Sesion.ejecutar(ciudadano, "volar")
      assert mensaje =~ "desconocido"
    end

    test "las entradas se validan antes de modificar el estado", %{coordinador: c} do
      assert {:error, _} = Sesion.ejecutar(c, ~s(registrar_necesidad agua -3 alta centro "x"))

      assert {:error, mensaje} =
               Sesion.ejecutar(c, ~s(registrar_necesidad agua 3 alta zona_falsa "x"))

      assert mensaje =~ "no está registrada"

      assert {:error, _} =
               Sesion.ejecutar(c, "registrar_recurso R001 agua -5 litros centro_acopio")

      assert {:error, _} = Sesion.ejecutar(c, ~s(registrar_zona centro "Repetida" alto 1))
      assert GestorNecesidades.listar() == []
    end
  end

  describe "conflictos concurrentes" do
    test "dos asignaciones simultáneas no superan el inventario (30 + 25 sobre 50)", %{
      coordinador: laura
    } do
      pedro = sesion("pedro", "coordinador")

      preparar(laura, [
        ~s(registrar_necesidad agua 30 critica centro "Punto 3"),
        ~s(registrar_necesidad agua 25 alta centro "Parque"),
        "registrar_recurso R001 agua 50 litros centro_acopio"
      ])

      resultados =
        [{laura, "asignar_recurso N001 agua 30"}, {pedro, "asignar_recurso N002 agua 25"}]
        |> Enum.map(fn {s, linea} -> Task.async(fn -> Sesion.ejecutar(s, linea) end) end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      {:ok, r} = GestorRecursos.obtener("R001")
      assert Emergencias.Dominio.Recurso.total(r) in [20, 25]
    end

    test "50 asignaciones simultáneas: lo asignado nunca supera lo disponible", %{coordinador: c} do
      preparar(c, ["registrar_recurso R002 alimentos 100 raciones bodega"])

      for i <- 1..50,
          do: preparar(c, [~s(registrar_necesidad alimentos 3 media centro "Familia #{i}")])

      resultados =
        GestorNecesidades.listar()
        |> Enum.map(fn n ->
          Task.async(fn -> GestorNecesidades.asignar(n.id, "alimentos", 3, "laura") end)
        end)
        |> Task.await_many()

      exitosas = Enum.count(resultados, &match?({:ok, _, _}, &1))
      assert exitosas == 33
      {:ok, r} = GestorRecursos.obtener("R002")
      assert Emergencias.Dominio.Recurso.total(r) == 100 - exitosas * 3
    end

    test "un mismo reporte de mascota no se resuelve dos veces aunque se confirme a la vez", %{
      coordinador: c
    } do
      preparar(c, [
        "reportar_mascota perdida perro Luna negra mediana norte 300",
        "reportar_mascota encontrada perro desconocido negra mediana norte 301"
      ])

      otro = sesion("pedro", "coordinador")

      resultados =
        [c, otro]
        |> Enum.map(fn s ->
          Task.async(fn -> Sesion.ejecutar(s, "confirmar_coincidencia MA001 MA002") end)
        end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    end

    test "ingresos simultáneos no superan la capacidad del albergue", %{coordinador: c} do
      preparar(c, [~s(registrar_albergue A01 "Albergue Norte" norte 3)])

      for i <- 1..8,
          do: preparar(c, [~s(reportar_persona doc#{i} "Persona #{i}" norte localizada)])

      resultados =
        1..8
        |> Enum.map(fn i ->
          Task.async(fn -> Sesion.ejecutar(c, "registrar_ingreso A01 doc#{i}") end)
        end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 3
      {:ok, albergue} = Emergencias.Estado.GestorAlbergues.obtener("A01")
      assert Emergencias.Dominio.Albergue.ocupacion(albergue) == 3
    end
  end

  describe "reglas de negocio" do
    test "una necesidad atendida no vuelve a consumir recursos y no se cierra dos veces", %{
      coordinador: c
    } do
      preparar(c, [
        ~s(registrar_necesidad agua 10 alta centro "x"),
        "registrar_recurso R001 agua 100 litros centro_acopio",
        "asignar_recurso N001 agua 10",
        "cerrar_necesidad N001"
      ])

      assert {:error, m1} = Sesion.ejecutar(c, "asignar_recurso N001 agua 5")
      assert m1 =~ "ya fue atendida"
      assert {:error, _} = Sesion.ejecutar(c, "cerrar_necesidad N001")
    end

    test "cancelar devuelve los recursos al inventario", %{coordinador: c} do
      preparar(c, [
        ~s(registrar_necesidad agua 10 alta centro "x"),
        "registrar_recurso R001 agua 30 litros centro_acopio",
        "asignar_recurso N001 agua 10",
        "cancelar_necesidad N001"
      ])

      {:ok, r} = GestorRecursos.obtener("R001")
      assert Emergencias.Dominio.Recurso.total(r) == 30
    end

    test "atender_siguiente atiende primero la necesidad de mayor prioridad", %{coordinador: c} do
      preparar(c, [
        ~s(registrar_necesidad agua 5 baja centro "baja"),
        ~s(registrar_necesidad agua 5 critica centro "urgente"),
        "registrar_recurso R001 agua 5 litros centro_acopio"
      ])

      assert {:ok, texto} = Sesion.ejecutar(c, "atender_siguiente")
      assert texto =~ "N002"
    end

    test "mensajes, búsqueda de personas e historial", %{coordinador: c} do
      preparar(c, [
        ~s(reportar_persona 1094 "Andrés López" norte localizada edad=34),
        ~s(registrar_albergue A01 "Albergue Norte" norte 10),
        "registrar_ingreso A01 1094",
        ~s(enviar_mensaje 1094 "Estamos bien")
      ])

      assert {:ok, texto} = Sesion.ejecutar(c, "buscar_persona nombre=andres")
      assert texto =~ "en_albergue"
      assert {:ok, texto} = Sesion.ejecutar(c, "listar_mensajes 1094")
      assert texto =~ "Estamos bien"
      assert {:ok, _} = Sesion.ejecutar(c, "marcar_mensaje M001 entregado")
      assert {:error, _} = Sesion.ejecutar(c, "marcar_mensaje M001 entregado")
    end

    test "estadísticas recursivas de una zona con sectores", %{coordinador: c} do
      preparar(c, [
        ~s(registrar_zona s1 "Sector 1" alto 200 padre=centro),
        ~s(registrar_zona p1 "Punto 1" medio 20 padre=s1)
      ])

      assert {:ok, texto} = Sesion.ejecutar(c, "estado_zona centro")
      assert texto =~ "1220 personas afectadas"
    end
  end

  describe "registro con structs (modo guiado de ingresar)" do
    test "un struct creado con crear se registra y respeta los permisos", %{coordinador: c} do
      {:ok, necesidad} =
        Emergencias.Dominio.Necesidad.crear(nil, "agua", 5, "alta", "centro", "Guiada", "x")

      assert {:ok, texto} = Sesion.registrar(c, necesidad)
      assert texto =~ "N001"
      assert texto =~ "por laura"

      ciudadano = sesion("ana", "ciudadano")
      {:ok, albergue} = Emergencias.Dominio.Albergue.crear("A03", "Norte", "norte", 5)
      assert {:error, mensaje} = Sesion.registrar(ciudadano, albergue)
      assert mensaje =~ "Permiso denegado"
    end

    test "cada struct se muestra con su to_string (String.Chars)" do
      {:ok, albergue} = Emergencias.Dominio.Albergue.crear("A01", "Norte", "norte", 10)
      assert "#{albergue}" =~ "A01 | Norte | zona norte | ocupación 0/10"
    end
  end

  describe "página web (rutas)" do
    alias Emergencias.Web.Rutas

    test "conectar, ejecutar un comando y salir con el token" do
      :ok = Emergencias.Web.iniciar(4799)
      assert {"200 OK", "text/html" <> _, html} = Rutas.responder("GET", "/", "")
      assert html =~ "Iniciar sesión"

      cuerpo =
        JSON.encode!(%{usuario: "web1", contrasena: "1234", tipo: "coordinador", zona: "centro"})

      {"200 OK", _, respuesta} = Rutas.responder("POST", "/api/conectar", cuerpo)
      %{"ok" => true, "token" => token} = JSON.decode!(respuesta)

      {_, _, respuesta} =
        Rutas.responder(
          "POST",
          "/api/comando",
          JSON.encode!(%{token: token, linea: "listar_zonas"})
        )

      assert %{"ok" => true, "texto" => texto} = JSON.decode!(respuesta)
      assert texto =~ "centro"

      {_, _, respuesta} =
        Rutas.responder("POST", "/api/comando", JSON.encode!(%{token: "falso", linea: "resumen"}))

      assert %{"ok" => false} = JSON.decode!(respuesta)

      {_, _, respuesta} = Rutas.responder("POST", "/api/salir", JSON.encode!(%{token: token}))
      assert %{"ok" => true} = JSON.decode!(respuesta)
    end

    test "acciones por rol, acción con formulario, nombre completo y puerto ocupado" do
      :ok = Emergencias.Web.iniciar(4798)
      assert {:error, mensaje} = Emergencias.Web.iniciar(4798)
      assert mensaje =~ "ya está en uso"

      datos = %{
        usuario: "ana.lopez",
        contrasena: "1234",
        nombre: "Ana López",
        tipo: "",
        zona: "norte"
      }

      {_, _, respuesta} = Rutas.responder("POST", "/api/conectar", JSON.encode!(datos))

      %{"ok" => true, "token" => token, "nombre" => "Ana López", "tipo" => "ciudadano"} =
        JSON.decode!(respuesta)

      {_, _, respuesta} = Rutas.responder("POST", "/api/acciones", JSON.encode!(%{token: token}))
      %{"ok" => true, "grupos" => grupos} = JSON.decode!(respuesta)
      comandos = for g <- grupos, a <- g["acciones"], do: a["comando"]
      assert "registrar_necesidad" in comandos
      refute "registrar_recurso" in comandos

      accion = %{
        token: token,
        comando: "registrar_necesidad",
        valores: ["agua", "5", "alta", "norte", "Familia López", ""]
      }

      {_, _, respuesta} = Rutas.responder("POST", "/api/accion", JSON.encode!(accion))
      assert %{"ok" => true, "texto" => texto} = JSON.decode!(respuesta)
      assert texto =~ "Familia López"

      usuario_con_espacios = %{usuario: "joan sebastian", contrasena: "1234"}

      {_, _, respuesta} =
        Rutas.responder("POST", "/api/conectar", JSON.encode!(usuario_con_espacios))

      assert %{"ok" => false, "texto" => texto} = JSON.decode!(respuesta)
      assert texto =~ "sin espacios"
    end
  end

  describe "supervisión y persistencia" do
    test "si un gestor se cae, el supervisor lo reinicia con los datos del archivo", %{
      coordinador: c
    } do
      preparar(c, ["registrar_recurso R001 agua 40 litros centro_acopio"])
      admin = sesion("admin", "administrador")
      assert {:ok, _} = Sesion.ejecutar(admin, "simular_falla recursos")
      assert {:ok, r} = GestorRecursos.obtener("R001")
      assert Emergencias.Dominio.Recurso.total(r) == 40
    end

    test "los datos sobreviven a reiniciar la aplicación completa", %{coordinador: c} do
      preparar(c, [~s(registrar_necesidad rescate 2 critica norte "Edificio colapsado")])
      Application.stop(:emergencias)
      {:ok, _} = Application.ensure_all_started(:emergencias)
      assert [%{descripcion: "Edificio colapsado"}] = GestorNecesidades.listar()
      assert {:ok, _pid, _u, mensaje} = Sesiones.conectar(["laura", "1234"])
      assert mensaje =~ "Bienvenido"
    end
  end
end
