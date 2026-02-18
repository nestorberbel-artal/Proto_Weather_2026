#!/usr/bin/env bash

# Forzar bash aunque lo lancen con sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Este script requiere bash. Reiniciando con bash..."
  exec /usr/bin/env bash "$0" "$@"
fi

# Auto-limpieza CRLF del propio archivo (por si llego con \r)
sed -i 's/\r$//' "$0" 2>/dev/null || true

set -euo pipefail

echo "Configurando entorno Weather en Raspberry Pi:"
echo " - Instalar dependencias Python"
echo " - Habilitar SPI"
echo " - Clonar repositorio Waveshare e-Paper"
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

# 1) Dependencias (sin upgrade del SO)
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

# 3) Waveshare e-Paper: SIEMPRE como usuario REAL (no root) para evitar 'dubious ownership'
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

echo "Comprobando driver 2in13..."
EPD_PATH=\"${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd\"
if [ -d \"${EPD_PATH}\" ]; then
  ls \"${EPD_PATH}\" | grep -q 2in13 && echo \"Driver 2in13 encontrado.\" || echo \"No se encontraron archivos 2in13.\"
else
  echo \"No se encontro la ruta ${EPD_PATH}\"
fi

echo ""
echo "Ejecutando test 2in13 V3..."
EXAMPLES_PATH=\"${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/examples\"
TEST_SCRIPT=\"epd_2in13_V3_test.py\"

if [ -d \"${EXAMPLES_PATH}\" ]; then
  if [ -f \"${EXAMPLES_PATH}/${TEST_SCRIPT}\" ]; then
    sudo -u \"${REAL_USER}\" bash -lc \"
      set -e
      cd \\\"${EXAMPLES_PATH}\\\"
      python3 \\\"${TEST_SCRIPT}\\\"
    \"
    echo \"Si la pantalla se ha actualizado, todo correcto.\"
  else
    echo \"No se encontro ${TEST_SCRIPT} (revisa V2/V3/V4).\"
  fi
else
  echo \"No se encontro la carpeta de ejemplos.\"
fi

echo ""
echo "Script finalizado."
echo "Si es la primera vez que habilitas SPI, reinicia:"
echo "  sudo reboot"
