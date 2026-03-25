#!/bin/bash

set -e

echo "========================================"
echo " Configuración meteo + Waveshare 2.13\" "
echo "========================================"

# Comprobar archivo config.txt
CONFIG_FILE="/boot/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] No se encontró config.txt"
    exit 1
fi

echo "[INFO] Archivo de configuración: $CONFIG_FILE"

# Habilitar SPI
if grep -q "^dtparam=spi=on" "$CONFIG_FILE"; then
    echo "[OK] SPI ya estaba habilitado."
else
    echo "[INFO] Habilitando SPI..."
    sudo bash -c "echo 'dtparam=spi=on' >> '$CONFIG_FILE'"
    echo "[OK] SPI habilitado."
fi

# Instalar dependencias
echo "[INFO] Instalando dependencias..."
sudo apt update
sudo apt install -y python3-pil python3-requests fonts-dejavu-core git

# Clonar repo Waveshare si no existe
if [ ! -d "/home/pi/e-Paper" ]; then
    echo "[INFO] Clonando repo Waveshare..."
    git clone https://github.com/waveshare/e-Paper.git /home/pi/e-Paper
else
    echo "[OK] El repo /home/pi/e-Paper ya existe."
fi

# Mostrar drivers disponibles
echo "[INFO] Drivers disponibles:"
ls /home/pi/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd | grep 2in13 || true

# Carpeta de ejemplos
EXAMPLES_DIR="/home/pi/e-Paper/RaspberryPi_JetsonNano/python/examples"

if [ ! -d "$EXAMPLES_DIR" ]; then
    echo "[ERROR] No existe la carpeta:"
    echo "        $EXAMPLES_DIR"
    exit 1
fi

cd "$EXAMPLES_DIR"

# Test fijo que quieres ejecutar
TEST_FILE="epd_2in13_V2_test.py"

if [ ! -f "$TEST_FILE" ]; then
    echo "[ERROR] No existe el test esperado:"
    echo "        $EXAMPLES_DIR/$TEST_FILE"
    echo
    echo "Archivos disponibles:"
    ls "$EXAMPLES_DIR" | grep 2in13 || true
    exit 1
fi

echo "[OK] Test encontrado: $TEST_FILE"
echo "[INFO] Ejecutando test Waveshare..."

python3 "$TEST_FILE"

echo
echo "[OK] Test finalizado."
echo "Si la pantalla no ha reaccionado, reinicia con:"
echo "  sudo reboot"
