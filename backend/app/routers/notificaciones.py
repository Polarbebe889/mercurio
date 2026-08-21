"""Notificaciones push: registro de FCM tokens."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import FcmToken, Usuario
from ..routers.auth import get_usuario_actual

router = APIRouter(prefix="/notificaciones", tags=["notificaciones"])


class TokenIn(BaseModel):
    token: str
    plataforma: str = "android"  # ios, android, web


@router.post("/token")
def registrar_token(datos: TokenIn, db: Session = Depends(get_db), usuario: Usuario = Depends(get_usuario_actual)):
    # upsert por token único
    existente = db.query(FcmToken).filter(FcmToken.token == datos.token).first()
    if existente:
        existente.usuario_id = usuario.id
        existente.plataforma = datos.plataforma
        db.commit()
        return {"ok": True, "actualizado": True}
    # borra tokens viejos del mismo usuario si ya tiene 3 (limite por usuario)
    viejos = db.query(FcmToken).filter(FcmToken.usuario_id == usuario.id).order_by(FcmToken.updated_at.desc()).all()
    if len(viejos) >= 3:
        for v in viejos[2:]:
            db.delete(v)
    nuevo = FcmToken(usuario_id=usuario.id, token=datos.token, plataforma=datos.plataforma)
    db.add(nuevo)
    db.commit()
    return {"ok": True, "actualizado": False}


@router.delete("/token")
def borrar_token(datos: TokenIn, db: Session = Depends(get_db), usuario: Usuario = Depends(get_usuario_actual)):
    q = db.query(FcmToken).filter(FcmToken.usuario_id == usuario.id, FcmToken.token == datos.token)
    q.delete()
    db.commit()
    return {"ok": True}


@router.get("/tokens")
def listar_tokens(db: Session = Depends(get_db), usuario: Usuario = Depends(get_usuario_actual)):
    tokens = db.query(FcmToken).filter(FcmToken.usuario_id == usuario.id).all()
    return {"tokens": [{"token": t.token[:20] + "...", "plataforma": t.plataforma} for t in tokens]}
