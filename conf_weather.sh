#!/usr/bin/env bash

# Forzar bash aunque lo lancen con sh
if [ -z "${BASH_VERSION:-}" ]; then
  echo "🔁 Este script requiere bash. Reiniciando con bash..."
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

echo "🌦️ Configurando entorno Weather en Raspberry Pi:"
echo "   - Instalar dependencias Python"
echo "   - Habilitar SPI"
echo "   - Clonar repositorio Waveshare e-Paper"
echo "   - Verificar driver 2in13"
echo "   - Ejecutar test de pantalla e-ink"

# 1) Root
if [ "${EUID:-0}" -ne 0 ]; then
  echo "❌ Ejecuta con sudo:"
  echo "   sudo ./conf_weather.sh"
  exit 1
fi

# Usuario real (para trabajar en su HOME)
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(eval echo ~"${REAL_USER}")"

# 2) Instalar dependencias (SIN actualizar el SO)
echo "📦 Instalando dependencias..."
apt install -y python3-requests python3-pil fonts-dejavu-core git

# 3) Habilitar SPI usando raspi-config
if command -v raspi-config >/dev/null 2>&1; then
  echo "🛠️ Habilitando SPI vía raspi-config..."
  raspi-config nonint do_spi 0
else
  echo "⚠️ raspi-config no disponible. Aplicando fallback..."

  BOOTDIR="/boot/firmware"
  if [ ! -d "$BOOTDIR" ]; then
    BOOTDIR="/boot"
  fi

  CONFIG_FILE="$BOOTDIR/config.txt"
  USERCFG="$BOOTDIR/usercfg.txt"

  cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

  touch "$USERCFG"
  cp -a "$USERCFG" "${USERCFG}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$CONFIG_FILE" || true
  sed -i 's/^dtparam=spi=off/#dtparam=spi=off/' "$USERCFG" || true

  if ! grep -q '^dtparam=spi=on$' "$USERCFG"; then
    echo "dtparam=spi=on" >> "$USERCFG"
  fi
fi

# 4) Cargar módulos
echo "🧩 Cargando módulos SPI..."
modprobe spi_bcm2835 2>/dev/null || true
modprobe spidev 2>/dev/null || true

# 5) Verificación SPI
echo "🔎 Verificando dispositivos SPI..."
ls /dev/spidev* 2>/dev/null || echo "Aún no visibles (requiere reboot)"

# 6) Clonar repositorio Waveshare e-Paper (en HOME del usuario real)
echo "📥 Clonando repositorio Waveshare e-Paper..."
sudo -u "${REAL_USER}" bash -lc "
  cd \"${REAL_HOME}\"
  if [ ! -d \"e-Paper\" ]; then
    git clone https://github.com/waveshare/e-Paper.git
  else
    echo \"📁 La carpeta e-Paper ya existe, actualizando...\"
    cd e-Paper
    git pull
  fi
"

# 7) Comprobación del modelo 2in13
echo "🔎 Comprobando archivos del modelo 2in13..."
EPD_PATH="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"

if [ -d "$EPD_PATH" ]; then
  ls "$EPD_PATH" | grep 2in13 || echo "⚠️ No se encontraron archivos 2in13 en waveshare_epd"
else
  echo "❌ No se encontró la ruta $EPD_PATH"
fi

# 8) Test automático pantalla e-ink 2in13 V3
echo ""
echo "🧪 Ejecutando test de la pantalla e-ink 2in13 V3..."

EXAMPLES_PATH="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/examples"

if [ -d "$EXAMPLES_PATH" ]; then
  if [ -f "${EXAMPLES_PATH}/epd_2in13_V3_test.py" ]; then
    sudo -u "${REAL_USER}" bash -lc "
      cd \"${EXAMPLES_PATH}\"
      python3 epd_2in13_V3_test.py
    "
    echo ""
    echo "✔️ Si la pantalla se ha actualizado, todo funciona correctamente."
  else
    echo "⚠️ No se encontró epd_2in13_V3_test.py"
    echo "Revisa la versión exacta de tu pantalla (V2, V3, V4...)."
  fi
else
  echo "❌ No se encontró la carpeta de ejemplos."
fi

echo ""
echo "✅ Script finalizado."
echo "⚠️ Si es la primera vez que habilitas SPI, reinicia antes de repetir el test:"
echo "   sudo reboot"
