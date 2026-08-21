"""Serialización a dicts planos (SQLite local: siempre se lee todo fresco
dentro del request; nada de lazy-loading tras cerrar la sesión)."""

from .. import config
from ..config import ELO_K, ELO_INICIAL
from ..models import (  # noqa: F401  (re-export útiles para routers)
    AhoraEscuchando,
    DropsFoto,
    EstadoPlan,
    EstadoPlanRegistro,
    NotaVoz,
    Partida,
    PinAudio,
    Plan,
    Usuario,
)
from .elo_service import esperado  # noqa: F401


def _abs_upload(filename: str) -> str:
    """Construye URL HTTPS absoluta para un archivo en /uploads."""
    if filename.startswith("http"):
        return filename
    # API_BASE_URL ya sin trailing slash
    return f"{config.API_BASE_URL}/uploads/{filename}"


def usuario_dict(u: Usuario, con_musica: bool = True) -> dict:
    d = {
        "id": u.id,
        "username": u.username,
        "display_name": u.display_name,
        "emoji": u.emoji,
        "avatar_color": u.avatar_color,
        "elo": u.elo,
        "status_text": u.status_text,
        "status_updated_at": u.status_updated_at.isoformat()
        if u.status_updated_at
        else None,
    }
    if con_musica:
        d["musica"] = musica_dict(u.musica) if u.musica else None
    return d


def musica_dict(m: AhoraEscuchando) -> dict:
    return {
        "provider": m.provider.value,
        "titulo": m.titulo,
        "artista": m.artista,
        "album": m.album,
        "artwork_url": m.artwork_url,
        "reproduciendo": m.reproduciendo,
        "updated_at": m.updated_at.isoformat() if m.updated_at else None,
    }


def nota_dict(n: NotaVoz) -> dict:
    return {
        "id": n.id,
        "usuario_id": n.usuario_id,
        "audio_url": _abs_upload(n.filename),
        "duration_s": n.duration_s,
        "created_at": n.created_at.isoformat(),
        "expires_at": n.expires_at.isoformat(),
    }


def pin_dict(p: PinAudio) -> dict:
    return {
        "id": p.id,
        "usuario_id": p.usuario_id,
        "audio_url": _abs_upload(p.filename),
        "duration_s": p.duration_s,
        "caption": p.caption,
        "created_at": p.created_at.isoformat(),
    }


def drop_dict(d: DropsFoto) -> dict:
    return {
        "id": d.id,
        "usuario_id": d.usuario_id,
        "img_url": _abs_upload(d.filename),
        "mime_type": d.mime_type,
        "size_bytes": d.size_bytes,
        "caption": d.caption,
        "created_at": d.created_at.isoformat(),
    }


def partida_dict(p: Partida, j1: Usuario, j2: Usuario) -> dict:
    return {
        "id": p.id,
        "juego": p.juego,
        "marcador1": p.marcador1,
        "marcador2": p.marcador2,
        "ganador_id": p.ganador_id,
        "reaction_audio": _abs_upload(p.reaction_audio)
        if p.reaction_audio
        else None,
        "jugador1": {"id": j1.id, "display_name": j1.display_name, "elo": p.elo1_antes, "elo_final": p.elo1_despues},
        "jugador2": {"id": j2.id, "display_name": j2.display_name, "elo": p.elo2_antes, "elo_final": p.elo2_despues},
        "created_at": p.created_at.isoformat(),
    }


def plan_dict(p: Plan, con_estados: bool = True) -> dict:
    d = {
        "id": p.id,
        "creador_id": p.creador_id,
        "titulo": p.titulo,
        "descripcion": p.descripcion,
        "lugar": p.lugar,
        "lat": p.lat,
        "lng": p.lng,
        "starts_at": p.starts_at.isoformat(),
        "created_at": p.created_at.isoformat(),
    }
    if con_estados:
        d["estados"] = [
            {
                "usuario_id": e.usuario_id,
                "estado": e.estado.value,
                "updated_at": e.updated_at.isoformat() if e.updated_at else None,
            }
            for e in p.estados
        ]
    return d


def elo_inicial() -> int:
    return ELO_INICIAL