defmodule CodigosTest do
  @moduledoc """
  Pruebas del anexo "Base de datos de códigos": los registros aceptan el código
  (ES01, PE3, B07...) o el valor (perro, localizada...) y guardan el valor.
  """

  use ExUnit.Case, async: false

  import Emergencias.Prueba

  alias Emergencias.Anexos.Codigos
  alias Emergencias.Dominio.{Mascota, Persona}
  alias Emergencias.Sesion

  doctest Emergencias.Anexos.Codigos

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

    test "el barrio da la zona cuando no se escribe" do
      assert Codigos.ubicacion("", "b04") == {:ok, "sur", "B04"}
      assert {:error, mensaje} = Codigos.ubicacion("centro", "B99")
      assert mensaje =~ "Barrio inválido"
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
               Mascota.crear(nil, "MT1", "ES01", "Luna", "CO01", "TA2", "B07", "300", "", "ana")

      assert {m.tipo, m.especie, m.color, m.tamano, m.zona, m.barrio} ==
               {"perdida", "perro", "negro", "mediana", "norte", "B07"}
    end

    test "persona con códigos y datos opcionales" do
      assert {:ok, p} =
               Persona.crear(nil, "1094", "Andrés", "", "PE3", "34", "ana", %{
                 "tipo_doc" => "CC",
                 "barrio" => "B02",
                 "direccion" => "Calle 10 # 5-20"
               })

      assert {p.estado, p.tipo_documento, p.zona, p.barrio} ==
               {"localizada", "cedula", "centro", "B02"}

      assert Persona.to_string(p) =~ "barrio Granada (Armenia) (Calle 10 # 5-20)"
    end
  end

  describe "interfaces (web y ventanas)" do
    alias Emergencias.Interfaz.Acciones

    test "los campos con códigos muestran 'código – valor' y envían el código" do
      {:ok, accion} = Acciones.buscar("reportar_mascota")
      [tipo, especie | _] = accion.campos
      assert tipo.opciones == ["MT1", "MT2"]
      assert hd(especie.nombres) == "ES01 – perro"
      assert especie.libre
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

      cuerpo =
        JSON.encode!(%{
          token: token,
          comando: "reportar_mascota",
          valores: ["MT1", "ES02", "Misi", "CO09", "TA1", "B08", "300", "", "Calle 5"]
        })

      {"200 OK", _tipo, respuesta} =
        Emergencias.Web.Rutas.responder("POST", "/api/accion", cuerpo)

      assert %{"ok" => true, "texto" => texto} = JSON.decode!(respuesta)
      assert texto =~ "gato"
      assert texto =~ "barrio Laureles"
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

    test "reportar y filtrar mascotas con códigos", %{c: c} do
      assert {:ok, texto} =
               Sesion.ejecutar(
                 c,
                 ~s(reportar_mascota MT1 ES01 Luna CO01 TA2 B07 300 direccion="Parque")
               )

      assert texto =~ "perro"
      assert texto =~ "barrio La Castellana"

      assert {:ok, lista} = Sesion.ejecutar(c, "listar_mascotas especie=ES01 barrio=B07")
      assert lista =~ "Luna"
    end

    test "reportar y actualizar personas con códigos", %{c: c} do
      assert {:ok, _} =
               Sesion.ejecutar(c, ~s(reportar_persona 1094 "Andrés López" B02 PE3 tipo_doc=CC))

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
