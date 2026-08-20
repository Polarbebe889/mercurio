"""Música en vivo: lo que cada usuario escucha (Spotify / MusicKit)."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import AhoraEscuchando, ProviderMusica, Usuario
from ..schemas import MusicaIn
from ..services.serializers import musica_dict, usuario_dict
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/musica", tags=["musica"])


@router.put("/me")
async def actualizar_musica(
    datos: MusicaIn,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    try:
        provider = ProviderMusica(datos.provider)
    except ValueError:
        raise HTTPException(422, "provider debe ser spotify o music_kit")

    musica = db.get(AhoraEscuchando, usuario.id)
    if musica is None:
        musica = AhoraEscuchando(usuario_id=usuario.id, provider=provider)
        db.add(musica)
    musica.provider = provider
    musica.titulo = datos.titulo
    musica.artista = datos.artista
    musica.album = datos.album
    musica.artwork_url = datos.artwork_url
    musica.reproduciendo = datos.reproduciendo
    musica.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(musica)

    await manager.transmitir(
        {
            "type": "musica.actualizada",
            "usuario_id": usuario.id,
            "musica": musica_dict(musica),
        }
    )
    return musica_dict(musica)


@router.delete("/me")
async def detener_musica(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    db.delete(db.get(AhoraEscuchando, usuario.id))
    db.commit()
    await manager.transmitir(
        {"type": "musica.detenida", "usuario_id": usuario.id}
    )
    return {"ok": True}