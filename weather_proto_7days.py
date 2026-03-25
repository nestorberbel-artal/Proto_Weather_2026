#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import datetime as dt
from typing import Dict, Any, Optional

import requests
from PIL import Image, ImageDraw, ImageFont

# =========================================================
# CONFIGURACIÓN
# =========================================================
W, H = 250, 122

# Terrassa, Barcelona
LAT = 41.56667
LON = 2.01667
TZ = "Europe/Madrid"

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# Ruta fija al repo de Waveshare
WAVESHARE_EPD_LIB = "/home/pi/e-Paper/RaspberryPi_JetsonNano/python/lib"

# PNG de depuración
OUT_PNG = "/tmp/weather_7days_250x122.png"

# Mantener orientación actual de tu pantalla
ROTATE_IMAGE = False

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


# =========================================================
# UTILIDADES
# =========================================================
def load_font(path: str, size: int):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


# =========================================================
# DESCARGA METEO
# =========================================================
def fetch_forecast_7days() -> Dict[str, Any]:
    params = {
        "latitude": LAT,
        "longitude": LON,
        "timezone": TZ,
        "daily": ",".join([
            "weathercode",
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "windspeed_10m_max",
        ]),
        "forecast_days": 7,
    }

    response = requests.get(OPEN_METEO_URL, params=params, timeout=20)
    response.raise_for_status()
    return response.json()


# =========================================================
# ICONOS DIBUJADOS
# =========================================================
def draw_sun(draw, x, y, size=12):
    r = size // 3
    cx = x + size // 2
    cy = y + size // 2

    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=0, width=1)

    draw.line((cx, y, cx, y + 3), fill=0, width=1)
    draw.line((cx, y + size - 3, cx, y + size), fill=0, width=1)
    draw.line((x, cy, x + 3, cy), fill=0, width=1)
    draw.line((x + size - 3, cy, x + size, cy), fill=0, width=1)

    draw.line((x + 2, y + 2, x + 4, y + 4), fill=0, width=1)
    draw.line((x + size - 4, y + 2, x + size - 2, y + 4), fill=0, width=1)
    draw.line((x + 2, y + size - 2, x + 4, y + size - 4), fill=0, width=1)
    draw.line((x + size - 4, y + size - 4, x + size - 2, y + size - 2), fill=0, width=1)


def draw_cloud(draw, x, y, size=14):
    draw.ellipse((x + 1, y + 5, x + 7, y + 11), outline=0, width=1)
    draw.ellipse((x + 5, y + 2, x + 11, y + 10), outline=0, width=1)
    draw.ellipse((x + 9, y + 5, x + 15, y + 11), outline=0, width=1)
    draw.rectangle((x + 3, y + 8, x + 13, y + 11), outline=0, width=1)


def draw_rain(draw, x, y, size=14):
    draw_cloud(draw, x, y, size)
    draw.line((x + 4, y + 13, x + 3, y + 16), fill=0, width=1)
    draw.line((x + 8, y + 13, x + 7, y + 16), fill=0, width=1)
    draw.line((x + 12, y + 13, x + 11, y + 16), fill=0, width=1)


def draw_fog(draw, x, y, size=14):
    draw_cloud(draw, x, y, size)
    draw.line((x + 1, y + 14, x + 14, y + 14), fill=0, width=1)
    draw.line((x + 2, y + 16, x + 13, y + 16), fill=0, width=1)


def draw_snow(draw, x, y, size=14):
    cx = x + 8
    cy = y + 9
    draw.line((cx, cy - 5, cx, cy + 5), fill=0, width=1)
    draw.line((cx - 5, cy, cx + 5, cy), fill=0, width=1)
    draw.line((cx - 4, cy - 4, cx + 4, cy + 4), fill=0, width=1)
    draw.line((cx - 4, cy + 4, cx + 4, cy - 4), fill=0, width=1)


def draw_storm(draw, x, y, size=14):
    draw_cloud(draw, x, y, size)
    draw.line((x + 8, y + 12, x + 5, y + 16), fill=0, width=1)
    draw.line((x + 5, y + 16, x + 8, y + 16), fill=0, width=1)
    draw.line((x + 8, y + 16, x + 6, y + 19), fill=0, width=1)


def draw_weather_icon(draw, code, x, y):
    if code == 0:
        draw_sun(draw, x, y, 14)
    elif code in (1, 2):
        draw_sun(draw, x, y, 12)
        draw_cloud(draw, x + 6, y + 4, 12)
    elif code == 3:
        draw_cloud(draw, x, y + 2, 14)
    elif code in (45, 48):
        draw_fog(draw, x, y, 14)
    elif code in (51, 53, 55, 61, 63, 65, 66, 67, 80, 81, 82):
        draw_rain(draw, x, y, 14)
    elif code in (71, 73, 75, 77):
        draw_snow(draw, x, y, 14)
    elif code in (95, 96, 99):
        draw_storm(draw, x, y, 14)
    else:
        draw_cloud(draw, x, y + 2, 14)


