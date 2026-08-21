"""Drops: pines de foto permanentes sin pérdida de calidad."""

from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import DropsFoto, Usuario
from ..services.serializers import drop_dict
from ..services.uploads import eliminar_media, guardar_media
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/drops", tags=["drops"])

TIPOS = {"image/jpeg", "image/png", "image/webp", "image/heic"}


@router.get("")
def listar_drops(
    limite: int = 50, db: Session = Depends(get_db), _: Usuario = Depends(get_usuario_actual)
):
    items = (
        db.query(DropsFoto).order_by(DropsFoto.created_at.desc()).limit(min(limite, 200)).all()
    )
    return {"drops": [drop_dict(d) for d in items]}


@router.post("", status_code=201)
async def crear_drop(
    file: UploadFile = File(...),
    caption: str = Form(default="", max_length=2000),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    filename, mime, size = await guardar_media(file, TIPOS, config.MAX_PHOTO_BYTES)
    drop = DropsFoto(
        usuario_id=usuario.id,
        filename=filename,
        mime_type=mime,
        size_bytes=size,
        caption=caption,
    )
    db.add(drop)
    db.commit()
    db.refresh(drop)

    await manager.transmitir(
        {
            "type": "drop.nuevo",
            "drop": drop_dict(drop),
            "autor": {"id": usuario.id, "display_name": usuario.display_name},
        }
    )
    return drop_dict(drop)


@router.delete("/{drop_id}")
async def borrar_drop(
    drop_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    drop = db.get(DropsFoto, drop_id)
    if drop is None:
        raise HTTPException(404, "drop no existe")
    if drop.usuario_id != usuario.id:
        raise HTTPException(403, "solo su autor puede borrarlo")
    eliminar_media(drop.filename)
    db.delete(drop)
    db.commit()
    await manager.transmitir({"type": "drop.borrado", "drop_id": drop_id})
    return {"ok": True}