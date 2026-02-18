#!/usr/bin/env bash

# Forzar bash aunque lo lancen con sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Este script requiere bash. Reiniciando con bash..."
  exec /usr/bin/env bash "$0" "$@"
fi

# Auto-limpieza CRLF (por si llega con \r)
sed -i 's/\r$//' "$0" 2>/dev/null || true

set -euo pipefail

echo "Configurando entorno Weather en Raspberry Pi:"
echo " - Instalar dependencias Python"
echo " - Habilitar SPI"
echo " - Clonar repositorio Waveshare e-Paper"
echo " - Localizar libreria waveshare_epd"
echo " - Verificar driver 2in13"
echo " - Ejecutar test de pantalla e-ink"

# Root check
if [ "${EUID:-0}" -ne 0 ]; then
  echo "Ejecuta con sudo:"
  echo "  sudo bash ./conf_weather.sh"
  exit 1
fi

REAL_USER="${SUDO_USER:-pi}"
REAL_HOME="$(eval echo ~"${REAL_USER}")"

# 1) Dependencias (sin upgrade completo)
echo "Instalando dependencias..."
apt update
apt install -y python3-requests python3-pil fonts-dejavu-core git

# 2) Habilitar SPI
if command -v raspi-config >/dev/null 2>&1; then
  echo "Habilitando SPI via raspi-config..."
  raspi-config nonint do_spi 0 || true
else
  echo "raspi-config no disponible. Aplicando fallback..."
  BOOTDIR="/boot/firmware"
  [ -d "$BOOTDIR" ] || BOOTDIR="/boot"
  CONFIG_FILE="$BOOTDIR/config.txt"
  USERCFG="$BOOTDIR/usercfg.txt"

  cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  touch "$USERCFG"
  cp -a "$USERCFG" "${USERCFG}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$CONFIG_FILE" || true
  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$USERCFG" || true
  grep -q '^dtparam=spi=on$' "$USERCFG" || echo "dtparam=spi=on" >> "$USERCFG"
fi

echo "Cargando modulos SPI..."
modprobe spi_bcm2835 2>/dev/null || true
modprobe spidev 2>/dev/null || true

echo "Verificando dispositivos SPI..."
ls /dev/spidev* 2>/dev/null || echo "Aun no visibles (requiere reboot)"

# 3) Waveshare e-Paper: clonar/actualizar como usuario real
echo "Clonando/actualizando Waveshare e-Paper (como ${REAL_USER})..."
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

# 4) Localizar waveshare_epd de forma automatica
echo "Buscando libreria waveshare_epd dentro de ${REAL_HOME}/e-Paper ..."
WAVESHARE_EPD_DIR="$(sudo -u "${REAL_USER}" bash -lc "cd \"${REAL_HOME}/e-Paper\" && find . -type d -name waveshare_epd -print -quit" || true)"

if [ -z "${WAVESHARE_EPD_DIR}" ]; then
  echo "ERROR: No se encontro ninguna carpeta llamada 'waveshare_epd' dentro de ${REAL_HOME}/e-Paper"
  echo "Sugerencia: revisa la estructura con:"
  echo "  ls -la ${REAL_HOME}/e-Paper"
  exit 1
fi

# Convertir a ruta absoluta
WAVESHARE_EPD_DIR_ABS="${REAL_HOME}/e-Paper/${WAVESHARE_EPD_DIR#./}"
echo "OK: waveshare_epd encontrada en:"
echo "  ${WAVESHARE_EPD_DIR_ABS}"

# 5) Comprobar driver 2in13
echo "Comprobando archivos del modelo 2in13..."
if ls "${WAVESHARE_EPD_DIR_ABS}" | grep -q "2in13"; then
  echo "Driver 2in13 encontrado."
else
  echo "AVISO: No se encontraron archivos 2in13 en ${WAVESHARE_EPD_DIR_ABS}"
  echo "Contenido:"
  ls -la "${WAVESHARE_EPD_DIR_ABS}" || true
fi

# 6) Localizar carpeta examples y ejecutar test 2in13 V3 si existe
echo ""
echo "Buscando carpeta 'examples' para ejecutar el test..."
EXAMPLES_DIR="$(sudo -u "${REAL_USER}" bash -lc "cd \"${REAL_HOME}/e-Paper\" && find . -type d -name examples -print -quit" || true)"

if [ -z "${EXAMPLES_DIR}" ]; then
  echo "ERROR: No se encontro ninguna carpeta 'examples' dentro de ${REAL_HOME}/e-Paper"
  exit 1
fi

EXAMPLES_DIR_ABS="${REAL_HOME}/e-Paper/${EXAMPLES_DIR#./}"
TEST_SCRIPT="epd_2in13_V3_test.py"

echo "Carpeta examples encontrada en:"
echo "  ${EXAMPLES_DIR_ABS}"

if [ -f "${EXAMPLES_DIR_ABS}/${TEST_SCRIPT}" ]; then
  echo "Ejecutando test ${TEST_SCRIPT}..."
  sudo -u "${REAL_USER}" bash -lc "
    set -e
    cd \"${EXAMPLES_DIR_ABS}\"
    python3 \"${TEST_SCRIPT}\"
  "
  echo ""
  echo "Si la pantalla se ha actualizado, todo correcto."
else
  echo "AVISO: No se encontro ${TEST_SCRIPT} en ${EXAMPLES_DIR_ABS}"
  echo "Scripts disponibles:"
  ls -1 "${EXAMPLES_DIR_ABS}" | head -n 50 | sed 's/^/ - /'
  echo ""
  echo "Revisa la version exacta de tu pantalla (V2/V3/V4) y ejecuta el script adecuado."
fi

echo ""
echo "Script finalizado."
echo "Si es la primera vez que habilitas SPI, reinicia:"
echo "  sudo reboot"
