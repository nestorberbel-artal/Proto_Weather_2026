#!/usr/bin/env bash
# conf_weather.sh (LF, bash-only, robusto)

# 0) Forzar bash aunque lo lancen con sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Este script requiere bash. Reiniciando con bash..."
  exec /usr/bin/env bash "$0" "$@"
fi

# 1) Auto-limpieza CRLF del propio archivo (por si Git/edicion metio \r)
#    (No rompe nada si ya esta OK.)
#    Nota: sed -i in-place puede fallar en FS raros, pero en RPi OS/Debian va bien.
if command -v sed >/dev/null 2>&1; then
  sed -i 's/\r$//' "$0" 2>/dev/null || true
fi

set -euo pipefail

echo "Configurando entorno Weather en Raspberry Pi:"
echo " - Instalar dependencias Python"
echo " - Habilitar SPI"
echo " - Clonar repositorio Waveshare e-Paper"
echo " - Verificar driver 2in13"
echo " - Ejecutar test de pantalla e-ink"

# 2) Root check
if [ "${EUID:-0}" -ne 0 ]; then
  echo "Ejecuta con sudo:"
  echo "  sudo ./conf_weather.sh"
  exit 1
fi

# 3) Usuario real (para clonar en su HOME)
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(eval echo ~"${REAL_USER}")"

# --- OPCIONAL: limpiar nombres con \r en el directorio actual ---
# Si sueles arrastrar archivos con \r en el nombre, descomenta este bloque.
# (No afecta al funcionamiento normal.)
# for f in ./*$'\r'; do
#   [ -e "$f" ] || continue
#   mv -- "$f" "${f%$'\r'}"
# done

# 4) Dependencias (SIN actualizar el SO; eso lo haces en el script previo)
echo "Instalando dependencias..."
apt install -y python3-requests python3-pil fonts-dejavu-core git

# 5) Habilitar SPI
if command -v raspi-config >/dev/null 2>&1; then
  echo "Habilitando SPI via raspi-config..."
  raspi-config nonint do_spi 0 || true
else
  echo "raspi-config no disponible. Aplicando fallback..."

  BOOTDIR="/boot/firmware"
  [ -d "$BOOTDIR" ] || BOOTDIR="/boot"

  CONFIG_FILE="$BOOTDIR/config.txt"
  USERCFG="$BOOTDIR/usercfg.txt"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "No se encontro $CONFIG_FILE"
    exit 1
  fi

  cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

  touch "$USERCFG"
  cp -a "$USERCFG" "${USERCFG}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

  # Comentar spi=off si existe
  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$CONFIG_FILE" || true
  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$USERCFG" || true

  # Asegurar spi=on en usercfg
  grep -q '^dtparam=spi=on$' "$USERCFG" || echo "dtparam=spi=on" >> "$USERCFG"
fi

# 6) Cargar modulos SPI
echo "Cargando modulos SPI..."
modprobe spi_bcm2835 2>/dev/null || true
modprobe spidev 2>/dev/null || true

# 7) Verificar /dev/spidev*
echo "Verificando dispositivos SPI..."
ls /dev/spidev* 2>/dev/null || echo "Aun no visibles (requiere reboot)"

# 8) Clonar/actualizar Waveshare e-Paper (en HOME del usuario real)
echo "Clonando/actualizando repositorio Waveshare e-Paper..."
sudo -u "${REAL_USER}" bash -lc "
  set -e
  cd \"${REAL_HOME}\"
  if [ ! -d \"e-Paper\" ]; then
    git clone https://github.com/waveshare/e-Paper.git
  else
    cd e-Paper
    git pull
  fi
"

# 9) Comprobar driver 2in13
echo "Comprobando archivos del modelo 2in13..."
EPD_PATH="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"

if [ -d "$EPD_PATH" ]; then
  ls "$EPD_PATH" | grep -q 2in13 && echo "Driver 2in13 encontrado." || echo "No se encontraron archivos 2in13 en waveshare_epd"
else
  echo "No se encontro la ruta $EPD_PATH"
fi

# 10) Test pantalla e-ink 2in13 V3
echo ""
echo "Ejecutando test de la pantalla e-ink 2in13 V3..."
EXAMPLES_PATH="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/examples"
TEST_SCRIPT="epd_2in13_V3_test.py"

if [ -d "$EXAMPLES_PATH" ]; then
  if [ -f "${EXAMPLES_PATH}/${TEST_SCRIPT}" ]; then
    sudo -u "${REAL_USER}" bash -lc "
      set -e
      cd \"${EXAMPLES_PATH}\"
      python3 \"${TEST_SCRIPT}\"
    "
    echo ""
    echo "Si la pantalla se ha actualizado, todo funciona correctamente."
  else
    echo "No s
