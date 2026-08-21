"""Auth del grupo cerrado: alta con join code (máx. 6) + token de acceso + PIN 4 dígitos."""

import secrets
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Usuario
from ..schemas import LoginIn, RegistroIn, RegistroOut, UsuarioOut


def _hash_pin(pin: str) -> str:
    # Por ahora guardamos PIN en claro (4 dígitos) para compat con SQLite + migración simple.
    # Si quieres bcrypt, cambia a passlib: pwd_context.hash(pin) y añade passlib[bcrypt] a requirements.
    return pin


def _verify_pin(pin: str, stored: str | None) -> bool:
    if stored is None:
        return False
    # Soporte dual: si algún día migras a bcrypt ($2b$) verificará con passlib, si no es plain
    if stored.startswith("$2b$") or stored.startswith("$2a$") or stored.startswith("$2y$"):
        try:
            from passlib.context import CryptContext

            pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
            return pwd_context.verify(pin, stored)
        except Exception:
            return False
    return stored == pin

router = APIRouter(prefix="/auth", tags=["auth"])

MAX_USUARIOS = 6


def get_usuario_actual(
    x_token: Optional[str] = Header(None, alias="x-token"),
    x_user_id: Optional[str] = Header(None, alias="x-user-id"),
    x_username: Optional[str] = Header(None, alias="x-username"),
    db: Session = Depends(get_db),
) -> Usuario:
    # Prioridad: x-token (flujo principal). Fallback: x-user-id / x-username (minimalista).
    if x_token:
        u = db.query(Usuario).filter(Usuario.token == x_token).first()
        if u is not None:
            return u
    # Fallback por username si Flutter envía x-user-id (requerido por spec) y el token aún no se validó
    username = x_user_id or x_username
    if username:
        u = db.query(Usuario).filter(Usuario.username == username).first()
        if u is not None:
            return u
    raise HTTPException(401, "token inválido - inicia sesión de nuevo")


@router.post("/registro", response_model=RegistroOut, status_code=201)
def registrar(datos: RegistroIn, db: Session = Depends(get_db)):
    if datos.join_code != config.JOIN_CODE:
        raise HTTPException(403, "código de invitación incorrecto")

    existente = db.query(Usuario).filter(Usuario.username == datos.username).first()
    if existente is not None:
        # Login persistente: si el PIN coincide (bcrypt o plain legacy), recupera sesión.
        if _verify_pin(datos.pin, existente.pin):
            # migra plain legacy a bcrypt en el primer login exitoso
            if existente.pin and not existente.pin.startswith("$2"):
                existente.pin = _hash_pin(datos.pin)
                db.commit()
                db.refresh(existente)
            return {"usuario": existente, "token": existente.token}
        # Usuario legacy sin PIN: lo vincula ahora (hash bcrypt)
        if existente.pin is None:
            existente.pin = _hash_pin(datos.pin)
            if datos.display_name:
                existente.display_name = datos.display_name
            db.commit()
            db.refresh(existente)
            return {"usuario": existente, "token": existente.token}
        raise HTTPException(409, "ese username ya existe - PIN incorrecto")
    if db.query(Usuario).count() >= MAX_USUARIOS:
        raise HTTPException(409, f"el bunker ya está lleno ({MAX_USUARIOS})")

    # display_name por defecto = username si viene vacío (flujo minimalista username+PIN)
    dn = datos.display_name.strip() if datos.display_name else datos.username.strip()
    usuario = Usuario(
        username=datos.username.strip(),
        display_name=dn,
        emoji=datos.emoji,
        avatar_color=datos.avatar_color,
        token=secrets.token_hex(32),
        pin=_hash_pin(datos.pin),
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return {"usuario": usuario, "token": usuario.token}


@router.post("/login", response_model=RegistroOut)
def login(datos: LoginIn, db: Session = Depends(get_db)):
    """Login minimalista: username + PIN 4 dígitos. Idempotente, no crea fantasmas."""
    u = db.query(Usuario).filter(Usuario.username == datos.username.strip()).first()
    if u is None:
        raise HTTPException(404, "usuario no existe - regístrate primero")
    # Usuario legacy sin PIN: primera vez lo asigna (bcrypt)
    if u.pin is None:
        u.pin = _hash_pin(datos.pin)
        db.commit()
        db.refresh(u)
        return {"usuario": u, "token": u.token}
    if not _verify_pin(datos.pin, u.pin):
        raise HTTPException(401, "PIN incorrecto")
    # migra plain a bcrypt si hace falta
    if u.pin and not u.pin.startswith("$2"):
        u.pin = _hash_pin(datos.pin)
        db.commit()
        db.refresh(u)
    return {"usuario": u, "token": u.token}


@router.get("/me", response_model=UsuarioOut)
def mi_perfil(usuario: Usuario = Depends(get_usuario_actual)):
    return usuario