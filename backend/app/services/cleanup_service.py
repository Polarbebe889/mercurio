"""Tareas de mantenimiento programadas (se lanzan desde el lifespan de main)."""

from datetime import datetime

from .. import config
from ..database import SessionLocal
from ..models import NotaVoz


def limpiar_notas_expiradas() -> int:
    """Borra historias de voz vencidas: fila + archivo del disco.

    Devuelve cuántas se eliminaron.
    """
    db = SessionLocal()
    try:
        vencidas = (
            db.query(NotaVoz)
            .filter(NotaVoz.expires_at < datetime.utcnow())
            .all()
        )
        for nota in vencidas:
            archivo = config.UPLOAD_DIR / nota.filename
            if archivo.exists():
                archivo.unlink(missing_ok=True)
            db.delete(nota)
        if vencidas:
            db.commit()
        return len(vencidas)
    finally:
        db.close()