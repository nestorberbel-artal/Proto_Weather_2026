#!/bin/bash
set -euo pipefail

###############################################################################
# conf_weather.sh
# Configuración completa para Proto_Weather_2026 (Raspberry Pi OS / Debian)
# - Instala dependencias necesarias
# - Habilita SPI (compatible con Trixie: /boot/firmware/config.txt)
# - Clona Waveshare e-Paper
# - Comprueba driver 2in13
# - Ejecuta test de pantalla e-ink 2.13" V3
###############################################################################

log()  { echo -e "✅ $*"; }
info() { echo -e "ℹ️  $*"; }
warn() { echo -e "⚠️  $*"; }
err()  { echo -e "❌ $*" >&2; }

# 1️⃣ Comprobar root
if [ "${EUID:-0}" -ne 0 ]; then
  err "Ejecuta este script con sudo:"
  echo "   sudo bash conf_weather.sh"
  exit 1
fi

# Usuario real (para trabajar en su HOME)
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(eval echo ~"${REAL_USER}")"

echo "🌦️ conf_weather.sh — Configuración completa de Proto Weather 2026"
info "Usuario objetivo: ${REAL_USER}"
info "HOME objetivo: ${REAL_HOME}"
echo

# 2️⃣ Instalar dependencias necesarias
info "Instalando dependencias..."
apt install -y python3-requests python3-pil fonts-dejavu-core git
log "Dependencias instaladas."
echo

# 3️⃣ Habilitar SPI (compatible Trixie / Bookworm)
enable_spi_config_txt() {
  local cfg=""

  if [ -f "/boot/firmware/config.txt" ]; then
    cfg="/boot/firmware/config.txt"
  elif [ -f "/boot/config.txt" ]; then
    cfg="/boot/config.txt"
  else
    err "No se encontró config.txt en /boot/firmware ni en /boot."
    return 1
  fi

  info "Habilitando SPI en: ${cfg}"

  if grep -qE '^[[:space:]]*dtparam=spi=off[[:space:]]*$' "$cfg"; then
    sed -i 's/^[[:space:]]*dtparam=spi=off[[:space:]]*$/dtparam=spi=on/' "$cfg"
    log "Cambiado dtparam=spi=off → dtparam=spi=on"
  elif grep -qE '^[[:space:]]*dtparam=spi=on[[:space:]]*$' "$cfg"; then
    log "SPI ya estaba activado."
  else
    echo "" >> "$cfg"
    echo "# Habilitar SPI (añadido por conf_weather.sh)" >> "$cfg"
    echo "dtparam=spi=on" >> "$cfg"
    log "Añadido dtparam=spi=on"
  fi

  # Intentar también con raspi-config si existe
  if command -v raspi-config >/dev/null 2>&1; then
    info "Aplicando raspi-config do_spi..."
    set +e
    raspi-config nonint do_spi 0 >/dev/null 2>&1
    set -e
    log "raspi-config aplicado (o ya estaba)."
  fi

  # Cargar módulos
  info "Cargando módulos SPI..."
  modprobe spi_bcm2835 >/dev/null 2>&1 || true
  modprobe spidev >/dev/null 2>&1 || true

  # Asegurar carga persistente
  mkdir -p /etc/modules-load.d
  cat > /etc/modules-load.d/spi.conf <<'EOF'
# Módulos SPI (añadido por conf_weather.sh)
spi_bcm2835
spidev
EOF

  log "SPI configurado (puede requerir reinicio)."
}

enable_spi_config_txt
echo

# 4️⃣ Clonar Waveshare e-Paper
info "Clonando Waveshare e-Paper en ${REAL_HOME}..."
sudo -u "${REAL_USER}" bash -lc "
  cd \"${REAL_HOME}\"
  if [ ! -d \"e-Paper\" ]; then
    git clone https://github.com/waveshare/e-Paper.git
  else
    cd e-Paper
    git pull
  fi
"
log "Repositorio Waveshare preparado."
echo

# 5️⃣ Comprobación driver 2in13
info "Comprobando driver 2in13..."
WAVESHARE_DRIVER_DIR="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"

if [ ! -d "${WAVESHARE_DRIVER_DIR}" ]; then
  err "No existe el directorio esperado:"
  err "${WAVESHARE_DRIVER_DIR}"
  exit 1
fi

if ls "${WAVESHARE_DRIVER_DIR}" | grep -q "2in13"; then
  log "Driver 2in13 encontrado."
else
  err "No se encontró '2in13' en ${WAVESHARE_DRIVER_DIR}"
  ls -la "${WAVESHARE_DRIVER_DIR}" || true
  exit 1
fi
echo

# 6️⃣ Ejecutar test de la pantalla e-ink
info "Ejecutando test de pantalla e-ink 2in13 V3..."
EXAMPLES_DIR="${REAL_HOME}/e-Paper/RaspberryPi_JetsonNano/python/examples"
TEST_SCRIPT="epd_2in13_V3_test.py"

if [ ! -f "${EXAMPLES_DIR}/${TEST_SCRIPT}" ]; then
  err "No se encontró el script de test:"
  err "${EXAMPLES_DIR}/${TEST_SCRIPT}"
  echo "Scripts disponibles:"
  ls -1 "${EXAMPLES_DIR}" | sed 's/^/ - /'
  exit 1
fi

set +e
sudo -u "${REAL_USER}" bash -lc "
  cd \"${EXAMPLES_DIR}\"
  python3 \"${TEST_SCRIPT}\"
"
TEST_RC=$?
set -e

if [ "${TEST_RC}" -eq 0 ]; then
  log "Test ejecutado correctamente."
  echo "Si la pantalla se ha actualizado → ✔️ todo correcto."
else
  warn "El test devolvió error (${TEST_RC})."
  warn "Si SPI acaba de activarse, reinicia y vuelve a probar."
fi
echo

# 7️⃣ Verificación rápida SPI
if ls /dev/spidev* >/dev/null 2>&1; then
  log "Dispositivos SPI detectados:"
  ls /dev/spidev*
else
  warn "No se detectan /dev/spidev* todavía."
  warn "Probablemente necesites reiniciar."
fi
echo

log "Configuración completada."
echo "Si SPI se acaba de activar, reinicia ahora:"
echo "   sudo reboot"
