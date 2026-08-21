"""El Bunker — API FastAPI.

Punto de entrada: uvicorn app.main:app

Ya configurado aquí (paso 1):
- CORS (orígenes desde config / entorno).
- Conexión SQLite: init_db() en el lifespan (tablas idempotentes).
- Archivos servidos en /uploads (drops, audios).
- WebSocket /ws con autenticación por token (query ?token=...).
- Tarea en background: limpieza de historias de voz de 24 h.
- /health para los pings externos que mantienen despierto Render free.

Los routers de negocio (auth, lobby, drops, voz, partidas, planes) se
suman en el paso 2; aquí solo el esqueleto estable.
"""

import asyncio
import json
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import config
from .database import SessionLocal, get_db, init_db
from .models import Usuario
from .routers import auth, drops, lobby, musica, notificaciones, partidas, planes, spotify, voz
from .services.cleanup_service import limpiar_notas_expiradas
from .ws.manager import manager


async def _bucle_limpieza() -> None:
    while True:
        await asyncio.sleep(config.LIMPIEZA_HORAS * 3600)
        try:
            borradas = limpiar_notas_expiradas()
            if borradas:
                await manager.transmitir(
                    {"type": "voz.expiradas", "eliminadas": borradas}
                )
        except Exception:
            pass  # el siguiente ciclo reintenta; nunca tumba la API


async def _bucle_spotify():
    # Poller Spotify cada 45s (config.SPOTIFY_POLL_SECONDS) — solo si hay credenciales
    if not config.SPOTIFY_CLIENT_ID or not config.SPOTIFY_CLIENT_SECRET:
        return
    from .services.spotify_poll import bucle_spotify

    await bucle_spotify()


@asynccontextmanager
async def _lifespan(app: FastAPI):
    init_db()
    config.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    tarea_limpieza = asyncio.create_task(_bucle_limpieza())
    tarea_spotify = asyncio.create_task(_bucle_spotify())
    yield
    tarea_limpieza.cancel()
    tarea_spotify.cancel()
    try:
        await tarea_limpieza
    except asyncio.CancelledError:
        pass
    try:
        await tarea_spotify
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="El Bunker API",
    version="0.1.0",
    description="Red social privada para el grupo cerrado (6).",
    lifespan=_lifespan,
)

# CORS: si es wildcard no se puede usar allow_credentials=True (falla en navegadores)
_cors_origins = config.CORS_ORIGINS
_cors_credentials = True
if len(_cors_origins) == 1 and _cors_origins[0] == "*":
    _cors_credentials = False
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_cors_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/uploads", StaticFiles(directory=config.UPLOAD_DIR), name="uploads")

# ---------------------------------------------------------------------------
# Routers de negocio (autenticados con header x-token + x-user-id)
# ---------------------------------------------------------------------------
app.include_router(auth.router)
app.include_router(spotify.router)
app.include_router(spotify.router_api)
app.include_router(spotify.router_api_auth)
app.include_router(notificaciones.router)
app.include_router(lobby.router)
app.include_router(musica.router)
app.include_router(drops.router)
app.include_router(voz.router)
app.include_router(partidas.router)
app.include_router(planes.router)


def _usuario_por_token(token: str) -> Usuario | None:
    db = SessionLocal()
    try:
        return db.query(Usuario).filter(Usuario.token == token).first()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Endpoints base
# ---------------------------------------------------------------------------
@app.get("/")
def raiz():
    return {"app": "el-bunker", "estado": "activo"}


@app.get("/health", dependencies=[Depends(get_db)])
def health():
    """Blanco del keep-alive externo (Render free duerme a los ~15 min)."""
    return {"ok": True, "ws_conectados": len(manager.conectados())}


# ---------------------------------------------------------------------------
# WebSocket del lobby
# ---------------------------------------------------------------------------
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: str = Query(...)):
    usuario = _usuario_por_token(token)
    if usuario is None:
        await websocket.close(code=4401)  # 4401 = no autorizado
        return

    await manager.conectar(usuario.id, websocket)
    try:
        while True:
            texto = await websocket.receive_text()
            try:
                data = json.loads(texto)
            except json.JSONDecodeError:
                data = {}
            # Por ahora solo acuse; los comandos de negocio se definen en
            # el paso 2 (el flujo principal es push del servidor).
            await manager.enviar(
                usuario.id,
                {
                    "type": "ack",
                    "usuario_id": usuario.id,
                    "recibido": data,
                },
            )
    except WebSocketDisconnect:
        await manager.desconectar(usuario.id)