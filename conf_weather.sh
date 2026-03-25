#!/bin/bash

set -e

echo "========================================"
echo " Configuración meteo + Waveshare 2.13\" "
echo "========================================"

# -----------------------------
# Comprobar usuario
# -----------------------------
if [ "$EUID" -eq 0 ]; then
    echo "[WARN] Estás ejecutando como root."
    echo "[WARN] Es mejor lanzarlo como usuario pi:"
    echo "       ./conf_weather.sh"
    echo
fi

# -----------------------------
# Comprobar variable V
# -----------------------------
if [ -z "$V" ]; then
    echo "[ERROR] La variable V no está definida."
    echo "Ejemplo de uso:"
    echo "  V=3 ./conf_weather.sh"
    echo "  V=4 ./conf_weather.sh"
    exit 1
fi

# -----------------------------
# Activar SPI
# -----------------------------
CONFIG_FILE="/boot/config.txt"

if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] No se encontró config.txt"
    exit 1
fi

echo "[INFO] Archivo de configuración detectado: $CONFIG_FILE"

if grep -q "^dtparam=spi=on" "$CONFIG_FILE"; then
    echo "[OK] SPI ya estaba habilitado."
else
    echo "[INFO] Habilitando SPI..."
    sudo bash -c "echo 'dtparam=spi=on' >> '$CONFIG_FILE'"
    echo "[OK] SPI habilitado en config.txt"
fi

# -----------------------------
# Instalar dependencias
# -----------------------------
echo "[INFO] Instalando dependencias..."
sudo apt update
sudo apt install -y python3-pil python3-requests fonts-dejavu-core git

# -----------------------------
# Clonar repo Waveshare si no existe
# -----------------------------
if [ ! -d "/home/pi/e-Paper" ]; then
    echo "[INFO] Clonando repo Waveshare..."
    git clone https://github.com/waveshare/e-Paper.git /home/pi/e-Paper
else
    echo "[OK] El repo /home/pi/e-Paper ya existe."
fi

# -----------------------------
# Comprobar drivers 2in13
# -----------------------------
echo "[INFO] Drivers disponibles:"
ls /home/pi/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd | grep 2in13 || true

# -----------------------------
# Ir a ejemplos
# -----------------------------
EXAMPLES_DIR="/home/pi/e-Paper/RaspberryPi_JetsonNano/python/examples"

if [ ! -d "$EXAMPLES_DIR" ]; then
    echo "[ERROR] No existe la carpeta de ejemplos:"
    echo "        $EXAMPLES_DIR"
    exit 1
fi

cd "$EXAMPLES_DIR"

TEST_FILE="epd_2in13_V${V}_test.py"

if [ ! -f "$TEST_FILE" ]; then
    echo "[ERROR] No existe el test esperado:"
    echo "        $EXAMPLES_DIR/$TEST_FILE"
    echo
    echo "Archivos disponibles:"
    ls "$EXAMPLES_DIR" | grep 2in13 || true
    exit 1
fi

echo "[OK] Test encontrado: $TEST_FILE"

# -----------------------------
# Ejecutar test
# -----------------------------
echo "[INFO] Ejecutando test Waveshare..."
python3 "$TEST_FILE"

echo
echo "[OK] Test finalizado."
echo
echo "Si la pantalla no ha reaccionado todavía, reinicia la Raspberry con:"
echo "  sudo reboot"