# =========================================================
# RENDERIZADO
# =========================================================
def render_image(data: Dict[str, Any]) -> Image.Image:
    img = Image.new("1", (W, H), 255)
    d = ImageDraw.Draw(img)

    f_title = load_font(FONT_BOLD, 13)
    f_big = load_font(FONT_BOLD, 20)
    f_small = load_font(FONT_REG, 10)
    f_small_b = load_font(FONT_BOLD, 10)

    daily = data.get("daily", {})
    dates = daily.get("time", [])
    tmax = daily.get("temperature_2m_max", [])
    tmin = daily.get("temperature_2m_min", [])
    prcp = daily.get("precipitation_sum", [])
    wcode = daily.get("weathercode", [])

    now = dt.datetime.now()
    dows = ["LUN", "MAR", "MIE", "JUE", "VIE", "SAB", "DOM"]

    # Cabecera
    d.text((4, 2), "Terrassa", font=f_title, fill=0)
    d.text((190, 2), now.strftime("%d/%m"), font=f_small, fill=0)
    d.line((0, 17, W, 17), fill=0)

    # HOY
    code0 = int(wcode[0]) if len(wcode) > 0 else -1
    mx0 = round(tmax[0]) if len(tmax) > 0 else "-"
    mn0 = round(tmin[0]) if len(tmin) > 0 else "-"
    rr0 = round(float(prcp[0])) if len(prcp) > 0 else 0

    d.text((4, 22), "HOY", font=f_small_b, fill=0)
    draw_weather_icon(d, code0, 42, 20)
    d.text((72, 20), f"{mx0}°", font=f_big, fill=0)
    d.text((6, 45), f"{mn0}°  lluvia {rr0} mm", font=f_small, fill=0)

    d.line((0, 58, W, 58), fill=0)

    # Próximos 6 días
    start_y = 62
    row_h = 10

    for i in range(1, 7):
        y = start_y + (i - 1) * row_h

        try:
            day_dt = dt.datetime.strptime(dates[i], "%Y-%m-%d").date()
            day_name = dows[day_dt.weekday()]
        except Exception:
            day_name = dows[(now.weekday() + i) % 7]

        code = int(wcode[i]) if i < len(wcode) else -1
        mx = round(tmax[i]) if i < len(tmax) else "-"
        mn = round(tmin[i]) if i < len(tmin) else "-"
        rr = round(float(prcp[i])) if i < len(prcp) else 0

        d.text((4, y), day_name, font=f_small_b, fill=0)
        draw_weather_icon(d, code, 38, y - 2)
        d.text((62, y), f"{mx}/{mn}", font=f_small, fill=0)
        d.text((104, y), f"{rr} mm", font=f_small, fill=0)

    return img


# =========================================================
# DRIVER WAVESHARE
# =========================================================
def import_epd_driver() -> Optional[object]:
    if os.path.isdir(WAVESHARE_EPD_LIB) and WAVESHARE_EPD_LIB not in sys.path:
        sys.path.append(WAVESHARE_EPD_LIB)

    for name in ("epd2in13_V4", "epd2in13_V3", "epd2in13_V2", "epd2in13"):
        try:
            module = __import__("waveshare_epd." + name, fromlist=[name])
            print(f"[OK] Driver cargado: {name}")
            return module
        except Exception as e:
            print(f"[INFO] No se pudo cargar {name}: {e}")

    return None


def display_on_epd(img: Image.Image) -> bool:
    driver = import_epd_driver()
    if driver is None:
        return False

    try:
        epd = driver.EPD()
        epd.init()
        epd.Clear(0xFF)

        img1 = img.convert("1")
        if ROTATE_IMAGE:
            img1 = img1.rotate(180)

        epd.display(epd.getbuffer(img1))
        epd.sleep()
        return True
    except Exception as e:
        print(f"[ERROR] Fallo al mostrar en pantalla: {e}")
        return False


# =========================================================
# MAIN
# =========================================================
def main():
    try:
        data = fetch_forecast_7days()
    except Exception as e:
        print(f"[ERROR] No se pudo descargar la meteo: {e}")
        return

    img = render_image(data)

    preview = img.rotate(180) if ROTATE_IMAGE else img
    preview.save(OUT_PNG)
    print(f"[OK] PNG generado: {OUT_PNG}")

    if display_on_epd(img):
        print("[OK] Mostrado en la e-ink 2.13\".")
    else:
        print("[WARN] No pude cargar el driver de la e-ink.")
        print("Comprueba:")
        print("  - Repo Waveshare en /home/pi/e-Paper/")
        print("  - SPI habilitado")
        print("  - Driver correcto en waveshare_epd/")
        print("Prueba:")
        print("  ls /home/pi/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd | grep 2in13")


if __name__ == "__main__":
    main()