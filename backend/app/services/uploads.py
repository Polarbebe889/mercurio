"""Guardado de archivos multimedia (drops y audios) en /uploads con
nombre aleatorio inmutable y validación de tipo/tamaño en streaming."""

import uuid

from fastapi import HTTPException, UploadFile

from .. import config

MIME_EXT = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
    "audio/mpeg": ".mp3",
    "audio/mp4": ".m4a",
    "audio/aac": ".aac",
    "audio/ogg": ".ogg",
    "audio/ogg; codecs=opus": ".ogg",
    "audio/wav": ".wav",
}


async def guardar_media(
    upload: UploadFile,
    mime_permitidos: set[str],
    max_bytes: int,
) -> tuple[str, str, int]:
    """Guarda el archivo y devuelve (filename, mime, size_bytes)."""
    mime = (upload.content_type or "").lower()
    ext = MIME_EXT.get(mime)
    if ext is None or mime not in mime_permitidos:
        raise HTTPException(415, f"tipo no permitido: {mime or 'desconocido'}")

    # Falta la extensión en TIPOS_*: añade el mime al conjunto permitido pasado.
    filename = f"{uuid.uuid4().hex}{ext}"
    destino = config.UPLOAD_DIR / filename

    size = 0
    try:
        with destino.open("wb") as salida:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > max_bytes:
                    salida.close()
                    destino.unlink(missing_ok=True)
                    raise HTTPException(413, "archivo demasiado grande")
                salida.write(chunk)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        destino.unlink(missing_ok=True)
        raise HTTPException(500, f"no se pudo guardar: {e}")
    finally:
        await upload.close()

    return filename, mime, size


def eliminar_media(filename: str | None) -> None:
    if not filename:
        return
    archivo = config.UPLOAD_DIR / filename
    if archivo.exists():
        archivo.unlink(missing_ok=True)