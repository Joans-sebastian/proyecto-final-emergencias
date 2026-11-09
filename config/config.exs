import Config

# Carpeta donde se guardan los archivos de texto plano (persistencia).
config :emergencias, directorio_datos: "datos"

if config_env() == :test do
  # Las pruebas usan su propia carpeta para no tocar los datos reales.
  config :emergencias, directorio_datos: "tmp/datos_test"
  config :logger, level: :warning
end
