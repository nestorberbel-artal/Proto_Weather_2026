#!/bin/bash

set -e

echo "========================================"
echo " Instalación weather_proto_7days.py"
echo "========================================"

# =========================================================
# CONFIGURACIÓN
# =========================================================
REPO_URL="https://github.com/nestorberbel-artal/Proto_Weather_2026.git"
REPO_DIR="/home/pi/Proto_Weather_2026"

INSTALL_DIR="/home/pi/weather"
SCRIPT_NAME="weather_proto_7days.py"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

RUNNER_PATH="$INSTALL_DIR/run_weather.sh"
LOG_PATH="$INSTALL_DIR/weather.log"

PYTHON_BIN="/usr/bin/python3"

# =========================================================
# DEPENDENCIAS
# =========================================================
echo "[INFO] Instalando dependencias..."
sudo apt update
sudo apt install -y git python3-requests python3-pil fonts-dejavu-core

# =========================================================
# CLONAR O ACTUALIZAR REPO
# =========================================================
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "[INFO] Clonando repositorio..."
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo "[INFO] El repositorio ya existe. Actualizando..."
    cd "$REPO_DIR"
    git pull
fi

# =========================================================
# CREAR CARPETA DE INSTALACIÓN
# =========================================================
echo "[INFO] Creando carpeta de instalación..."
mkdir -p "$INSTALL_DIR"

# =========================================================
# COPIAR SCRIPT PRINCIPAL
# =========================================================
if [ ! -f "$REPO_DIR/$SCRIPT_NAME" ]; then
    echo "[ERROR] No se encuentra el archivo:"
    echo "        $REPO_DIR/$SCRIPT_NAME"
    exit 1
fi

cp "$REPO_DIR/$SCRIPT_NAME" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

echo "[OK] Script copiado en:"
echo "     $SCRIPT_PATH"

# =========================================================
# CREAR SCRIPT LANZADOR
# =========================================================
echo "[INFO] Creando lanzador..."
cat > "$RUNNER_PATH" <<EOF
#!/bin/bash
cd /home/pi/weather
$PYTHON_BIN /home/pi/weather/weather_proto_7days.py >> /home/pi/weather/weather.log 2>&1
EOF

chmod +x "$RUNNER_PATH"

echo "[OK] Lanzador creado en:"
echo "     $RUNNER_PATH"

# =========================================================
# CONFIGURAR CRON
# =========================================================
echo "[INFO] Configurando ejecución cada 30 minutos..."

CRON_LINE="*/30 * * * * /home/pi/weather/run_weather.sh"
TMP_CRON=$(mktemp)

crontab -l 2>/dev/null | grep -v "run_weather.sh" > "$TMP_CRON" || true
echo "$CRON_LINE" >> "$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

echo "[OK] Cron configurado."

# =========================================================
# PRUEBA INICIAL
# =========================================================
echo "[INFO] Ejecutando prueba inicial..."
bash "$RUNNER_PATH" || true

echo
echo "========================================"
echo " INSTALACIÓN COMPLETADA"
echo "========================================"
echo
echo "[OK] Repositorio:"
echo "     $REPO_URL"
echo
echo "[OK] Script instalado en:"
echo "     $SCRIPT_PATH"
echo
echo "[OK] Lanzador:"
echo "     $RUNNER_PATH"
echo
echo "[OK] Log:"
echo "     $LOG_PATH"
echo
echo "[OK] Cron configurado para ejecutarse cada 30 minutos."
echo
echo "Para comprobar el cron:"
echo "  crontab -l"
echo
echo "Para ver el log:"
echo "  tail -f $LOG_PATH"
echo
echo "Para ejecutar manualmente:"
echo "  bash $RUNNER_PATH"
