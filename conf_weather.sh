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
echo " - Ejecutar test de pantalla e-ink (auto-deteccion)"

# Root check
if [ "${EUID:-0}" -ne 0 ]; then
  echo "Ejecuta con sudo:"
  echo "  sudo bash ./conf_weather.sh"
  exit 1
fi

REAL_USER="${SUDO_USER:-pi}"
REAL_HOME="$(eval echo ~"${REAL_USER}")"
EPAPER_DIR="${REAL_HOME}/e-Paper"

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

# 4) Localizar waveshare_epd
echo "Buscando libreria waveshare_epd dentro de ${EPAPER_DIR} ..."
WAVESHARE_EPD_DIR_REL="$(sudo -u "${REAL_USER}" bash -lc "cd \"${EPAPER_DIR}\" && find . -type d -name waveshare_epd -print -quit" || true)"

if [ -z "${WAVESHARE_EPD_DIR_REL}" ]; then
  echo "ERROR: No se encontro ninguna carpeta llamada 'waveshare_epd' dentro de ${EPAPER_DIR}"
  exit 1
fi

WAVESHARE_EPD_DIR="${EPAPER_DIR}/${WAVESHARE_EPD_DIR_REL#./}"
echo "OK: waveshare_epd encontrada en:"
echo "  ${WAVESHARE_EPD_DIR}"

# 5) Verificar driver 2in13
echo "Comprobando archivos del modelo 2in13..."
if ls "${WAVESHARE_EPD_DIR}" | grep -qi "2in13"; then
  echo "Driver 2in13 encontrado."
else
  echo "AVISO: No se encontraron archivos 2in13 en ${WAVESHARE_EPD_DIR}"
  echo "Contenido:"
  ls -la "${WAVESHARE_EPD_DIR}" || true
fi

# 6) Auto-deteccion del script de test para 2in13
echo ""
echo "Buscando script de test para 2in13..."
TEST_REL="$(sudo -u "${REAL_USER}" bash -lc "cd \"${EPAPER_DIR}\" && find . -type f \\( -iname 'epd_2in13*_test.py' -o -iname '*2in13*test*.py' \\) -print | head -n 1" || true)"

if [ -z "${TEST_REL}" ]; then
  echo "AVISO: No se encontro ningun test tipo epd_2in13*_test.py en ${EPAPER_DIR}"
  echo "Puedes listar tests disponibles con:"
  echo "  cd ${EPAPER_DIR} && find . -type f -iname '*test*.py' | head -n 50"
  exit 0
fi

TEST_ABS="${EPAPER_DIR}/${TEST_REL#./}"
echo "OK: Test encontrado:"
echo "  ${TEST_ABS}"

# Ejecutar el test desde su carpeta
TEST_DIR="$(dirname "${TEST_ABS}")"
TEST_FILE="$(basename "${TEST_ABS}")"

echo "Ejecutando test..."
sudo -u "${REAL_USER}" bash -lc "
  set -e
  cd \"${TEST_DIR}\"
  python3 \"${TEST_FILE}\"
"

echo ""
echo "Si la pantalla se ha actualizado, todo correcto."
echo ""
echo "Script finalizado."
echo "Si es la primera vez que habilitas SPI, reinicia:"
echo "  sudo reboot"
