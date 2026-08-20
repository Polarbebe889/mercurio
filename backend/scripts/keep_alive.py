"""Keep-alive para Render free: hace ping a /health cada 9 minutos
(Render free duerme la instancia a los ~15 min sin tráfico; el ping la
despierta y mantiene el WebSocket del lobby vivo entre usos).

OPCIONES DE DESPLIEGUE:
1) LOCAL/LAPTOP: python scripts/keep_alive.py  (deja la terminal abierta
   o usa `nohup python scripts/keep_alive.py &`).
2) NUBE GRATIS (recomendado): crea un job en cron-job.org o UptimeRobot
   apuntando a https://TU-APP.onrender.com/health, intervalo 5 min.
   No consume batería local ni depende de tu máquina.
"""

import time

import httpx

URL = "https://TU-APP.onrender.com/health"  # <-- cambia por la URL real
INTERVALO_MIN = 9


def ping() -> None:
    try:
        r = httpx.get(URL, timeout=15)
        print(f"[{time.strftime('%H:%M:%S')}] /health -> {r.status_code}")
    except Exception as e:  # noqa: BLE001
        print(f"[{time.strftime('%H:%M:%S')}] fallo de ping: {e}")


if __name__ == "__main__":
    print(f"keep-alive cada {INTERVALO_MIN} min hacia {URL} (Ctrl+C para salir)")
    while True:
        ping()
        time.sleep(INTERVALO_MIN * 60)