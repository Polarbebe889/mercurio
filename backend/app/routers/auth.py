"""Auth del grupo cerrado: alta con join code (máx. 6) + token de acceso."""

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Usuario
from ..schemas import RegistroIn, RegistroOut, UsuarioOut

router = APIRouter(prefix="/auth", tags=["auth"])

MAX_USUARIOS = 6


def get_usuario_actual(
    x_token: str = Header(..., alias="x-token"),
    db: Session = Depends(get_db),
) -> Usuario:
    u = db.query(Usuario).filter(Usuario.token == x_token).first()
    if u is None:
        raise HTTPException(401, "token inválido")
    return u


@router.post("/registro", response_model=RegistroOut, status_code=201)
def registrar(datos: RegistroIn, db: Session = Depends(get_db)):
    if datos.join_code != config.JOIN_CODE:
        raise HTTPException(403, "código de invitación incorrecto")

    existente = db.query(Usuario).filter(Usuario.username == datos.username).first()
    if existente is not None:
        raise HTTPException(409, "ese username ya existe")
    if db.query(Usuario).count() >= MAX_USUARIOS:
        raise HTTPException(409, f"el bunker ya está lleno ({MAX_USUARIOS})")

    usuario = Usuario(
        username=datos.username,
        display_name=datos.display_name,
        emoji=datos.emoji,
        avatar_color=datos.avatar_color,
        token=secrets.token_hex(32),
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return {"usuario": usuario, "token": usuario.token}


@router.get("/me", response_model=UsuarioOut)
def mi_perfil(usuario: Usuario = Depends(get_usuario_actual)):
    return usuario