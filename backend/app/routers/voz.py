"""Voz: historias de 24 h (anillos del lobby) y pines de audio fijos."""

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import NotaVoz, PinAudio, Usuario
from ..services.serializers import nota_dict, pin_dict, usuario_dict
from ..services.uploads import eliminar_media, guardar_media
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/voz", tags=["voz"])

TIPOS_AUDIO = {"audio/mpeg", "audio/mp4", "audio/aac", "audio/ogg", "audio/wav"}

MAX_HISTORIAS_USUARIO = 6  # anillos simultáneos visibles


# ---------------------------------------------------------------------------
# Historias de voz (24 h) - envueltas en dict para Flutter jsonDecode -> Map
# ---------------------------------------------------------------------------
@router.get("/historias")
def historias(
    db: Session = Depends(get_db), _: Usuario = Depends(get_usuario_actual)
):
    ahora = datetime.utcnow()
    notas = (
        db.query(NotaVoz)
        .filter(NotaVoz.expires_at > ahora)
        .order_by(NotaVoz.created_at.desc())
        .all()
    )
    return {"historias": [nota_dict(n) for n in notas]}


@router.post("/historias", status_code=201)
async def subir_historia(
    file: UploadFile = File(...),
    duration_s: int = Form(default=0, ge=0, le=600),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    activas = (
        db.query(NotaVoz)
        .filter(NotaVoz.usuario_id == usuario.id, NotaVoz.expires_at > datetime.utcnow())
        .count()
    )
    if activas >= MAX_HISTORIAS_USUARIO:
        raise HTTPException(429, "ya tienes el máximo de historias activas (6)")

    filename, mime, _ = await guardar_media(file, TIPOS_AUDIO, config.MAX_AUDIO_BYTES)
    nota = NotaVoz(
        usuario_id=usuario.id,
        filename=filename,
        mime_type=mime,
        duration_s=duration_s,
        expires_at=datetime.utcnow() + timedelta(hours=config.HORAS_VOZ),
    )
    db.add(nota)
    db.commit()
    db.refresh(nota)

    await manager.transmitir(
        {
            "type": "voz.nueva",
            "nota": nota_dict(nota),
            "autor": {"id": usuario.id, "display_name": usuario.display_name},
        }
    )
    return nota_dict(nota)


@router.delete("/historias/{nota_id}")
async def borrar_historia(
    nota_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    nota = db.get(NotaVoz, nota_id)
    if nota is None:
        raise HTTPException(404, "historia no existe")
    if nota.usuario_id != usuario.id:
        raise HTTPException(403, "solo su autor puede borrarla")
    eliminar_media(nota.filename)
    db.delete(nota)
    db.commit()
    await manager.transmitir({"type": "voz.borrada", "nota_id": nota_id})
    return {"ok": True}


# ---------------------------------------------------------------------------
# Pines de audio (permanentes)
# ---------------------------------------------------------------------------
@router.get("/pines")
def listar_pines(
    db: Session = Depends(get_db), _: Usuario = Depends(get_usuario_actual)
):
    pines = (
        db.query(PinAudio).order_by(PinAudio.created_at.desc()).limit(50).all()
    )
    return {"pines": [pin_dict(p) for p in pines]}


@router.post("/pines", status_code=201)
async def fijar_audio(
    file: UploadFile = File(...),
    caption: str = Form(default="", max_length=2000),
    duration_s: int = Form(default=0, ge=0, le=600),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    filename, mime, _ = await guardar_media(file, TIPOS_AUDIO, config.MAX_AUDIO_BYTES)
    pin = PinAudio(
        usuario_id=usuario.id,
        filename=filename,
        mime_type=mime,
        duration_s=duration_s,
        caption=caption,
    )
    db.add(pin)
    db.commit()
    db.refresh(pin)

    await manager.transmitir(
        {
            "type": "pin.audio.nuevo",
            "pin": pin_dict(pin),
            "autor": {"id": usuario.id, "display_name": usuario.display_name},
        }
    )
    return pin_dict(pin)


@router.delete("/pines/{pin_id}")
async def borrar_pin(
    pin_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    pin = db.get(PinAudio, pin_id)
    if pin is None:
        raise HTTPException(404, "pin no existe")
    if pin.usuario_id != usuario.id:
        raise HTTPException(403, "solo su autor puede borrarlo")
    eliminar_media(pin.filename)
    db.delete(pin)
    db.commit()
    await manager.transmitir({"type": "pin.audio.borrado", "pin_id": pin_id})
    return {"ok": True}