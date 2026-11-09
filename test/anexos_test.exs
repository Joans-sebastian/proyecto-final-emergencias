defmodule AnexosTest do
  @moduledoc """
  Pruebas del anexo "Aplicaciones distribuidas": el proceso registrado
  :servicio_emergencias atiende mensajes con send/receive.

  Se le envían los mensajes con la tupla {nombre, nodo}, igual que desde otro
  nodo; aquí el nodo es el mismo de las pruebas (node()).
  """

  use ExUnit.Case, async: false

  import Emergencias.Prueba

  doctest Emergencias.Anexos.Nodo

  @servicio {:servicio_emergencias, node()}

  setup do
    reiniciar()
    coordinador = sesion("laura", "coordinador")

    preparar(coordinador, [
      ~s(registrar_zona centro "Zona Centro" critico 1000),
      ~s(registrar_zona norte "Zona Norte" alto 500),
      ~s(registrar_necesidad agua 30 critica centro "Punto de atención sector 3")
    ])

    :ok
  end

  test "el servicio queda registrado con su nombre" do
    assert is_pid(Process.whereis(:servicio_emergencias))
  end

  test "sin conectarse, el servicio pide usuario y contraseña" do
    send(@servicio, {:comando, self(), "listar_zonas"})
    assert_receive {:error, mensaje}
    assert mensaje =~ "Primero debe conectarse"
  end

  test "conectar, ejecutar un comando con los permisos del rol y terminar con :adios" do
    send(@servicio, {:conectar, self(), "laura", "1234"})
    assert_receive {:conectado, mensaje}
    assert mensaje =~ "Bienvenido"

    send(@servicio, {:comando, self(), "necesidades_pendientes"})
    assert_receive {:respuesta, texto}
    assert texto =~ "agua"

    send(@servicio, {:fin, self()})
    assert_receive :adios
  end

  test "una contraseña incorrecta se rechaza" do
    send(@servicio, {:conectar, self(), "laura", "mala"})
    assert_receive {:error, mensaje}
    assert mensaje =~ "Contraseña incorrecta"
  end

  test "un ciudadano no puede ejecutar comandos de coordinador" do
    send(@servicio, {:conectar, self(), "pedro", "abcd"})
    assert_receive {:conectado, _}

    send(@servicio, {:comando, self(), "registrar_recurso R009 agua 10 litros bodega"})
    assert_receive {:error, _mensaje}
  end

  test "el estado de todas las zonas llega en una sola respuesta (consultas en paralelo)" do
    send(@servicio, {:conectar, self(), "laura", "1234"})
    assert_receive {:conectado, _}

    send(@servicio, {:estado_zonas, self()})
    assert_receive {:estado_zonas, textos}, 5_000
    assert length(textos) == 2
    assert Enum.any?(textos, &(&1 =~ "Zona Centro"))
    assert Enum.any?(textos, &(&1 =~ "Zona Norte"))
  end

  test "varios clientes a la vez reciben cada uno su propia respuesta" do
    yo = self()

    clientes =
      for usuario <- ["ana", "beto", "carla"] do
        spawn(fn ->
          send(@servicio, {:conectar, self(), usuario, "1234"})

          receive do
            {:conectado, _} -> send(@servicio, {:comando, self(), "quien_soy"})
          end

          receive do
            {:respuesta, texto} -> send(yo, {:listo, usuario, texto})
          end
        end)
      end

    for usuario <- ["ana", "beto", "carla"] do
      assert_receive {:listo, ^usuario, texto}, 5_000
      assert texto =~ usuario
    end

    assert length(clientes) == 3
  end

  test "si el cliente se cae sin enviar :fin, su sesión se cierra" do
    cliente =
      spawn(fn ->
        send(@servicio, {:conectar, self(), "diego", "1234"})

        receive do
          {:conectado, _} -> :ok
        end
      end)

    ref = Process.monitor(cliente)
    assert_receive {:DOWN, ^ref, :process, ^cliente, _}, 2_000
    # El servicio recibe su propio {:DOWN, ...} y libera la sesión.
    Process.sleep(100)
    refute "diego" in Emergencias.Sesiones.activas()
  end
end
