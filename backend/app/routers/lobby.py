"""Lobby: tarjetas de estado, anillos de voz activos y pines de audio."""

from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import NotaVoz, PinAudio, Usuario
from ..schemas import StatusIn
from ..services.serializers import nota_dict, pin_dict, usuario_dict
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/lobby", tags=["lobby"])

LIMITE_VOZ = 6  # historias por usuario (anillos alrededor del avatar)


def _voz_activas(db: Session) -> list[NotaVoz]:
    ahora = datetime.utcnow()
    return (
        db.query(NotaVoz)
        .filter(NotaVoz.expires_at > ahora)
        .order_by(NotaVoz.created_at.asc())
        .all()
    )


@router.get("")
def lobby(db: Session = Depends(get_db)):
    usuarios = db.query(Usuario).order_by(Usuario.display_name).all()
    notas = _voz_activas(db)
    pines = (
        db.query(PinAudio).order_by(PinAudio.created_at.desc()).limit(20).all()
    )

    por_usuario: dict[int, list[dict]] = {}
    for n in notas:
        por_usuario.setdefault(n.usuario_id, []).append(nota_dict(n))
    for uid, lista in por_usuario.items():
        por_usuario[uid] = lista[-LIMITE_VOZ:]

    return {
        "usuarios": [
            {
                **usuario_dict(u),
                "notas_voz": por_usuario.get(u.id, []),
            }
            for u in usuarios
        ],
        "pines_audio": [pin_dict(p) for p in pines],
        "hora_servidor": datetime.utcnow().isoformat(),
    }


@router.put("/me/estado")
async def actualizar_estado(
    datos: StatusIn, db: Session = Depends(get_db), usuario: Usuario = Depends(get_usuario_actual)
):
    usuario.status_text = datos.status_text
    usuario.status_updated_at = datetime.utcnow()
    db.commit()
    db.refresh(usuario)
    await manager.transmitir(
        {"type": "status.actualizado", "usuario": usuario_dict(usuario)}
    )
    return usuario_dict(usuario)