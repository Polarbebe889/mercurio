import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR") or str(BASE_DIR / "uploads")).resolve()

DATABASE_URL = os.getenv(
    "DATABASE_URL", f"sqlite:///{BASE_DIR / 'bunker.db'}"
)

# Código de invitación único del grupo cerrado (los 6 entran con el mismo).
JOIN_CODE = os.getenv("JOIN_CODE", "BUNKER-6")

# Orígenes permitidos: "*" para modo abierto; separar con coma para producción.
CORS_ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]

# Límites de subida
MAX_AUDIO_BYTES = int(os.getenv("MAX_AUDIO_BYTES", "25_000_000"))  # 25 MB
MAX_PHOTO_BYTES = int(os.getenv("MAX_PHOTO_BYTES", "30_000_000"))  # 30 MB
TIPOS_AUDIO = {".mp3", ".m4a", ".aac", ".ogg", ".wav"}
TIPOS_FOTO = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
MEDIA_TIPOS = TIPOS_AUDIO | TIPOS_FOTO

# Historias de voz viven 24 h; el limpiador corre cada intervalo.
HORAS_VOZ = 24
LIMPIEZA_HORAS = float(os.getenv("LIMPIEZA_HORAS", "6"))

# Configuración Elo (E_Lo en contexto de certeza)
ELO_INICIAL = 1000
ELO_K = 32