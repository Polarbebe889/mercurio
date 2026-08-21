"""Competitivo: registro de retas, cálculo de Elo y reacciones de voz."""

from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Partida, Usuario
from ..schemas import PartidaIn
from ..services.elo_service import aplicar_elo
from ..services.fcm_service import notificar_a_todos
from ..services.serializers import partida_dict
from ..services.uploads import eliminar_media, guardar_media
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/partidas", tags=["partidas"])

TIPOS_AUDIO = {"audio/mpeg", "audio/mp4", "audio/aac", "audio/ogg", "audio/wav"}


def _oponente(db: Session, user: Usuario, partida: Partida) -> Usuario:
    return db.get(Usuario, partida.jugador2_id if user.id == partida.jugador1_id else partida.jugador1_id)


@router.post("", status_code=201)
async def registrar_partida(
    datos: PartidaIn,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    if datos.contrincante_id == usuario.id:
        raise HTTPException(422, "no puedes retarte a ti mismo")
    contrincante = db.get(Usuario, datos.contrincante_id)
    if contrincante is None:
        raise HTTPException(404, "contrincante no existe")

    # Resultado desde el punto de vista del jugador 1.
    if datos.marcador1 > datos.marcador2:
        resultado, ganador_id = 1.0, usuario.id
    elif datos.marcador1 < datos.marcador2:
        resultado, ganador_id = 0.0, contrincante.id
    else:
        resultado, ganador_id = 0.5, None

    elo1_antes, elo2_antes = usuario.elo, contrincante.elo
    elo1_despues, elo2_despues = aplicar_elo(elo1_antes, elo2_antes, resultado)

    partida = Partida(
        jugador1_id=usuario.id,
        jugador2_id=contrincante.id,
        marcador1=datos.marcador1,
        marcador2=datos.marcador2,
        ganador_id=ganador_id,
        juego=datos.juego,
        elo1_antes=elo1_antes,
        elo2_antes=elo2_antes,
        elo1_despues=elo1_despues,
        elo2_despues=elo2_despues,
    )
    db.add(partida)
    usuario.elo = elo1_despues
    contrincante.elo = elo2_despues
    db.commit()
    db.refresh(partida)

    await manager.transmitir(
        {
            "type": "partida.nueva",
            "partida": partida_dict(partida, usuario, contrincante),
        }
    )
    try:
        ganador = usuario.display_name if ganador_id == usuario.id else contrincante.display_name if ganador_id else "Empate"
        await notificar_a_todos(
            db,
            titulo=f"Reta {datos.juego} 🏆",
            cuerpo=f"{usuario.display_name} {datos.marcador1} - {datos.marcador2} {contrincante.display_name}" + (f" → {ganador}" if ganador_id else ""),
            data={"type": "partida.nueva", "partida_id": str(partida.id)},
            excluir=usuario.id,
        )
    except Exception:
        pass
    return partida_dict(partida, usuario, contrincante)


@router.post("/{partida_id}/reaccion", status_code=201)
async def reaccion_voz(
    partida_id: int,
    file: UploadFile = File(...),
    duration_s: int = Form(default=0, ge=0, le=600),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    partida = db.get(Partida, partida_id)
    if partida is None:
        raise HTTPException(404, "partida no existe")
    if usuario.id not in (partida.jugador1_id, partida.jugador2_id):
        raise HTTPException(403, "solo los jugadores pueden reaccionar")

    eliminar_media(partida.reaction_audio)  # la reacción se puede repetir
    filename, mime, _ = await guardar_media(file, TIPOS_AUDIO, config.MAX_AUDIO_BYTES)
    partida.reaction_audio = filename
    db.commit()
    db.refresh(partida)

    j1 = db.get(Usuario, partida.jugador1_id)
    j2 = db.get(Usuario, partida.jugador2_id)
    await manager.transmitir(
        {
            "type": "partida.reaccion",
            "partida": partida_dict(partida, j1, j2),
        }
    )
    return partida_dict(partida, j1, j2)


@router.get("")
def historial(
    limite: int = 50, db: Session = Depends(get_db), _: Usuario = Depends(get_usuario_actual)
):
    items = (
        db.query(Partida)
        .order_by(Partida.created_at.desc())
        .limit(min(limite, 200))
        .all()
    )
    usuarios = {u.id: u for u in db.query(Usuario).all()}
    return {
        "partidas": [
            partida_dict(p, usuarios.get(p.jugador1_id), usuarios.get(p.jugador2_id))
            for p in items
        ]
    }


@router.get("/ranking")
def ranking(db: Session = Depends(get_db), _: Usuario = Depends(get_usuario_actual)):
    usuarios = db.query(Usuario).all()
    filas = []
    for u in usuarios:
        juegos = (
            db.query(Partida)
            .filter(
                (Partida.jugador1_id == u.id) | (Partida.jugador2_id == u.id)
            )
            .all()
        )
        victorias = sum(1 for p in juegos if p.ganador_id == u.id)
        empates = sum(1 for p in juegos if p.ganador_id is None)
        filas.append(
            {
                "id": u.id,
                "display_name": u.display_name,
                "emoji": u.emoji,
                "elo": u.elo,
                "victorias": victorias,
                "empates": empates,
                "derrotas": len(juegos) - victorias - empates,
            }
        )
    filas.sort(key=lambda f: f["elo"], reverse=True)
    for i, f in enumerate(filas, start=1):
        f["posicion"] = i
    return {"ranking": filas}