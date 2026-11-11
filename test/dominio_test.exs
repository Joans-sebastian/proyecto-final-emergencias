defmodule DominioTest do
  @moduledoc "Pruebas de las funciones puras del dominio (sin procesos)."

  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Albergue, Comun, Mascota, Necesidad, Persona, Recurso, Usuario, Zona}
  alias Emergencias.Interfaz.Analizador

  doctest Emergencias.Dominio.Comun
  doctest Emergencias.Dominio.Recurso
  doctest Emergencias.Interfaz.Analizador
  doctest Emergencias.Interfaz.Acciones
  doctest Emergencias.Sesiones

  defp arbol do
    {:ok, centro} = Zona.crear("centro", "Centro", "critico", 100)
    {:ok, sector} = Zona.crear("s1", "Sector 1", "alto", 30)
    {:ok, punto} = Zona.crear("p1", "Punto 1", "medio", 5)
    {:ok, a} = Zona.insertar([], nil, centro)
    {:ok, a} = Zona.insertar(a, "centro", sector)
    {:ok, a} = Zona.insertar(a, "s1", punto)
    a
  end

  describe "árbol de zonas (recursión)" do
    test "insertar asigna el tipo según el padre y buscar encuentra en cualquier nivel" do
      a = arbol()
      assert %Zona{tipo: "sector"} = Zona.buscar(a, "s1")
      assert %Zona{tipo: "punto"} = Zona.buscar(a, "p1")
      assert Zona.buscar(a, "no_existe") == nil
    end

    test "un punto de atención no puede tener hijos y el padre debe existir" do
      {:ok, otro} = Zona.crear("x", "X", "bajo", 0)
      assert {:error, _} = Zona.insertar(arbol(), "p1", otro)
      assert {:error, _} = Zona.insertar(arbol(), "fantasma", otro)
    end

    test "estadísticas acumuladas y códigos del subárbol" do
      [centro] = arbol()

      assert Zona.estadisticas(centro) == %{
               personas: 135,
               sectores: 1,
               puntos: 1,
               nivel_maximo: "critico"
             }

      assert Zona.codigos(centro) == ["centro", "s1", "p1"]
    end

    test "actualizar un nodo profundo y persistencia ida y vuelta" do
      {:ok, a} = Zona.actualizar(arbol(), "p1", &%{&1 | personas: 50})
      assert Zona.buscar(a, "p1").personas == 50

      reconstruido =
        a
        |> Enum.map(&Zona.a_mapa/1)
        |> JSON.encode!()
        |> JSON.decode!()
        |> Enum.map(&Zona.desde_mapa/1)

      assert reconstruido == a
    end
  end

  describe "recursos" do
    test "planear_retiro es todo o nada" do
      fuentes = [{"R001", "centro_acopio", 20}, {"R002", "bodega", 50}]

      assert {:ok, [%{"cantidad" => 20}, %{"cantidad" => 10}]} =
               Recurso.planear_retiro(fuentes, 30)

      assert Recurso.planear_retiro(fuentes, 71) == :insuficiente
    end

    test "no permite cantidades negativas ni salidas mayores que el inventario" do
      assert {:error, _} =
               Recurso.crear("R001", "agua", -5, "litros", "centro_acopio", nil, "centro", "u")

      {:ok, r} = Recurso.crear("R001", "agua", 10, "litros", "centro_acopio", nil, "centro", "u")
      assert {:error, _} = Recurso.salida(r, "centro_acopio", 11, "", "u")
      assert {:error, _} = Recurso.entrada(r, "centro_acopio", -3, "", "u")
      {:ok, r} = Recurso.transferir(r, "centro_acopio", "bodega", 4, "u")
      assert r.existencias == %{"centro_acopio" => 6, "bodega" => 4}
      assert length(r.movimientos) == 2
    end
  end

  describe "catálogo de códigos permitidos" do
    test "zonas principales: solo sur, centro, norte, este y oeste" do
      {:ok, zona} = Zona.crear("Norte", "Norte", "alto", 10)
      assert {:ok, [%Zona{codigo: "norte"}]} = Zona.insertar([], nil, zona)

      {:ok, otra} = Zona.crear("zona_norte", "X", "alto", 10)
      assert {:error, mensaje} = Zona.insertar([], nil, otra)
      assert mensaje =~ "sur, centro, norte, este, oeste"
    end

    test "un sector no puede usar el código de una zona principal" do
      {:ok, sector} = Zona.crear("sur", "Sector", "alto", 1)
      assert {:error, mensaje} = Zona.insertar(arbol(), "centro", sector)
      assert mensaje =~ "reservado"
    end

    test "albergues A01-A03, recursos R001-R003 y ubicaciones del catálogo" do
      assert {:ok, %Albergue{codigo: "A03"}} = Albergue.crear("a03", "X", "norte", 5)
      assert {:error, _} = Albergue.crear("A04", "X", "norte", 5)

      assert {:error, _} =
               Recurso.crear("R004", "agua", 5, "litros", "bodega", nil, "centro", "u")

      assert {:error, _} = Recurso.crear("R001", "agua", 5, "litros", "otro", nil, "centro", "u")

      for ubicacion <- ~w(centro_acopio bodega fundacion A01) do
        assert {:ok, _} =
                 Recurso.crear("R001", "agua", 5, "litros", ubicacion, nil, "centro", "u")
      end
    end

    test "la zona principal del usuario debe ser una de las cinco (o general)" do
      assert {:ok, _} = Usuario.crear("pepe", "1234", "ciudadano", "este")
      assert {:ok, _} = Usuario.crear("pepe", "1234", "ciudadano", "general")
      assert {:error, _} = Usuario.crear("pepe", "1234", "ciudadano", "zona_norte")
    end
  end

  describe "necesidades" do
    test "valida datos y transiciones; no se cierra dos veces" do
      assert {:error, _} = Necesidad.crear("N1", "agua", 0, "alta", "centro", "x", "u")
      assert {:error, _} = Necesidad.crear("N1", "gasolina", 5, "alta", "centro", "x", "u")
      {:ok, n} = Necesidad.crear("N1", "agua", 10, "Crítica", "centro", "x", "u")
      assert n.prioridad == "critica"
      assert {:error, _} = Necesidad.cambiar_estado(n, "en_atencion", "u")
      {:ok, n} = Necesidad.cambiar_estado(n, "cancelada", "u")
      assert {:error, mensaje} = Necesidad.cambiar_estado(n, "cancelada", "u")
      assert mensaje =~ "no se puede cerrar"
    end

    test "la prioridad ordena las necesidades" do
      crear = fn id, prioridad ->
        {:ok, n} = Necesidad.crear(id, "agua", 1, prioridad, "centro", "x", "u")
        n
      end

      ordenadas =
        Necesidad.ordenar([crear.("N1", "baja"), crear.("N2", "critica"), crear.("N3", "media")])

      assert Enum.map(ordenadas, & &1.id) == ["N2", "N3", "N1"]
    end
  end

  describe "mascotas" do
    test "el puntaje considera varios atributos y exige la misma especie" do
      {:ok, perdida} =
        Mascota.crear(
          "A",
          "lost",
          "perro",
          "Luna",
          "negro",
          "mediana",
          "norte",
          "1",
          "collar rojo",
          "u"
        )

      {:ok, encontrada} =
        Mascota.crear(
          "B",
          "found",
          "perro",
          "desconocido",
          "negro",
          "mediana",
          "norte",
          "2",
          "collar rojo",
          "u"
        )

      {:ok, gato} =
        Mascota.crear("C", "found", "gato", "Luna", "negro", "mediana", "norte", "3", "", "u")

      assert {80, _razones} = Mascota.puntaje(perdida, encontrada)
      assert {0, _} = Mascota.puntaje(perdida, gato)
      assert encontrada.nombre == nil
      assert Mascota.comunes(["a", "b", "c"], ["b", "c", "d"]) == 2
    end
  end

  describe "otras validaciones" do
    test "albergue: no supera la capacidad ni repite personas" do
      {:ok, a} = Albergue.crear("A01", "Norte", "norte", 1)
      {:ok, a} = Albergue.ingresar(a, "1", "u")
      assert {:error, _} = Albergue.ingresar(a, "1", "u")
      assert {:error, mensaje} = Albergue.ingresar(a, "2", "u")
      assert mensaje =~ "lleno"
      assert {:error, _} = Albergue.crear("A02", "X", "norte", -1)
    end

    test "persona: estados normalizados y reunificada es final" do
      {:ok, p} = Persona.crear("P1", "1094", "Andrés", "norte", "Sin información", nil, "u")
      assert p.estado == "sin_informacion"
      {:ok, p} = Persona.cambiar_estado(p, "reunificada", "u")
      assert {:error, _} = Persona.cambiar_estado(p, "localizada", "u")
      assert length(p.historial) == 2
    end

    test "usuario: contraseña con hash y tipos válidos" do
      {:ok, u} = Usuario.crear("Laura", "1234", "coordinador", "centro")
      assert u.username == "laura"
      refute u.hash == "1234"
      assert Usuario.password_correcta?(u, "1234")
      refute Usuario.password_correcta?(u, "otra")
      assert {:error, _} = Usuario.crear("x", "1234", "coordinador", "centro")
      assert {:error, _} = Usuario.crear("pepe", "1234", "rey", "centro")
    end

    test "parser: comillas, opciones y comillas sin cerrar" do
      assert {:ok, "reportar_mascota", ["perdida", "perro", "Luna"],
              %{"caracteristicas" => "collar rojo"}} =
               Analizador.analizar(
                 ~s(reportar_mascota perdida perro "Luna" caracteristicas="collar rojo")
               )

      assert {:error, _} = Analizador.analizar(~s(enviar_mensaje 1 "hola))
      assert Comun.siguiente_id("N", %{"N001" => 1}) == "N002"
    end
  end
end
