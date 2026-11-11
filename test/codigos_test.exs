defmodule CodigosTest do
  @moduledoc """
  Pruebas del anexo "Base de datos de códigos": los registros aceptan el código
  (ES01, PE3, B01...) o el valor (perro, localizada...) y guardan el valor.
  Especie y color solo aceptan sus códigos (con "otro" se escribe cuál) y los
  barrios se registran a mano: B01, B02... en orden.
  """

  use ExUnit.Case, async: false

  import Emergencias.Prueba

  alias Emergencias.Anexos.{Barrios, Codigos}
  alias Emergencias.Dominio.{Mascota, Persona}
  alias Emergencias.Sesion

  doctest Emergencias.Anexos.Codigos
  doctest Emergencias.Anexos.Barrios

  describe "tablas (funciones puras)" do
    test "traducir acepta el código en mayúsculas o minúsculas y deja igual lo que no es código" do
      assert Codigos.traducir("color", "co01") == "negro"
      assert Codigos.traducir("estado_persona", "PE5") == "en_albergue"
      assert Codigos.traducir("especie", "perro") == "perro"
      assert Codigos.traducir("especie", "XX99") == "XX99"
    end

    test "cada tabla tiene códigos únicos" do
      for tabla <- Codigos.nombres() do
        codigos = Enum.map(Codigos.filas(tabla), & &1.codigo)
        assert codigos == Enum.uniq(codigos), "códigos repetidos en #{tabla}"
      end
    end

    test "los valores de las tablas coinciden con las listas cerradas del dominio" do
      valores = &Enum.map(Codigos.filas(&1), fn f -> f.valor end)
      assert valores.("estado_persona") == Persona.estados()
      assert valores.("tipo_necesidad") == Emergencias.Dominio.Necesidad.tipos()
      assert valores.("prioridad") == Emergencias.Dominio.Necesidad.prioridades()
      assert valores.("nivel") == Emergencias.Dominio.Zona.niveles()
      assert valores.("rol") == Emergencias.Dominio.Usuario.tipos()
    end

    test "especie y color: solo sus códigos; con otro se escribe cuál" do
      assert Enum.map(Codigos.filas("especie"), &{&1.codigo, &1.valor}) ==
               [{"ES01", "perro"}, {"ES02", "gato"}, {"ES03", "otro"}]

      assert Enum.map(Codigos.filas("color"), &{&1.codigo, &1.valor}) ==
               [
                 {"CO01", "negro"},
                 {"CO02", "blanco"},
                 {"CO03", "cafe"},
                 {"CO04", "gris"},
                 {"CO05", "otro"}
               ]

      assert Codigos.con_otro("especie", "ES02", nil) == {:ok, "gato"}
      assert Codigos.con_otro("color", "CO05", "Atigrado") == {:ok, "atigrado"}
      assert {:error, mensaje} = Codigos.con_otro("especie", "ES03", "")
      assert mensaje =~ "especie_otra"
      assert {:error, mensaje} = Codigos.con_otro("especie", "iguana", nil)
      assert mensaje =~ "ES01=perro, ES02=gato, ES03=otro"
    end

    test "formato de tabla con bordes y tabla desconocida" do
      assert {:ok, texto} = Codigos.formato_tabla("tamano")
      assert texto =~ "| TA2    | mediana |"
      assert {:error, _} = Codigos.formato_tabla("planetas")
    end
  end

  describe "entidades con códigos" do
    test "mascota con códigos guarda los valores" do
      assert {:ok, m} =
               Mascota.crear(nil, "MT1", "ES01", "Luna", "CO01", "TA2", "norte", "300", "", "ana")

      assert {m.tipo, m.especie, m.color, m.tamano, m.zona} ==
               {"perdida", "perro", "negro", "mediana", "norte"}
    end

    test "mascota con especie y color 'otro' guarda lo que se escribió" do
      extras = %{"especie_otra" => "Conejo", "color_otro" => "Atigrado"}

      assert {:ok, m} =
               Mascota.crear(nil, "MT2", "ES03", "", "CO05", "TA1", "norte", "300", "", "ana", extras)

      assert {m.especie, m.color} == {"conejo", "atigrado"}

      assert {:error, mensaje} =
               Mascota.crear(nil, "MT2", "ES03", "", "CO01", "TA1", "norte", "300", "", "ana")

      assert mensaje =~ "especie_otra"
    end
  end

  describe "barrios registrados a mano" do
    setup do
      reiniciar()
      :ok
    end

    test "reciben B01, B02... en orden y no se repiten" do
      assert Codigos.filas("barrio") == []
      assert {:ok, %{codigo: "B01"}, :nuevo} = Barrios.registrar("La Castellana", "norte")
      assert {:ok, %{codigo: "B02"}, :nuevo} = Barrios.registrar("Granada", "centro")
      assert {:ok, %{codigo: "B01"}, :existente} = Barrios.registrar("la castellana", "norte")
      assert Enum.map(Codigos.filas("barrio"), & &1.codigo) == ["B01", "B02"]
      assert {:error, _} = Barrios.registrar("Sin zona", "")
    end

    test "el barrio da la zona y uno nuevo se registra con la zona escrita" do
      {:ok, _, _} = Barrios.registrar("Los Quindos", "sur")
      assert Codigos.ubicacion("", "b01") == {:ok, "sur", "B01"}
      assert Codigos.ubicacion("B01", nil) == {:ok, "sur", "B01"}
      assert Codigos.ubicacion("centro", "Granada") == {:ok, "centro", "B02"}
      assert {:error, mensaje} = Codigos.ubicacion("centro", "B99")
      assert mensaje =~ "no está registrado"
      assert {:error, mensaje} = Codigos.ubicacion("", "Barrio sin zona")
      assert mensaje =~ "escriba también la zona"
    end

    test "persona con barrio registrado y datos opcionales" do
      {:ok, _, _} = Barrios.registrar("Granada", "centro")

      assert {:ok, p} =
               Persona.crear(nil, "1094", "Andrés", "", "PE3", "34", "ana", %{
                 "tipo_doc" => "CC",
                 "barrio" => "B01",
                 "direccion" => "Calle 10 # 5-20"
               })

      assert {p.estado, p.tipo_documento, p.zona, p.barrio} ==
               {"localizada", "cedula", "centro", "B01"}

      assert Persona.to_string(p) =~ "barrio Granada (zona centro) (Calle 10 # 5-20)"
    end

    test "los barrios se guardan en barrios.txt y vuelven al reiniciar" do
      {:ok, _, _} = Barrios.registrar("La Patria", "sur")
      Application.stop(:emergencias)
      {:ok, _} = Application.ensure_all_started(:emergencias)
      assert [%{codigo: "B01", nombre: "La Patria", zona: "sur"}] = Barrios.listar()
    end
  end

  describe "interfaces (web y ventanas)" do
    alias Emergencias.Interfaz.Acciones

    test "los campos con códigos muestran 'código – valor' y envían el código" do
      {:ok, accion} = Acciones.buscar("reportar_mascota")
      [tipo, especie | _] = accion.campos
      assert tipo.opciones == ["MT1", "MT2"]
      assert especie.nombres == ["ES01 – perro", "ES02 – gato", "ES03 – otro"]
      refute especie.libre
      assert Acciones.texto_ventana(tipo) == "Tipo de reporte|MT1 – perdida|MT2 – encontrada"
    end

    test "acciones con el mismo comando se distinguen por id" do
      assert {:ok, %{comando: "buscar_persona", campos: []}} = Acciones.buscar("buscar_personas")
      assert {:ok, %{comando: "codigos", campos: [_]}} = Acciones.buscar("codigos_tabla")
    end

    test "la web registra una mascota con códigos" do
      reiniciar()
      c = sesion("laura", "coordinador")
      preparar(c, [~s(registrar_zona norte "Zona Norte" NV2 500)])
      start_supervised!(Emergencias.Web.Fichas)
      token = Emergencias.Web.Fichas.crear("laura")

      # Campos: tipo, especie, nombre, color, tamaño, zona, contacto, y los opcionales
      # características, dirección, especie_otra, color_otro y barrio (uno nuevo).
      cuerpo =
        JSON.encode!(%{
          token: token,
          comando: "reportar_mascota",
          valores:
            ["MT1", "ES02", "Misi", "CO05", "TA1", "norte", "300"] ++
              ["", "Calle 5", "", "atigrado", "Laureles"]
        })

      {"200 OK", _tipo, respuesta} =
        Emergencias.Web.Rutas.responder("POST", "/api/accion", cuerpo)

      assert %{"ok" => true, "texto" => texto} = JSON.decode!(respuesta)
      assert texto =~ "gato"
      assert texto =~ "atigrado"
      assert texto =~ "barrio Laureles (zona norte)"
      assert [%{codigo: "B01", nombre: "Laureles"}] = Barrios.listar()
    end
  end

  describe "comandos" do
    setup do
      reiniciar()
      c = sesion("laura", "coordinador")

      preparar(c, [
        ~s(registrar_zona norte "Zona Norte" NV2 500),
        ~s(registrar_zona centro "Zona Centro" NV1 1000)
      ])

      {:ok, c: c}
    end

    test "codigos muestra el índice y una tabla", %{c: c} do
      assert {:ok, indice} = Sesion.ejecutar(c, "codigos")
      assert indice =~ "BASE DE DATOS DE CÓDIGOS"
      assert {:ok, tabla} = Sesion.ejecutar(c, "codigos especie")
      assert tabla =~ "ES01"
    end

    test "registrar_barrio da B01, B02... y se usa al reportar", %{c: c} do
      assert {:ok, "Barrio registrado: B01 – La Castellana (zona norte)"} =
               Sesion.ejecutar(c, ~s(registrar_barrio "La Castellana" norte))

      assert {:ok, "Barrio registrado: B02 – Granada (zona centro)"} =
               Sesion.ejecutar(c, "registrar_barrio Granada centro")

      assert {:ok, texto} = Sesion.ejecutar(c, ~s(registrar_barrio "la castellana" norte))
      assert texto =~ "ya estaba registrado: B01"
      assert {:ok, tabla} = Sesion.ejecutar(c, "codigos barrio")
      assert tabla =~ "| B02    | Granada"
    end

    test "reportar y filtrar mascotas con códigos", %{c: c} do
      preparar(c, [~s(registrar_barrio "La Castellana" norte)])

      assert {:ok, texto} =
               Sesion.ejecutar(
                 c,
                 ~s(reportar_mascota MT1 ES01 Luna CO01 TA2 B01 300 direccion="Parque")
               )

      assert texto =~ "perro"
      assert texto =~ "barrio La Castellana"

      assert {:ok, _} =
               Sesion.ejecutar(
                 c,
                 "reportar_mascota MT2 ES03 desconocido CO05 TA1 norte 301 especie_otra=conejo color_otro=atigrado"
               )

      assert {:ok, lista} = Sesion.ejecutar(c, "listar_mascotas especie=ES01 barrio=B01")
      assert lista =~ "Luna"
      refute lista =~ "conejo"
      assert {:ok, otras} = Sesion.ejecutar(c, "listar_mascotas especie=ES03")
      assert otras =~ "conejo"
      refute otras =~ "Luna"
    end

    test "reportar y actualizar personas con códigos", %{c: c} do
      assert {:ok, _} =
               Sesion.ejecutar(
                 c,
                 ~s(reportar_persona 1094 "Andrés López" centro PE3 tipo_doc=CC barrio=Granada)
               )

      assert {:ok, texto} = Sesion.ejecutar(c, "actualizar_persona 1094 PE5")
      assert texto =~ "en_albergue"
      assert {:ok, lista} = Sesion.ejecutar(c, "buscar_persona estado=PE5")
      assert lista =~ "Andrés"
    end

    test "necesidades con códigos", %{c: c} do
      assert {:ok, texto} =
               Sesion.ejecutar(c, ~s(registrar_necesidad NT01 30 PR1 centro "Punto 3"))

      assert texto =~ "agua"
      assert {:ok, lista} = Sesion.ejecutar(c, "listar_necesidades prioridad=PR1")
      assert lista =~ "agua"
    end
  end
end
