"""Drops: pines de foto permanentes sin pérdida de calidad."""

from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import text
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
    # REGLA: solo 1 drop activo por usuario → el más reciente por usuario_id
    # Postgres: DISTINCT ON (usuario_id) ORDER BY usuario_id, created_at DESC (rápido, indexado)
    # Fallback: Python dedup para SQLite/otros (Render free usa Postgres, pero tests usan SQLite)
    dialect = db.bind.dialect.name if db.bind is not None else ""
    if dialect == "postgresql":
        try:
            rows = db.execute(
                text(
                    """
                    SELECT DISTINCT ON (usuario_id) *
                    FROM drops_fotos
                    ORDER BY usuario_id, created_at DESC
                    """
                )
            ).mappings().all()
            # rows ya son 1 por usuario, ordenar global por created_at DESC y limitar
            filtrados = []
            for r in rows:
                # reconstruir DropsFoto mínimo para drop_dict (solo campos usados)
                d = DropsFoto(
                    id=r["id"],
                    usuario_id=r["usuario_id"],
                    filename=r["filename"],
                    mime_type=r["mime_type"],
                    size_bytes=r["size_bytes"],
                    caption=r["caption"],
                    created_at=r["created_at"],
                )
                filtrados.append(d)
            filtrados.sort(key=lambda d: d.created_at, reverse=True)
            filtrados = filtrados[: min(limite, 200)]
            return {"drops": [drop_dict(d) for d in filtrados]}
        except Exception:
            pass  # fallback a Python si falla la query
    todos = (
        db.query(DropsFoto).order_by(DropsFoto.created_at.desc()).all()
    )
    vistos: set[int] = set()
    filtrados: list[DropsFoto] = []
    for d in todos:
        if d.usuario_id not in vistos:
            vistos.add(d.usuario_id)
            filtrados.append(d)
        if len(filtrados) >= min(limite, 200):
            break
    return {"drops": [drop_dict(d) for d in filtrados]}


@router.post("", status_code=201)
async def crear_drop(
    file: UploadFile = File(...),
    caption: str = Form(default="", max_length=2000),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    filename, mime, size = await guardar_media(file, TIPOS, config.MAX_PHOTO_BYTES)
    # REGLA: 1 drop por usuario → elimina drops anteriores del mismo usuario (DB limpia)
    viejos = db.query(DropsFoto).filter(DropsFoto.usuario_id == usuario.id).all()
    for v in viejos:
        try:
            eliminar_media(v.filename)
        except Exception:
            pass
        db.delete(v)
    # flush para que no haya conflicto de clave antes de insertar
    if viejos:
        db.flush()
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
    # Notificar borrado de los anteriores para que el frontend los quite
    for v in viejos:
        await manager.transmitir({"type": "drop.borrado", "drop_id": v.id})
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