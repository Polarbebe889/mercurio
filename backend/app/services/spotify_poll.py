"""Poller de Spotify: actualiza AhoraEscuchando cada SPOTIFY_POLL_SECONDS."""

import asyncio
import base64
import logging
from datetime import datetime

import httpx
from sqlalchemy.orm import Session

from .. import config
from ..database import SessionLocal
from ..models import AhoraEscuchando, ProviderMusica, Usuario
from ..services.fcm_service import notificar_a_todos
from ..services.serializers import musica_dict
from ..ws.manager import manager

log = logging.getLogger(__name__)


async def _refresh_access_token(db: Session, usuario: Usuario) -> str | None:
    """Usa refresh_token para obtener nuevo access_token. Retorna nuevo access_token o None."""
    if not usuario.spotify_refresh_token or not config.SPOTIFY_CLIENT_SECRET:
        return None
    auth = base64.b64encode(f"{config.SPOTIFY_CLIENT_ID}:{config.SPOTIFY_CLIENT_SECRET}".encode()).decode()
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(
                "https://accounts.spotify.com/api/token",
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": usuario.spotify_refresh_token,
                },
                headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
            )
            if r.status_code != 200:
                log.warning(f"[Spotify] refresh failed for {usuario.username}: {r.status_code} {r.text[:200]}")
                return None
            j = r.json()
            new_access = j.get("access_token")
            if new_access:
                usuario.spotify_access_token = new_access
                # Spotify puede devolver nuevo refresh_token a veces
                if j.get("refresh_token"):
                    usuario.spotify_refresh_token = j.get("refresh_token")
                db.commit()
                return new_access
    except Exception as e:
        log.warning(f"[Spotify] refresh exception {usuario.username}: {e}")
    return None


async def _poll_one(db: Session, usuario: Usuario):
    if not usuario.spotify_access_token and not usuario.spotify_refresh_token:
        return
    access = usuario.spotify_access_token
    # intenta con access actual, si 401 intenta refresh
    for intento in range(2):
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(
                    "https://api.spotify.com/v1/me/player/currently-playing",
                    headers={"Authorization": f"Bearer {access}"},
                )
                if r.status_code == 401 and intento == 0:
                    # token expirado, refresca
                    new_access = await _refresh_access_token(db, usuario)
                    if new_access:
                        access = new_access
                        continue
                    # refresh falló, limpia musica
                    break
                if r.status_code == 204 or r.status_code == 202:
                    # nada sonando
                    await _set_no_musica(db, usuario)
                    return
                if r.status_code != 200:
                    # no hay nada o error, no actualices
                    if r.status_code in (404, 403):
                        await _set_no_musica(db, usuario)
                    return
                j = r.json()
                if not j or j.get("item") is None:
                    await _set_no_musica(db, usuario)
                    return
                item = j["item"]
                is_playing = j.get("is_playing", False)
                titulo = item.get("name", "")[:200]
                artistas = item.get("artists") or []
                artista = ", ".join([a.get("name", "") for a in artistas])[:120]
                album = (item.get("album") or {}).get("name", "")[:120]
                images = (item.get("album") or {}).get("images") or []
                artwork = images[0].get("url", "") if images else ""
                await _set_musica(db, usuario, titulo, artista, album, artwork, is_playing)
                return
        except Exception as e:
            log.warning(f"[Spotify] poll exception {usuario.username}: {e}")
            return


async def _set_musica(db: Session, usuario: Usuario, titulo: str, artista: str, album: str, artwork: str, reproduciendo: bool):
    musica = db.get(AhoraEscuchando, usuario.id)
    if musica is None:
        musica = AhoraEscuchando(usuario_id=usuario.id, provider=ProviderMusica.SPOTIFY)
        db.add(musica)
    musica.provider = ProviderMusica.SPOTIFY
    musica.titulo = titulo
    musica.artista = artista
    musica.album = album
    musica.artwork_url = artwork
    musica.reproduciendo = reproduciendo
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
    # Push si está reproduciendo y tiene título
    if reproduciendo and titulo:
        try:
            await notificar_a_todos(
                db,
                titulo=f"{usuario.display_name} 🎵 {titulo}",
                cuerpo=artista or "Sonando en Spotify",
                data={"type": "musica.actualizada", "usuario_id": str(usuario.id)},
                excluir=usuario.id,
            )
        except Exception:
            pass


async def _set_no_musica(db: Session, usuario: Usuario):
    # Siempre asegura que haya entrada spotify con reproduciendo=False para que el frontend detecte "conectado"
    existente = db.get(AhoraEscuchando, usuario.id)
    if existente is None:
        existente = AhoraEscuchando(usuario_id=usuario.id, provider=ProviderMusica.SPOTIFY, titulo="", artista="", album="", artwork_url="", reproduciendo=False)
        db.add(existente)
        existente.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(existente)
        await manager.transmitir({"type": "musica.actualizada", "usuario_id": usuario.id, "musica": musica_dict(existente)})
        return
    if existente.provider != ProviderMusica.SPOTIFY:
        # no toques Apple Music
        return
    if not existente.reproduciendo:
        # ya está en false, no spamees pero asegura que sigue existiendo para "conectado"
        return
    existente.reproduciendo = False
    existente.updated_at = datetime.utcnow()
    db.commit()
    await manager.transmitir({"type": "musica.detenida", "usuario_id": usuario.id})


async def poll_spotify_once():
    db = SessionLocal()
    try:
        usuarios = db.query(Usuario).filter(Usuario.spotify_refresh_token.isnot(None)).all()
        for u in usuarios:
            # expirar si no hay refresh, pero igual intenta con access
            await _poll_one(db, u)
            # refresca objeto por si fue modificado
            db.refresh(u)
    finally:
        db.close()


async def bucle_spotify():
    # espera un poco al arrancar para que DB esté lista
    await asyncio.sleep(10)
    while True:
        try:
            await poll_spotify_once()
        except Exception as e:
            log.warning(f"[Spotify] bucle error: {e}")
        await asyncio.sleep(config.SPOTIFY_POLL_SECONDS)
