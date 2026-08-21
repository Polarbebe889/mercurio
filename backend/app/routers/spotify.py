import base64
import os
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Usuario
from .auth import get_usuario_actual

router = APIRouter(prefix="/auth/spotify", tags=["spotify"])
# Alias routers para cubrir /api/spotify/callback y /api/auth/spotify/callback (404 fix)
router_api = APIRouter(prefix="/api/spotify", tags=["spotify"])
router_api_auth = APIRouter(prefix="/api/auth/spotify", tags=["spotify"])

SCOPES = "user-read-email user-read-private user-top-read playlist-read-private"


def _encode_state(user_id: int) -> str:
    return base64.urlsafe_b64encode(str(user_id).encode()).decode()


def _decode_state(state: str) -> int | None:
    try:
        return int(base64.urlsafe_b64decode(state.encode()).decode())
    except Exception:
        return None


async def _handle_spotify_callback(code: str, state: str, error: str, db: Session, request: Request):
    if error:
        return HTMLResponse(
            f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Spotify</title></head><body style="background:#050505;color:#FFF8E7;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px">
            <div><h1 style="color:#EF4444">Spotify error: {error}</h1><p>Cierra esta ventana y vuelve a Mercurio.</p>
            <a href="mercurio://callback?error={error}" style="color:#1DB954">Volver a Mercurio</a></div></body></html>""",
            status_code=400,
        )
    if not code or not state:
        raise HTTPException(400, "code/state faltan — vuelve a iniciar login desde Mercurio")
    # state puede ser base64(user_id) (nuevo, seguro, de files.zip) o token legacy (compat)
    user = None
    uid = _decode_state(state)
    if uid is not None:
        user = db.query(Usuario).filter(Usuario.id == uid).first()
    if user is None:
        user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        return HTMLResponse(
            """<!doctype html><html><body style="background:#050505;color:#FFF8E7;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px">
            <div><h1>Token de Mercurio inválido</h1><p>Inicia sesión de nuevo en Mercurio y reintenta conectar Spotify.</p></div></body></html>""",
            status_code=401,
        )
    if not config.SPOTIFY_CLIENT_SECRET:
        return HTMLResponse("<h1>SPOTIFY_CLIENT_SECRET no configurado en Render</h1><p>Configura la variable de entorno en Render Dashboard.</p>", status_code=500)
    # intercambiar code por tokens - intenta con redirect_uri configurado y con fallback derivado del request
    auth = base64.b64encode(f"{config.SPOTIFY_CLIENT_ID}:{config.SPOTIFY_CLIENT_SECRET}".encode()).decode()
    # Posibles redirect_uris a probar (el registrado en Spotify Dashboard debe coincidir)
    candidates = [config.SPOTIFY_REDIRECT_URI]
    # Derivar del request actual (útil si Spotify está registrado como /api/spotify/callback)
    try:
        base = str(request.base_url).rstrip("/")
        for p in ["/auth/spotify/callback", "/api/spotify/callback", "/api/auth/spotify/callback"]:
            cand = base + p
            if cand not in candidates:
                candidates.append(cand)
    except Exception:
        pass
    j = None
    last_resp = None
    async with httpx.AsyncClient() as client:
        for redirect_uri in candidates:
            r = await client.post(
                "https://accounts.spotify.com/api/token",
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": redirect_uri,
                },
                headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
            )
            last_resp = r
            if r.status_code == 200:
                j = r.json()
                break
    if j is None:
        r = last_resp  # type: ignore
        return HTMLResponse(f"<h1>Spotify token error {r.status_code}: {r.text}</h1><p>Verifica que el redirect_uri en Spotify Dashboard coincida con {config.SPOTIFY_REDIRECT_URI}</p>", status_code=400)
    user.spotify_access_token = j.get("access_token")
    if j.get("refresh_token"):
        user.spotify_refresh_token = j.get("refresh_token")
    db.commit()
    # Crea placeholder AhoraEscuchando para que el frontend detecte "conectado" inmediato (antes del primer poll de 45s)
    try:
        from ..models import AhoraEscuchando, ProviderMusica
        from ..services.serializers import musica_dict
        from ..ws.manager import manager

        existente = db.get(AhoraEscuchando, user.id)
        if existente is None:
            placeholder = AhoraEscuchando(usuario_id=user.id, provider=ProviderMusica.SPOTIFY, titulo="", artista="", album="", artwork_url="", reproduciendo=False)
            db.add(placeholder)
            db.commit()
            db.refresh(placeholder)
            # no bloquees el callback si WS falla
            try:
                import asyncio

                asyncio.create_task(manager.transmitir({"type": "musica.actualizada", "usuario_id": user.id, "musica": musica_dict(placeholder)}))
            except Exception:
                pass
        elif existente.provider != ProviderMusica.SPOTIFY:
            pass
        else:
            # ya existe spotify, asegura que siga con reproduciendo=False hasta el primer poll
            pass
    except Exception:
        pass  # no rompas el callback si falla el placeholder
    # Éxito: intenta redirigir a custom scheme y muestra HTML con fallback manual (Safari bloquea window.close si no es user gesture)
    return HTMLResponse(
        """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Mercurio — Spotify conectado</title>
        <style>body{background:#050505;color:#FFF8E7;font-family:Inter,system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
        .card{background:#141414;border:1px solid rgba(255,255,255,0.06);border-radius:18px;padding:32px;max-width:420px;width:100%}
        .check{width:64px;height:64px;background:#1DB954;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 16px;font-size:32px}
        a{color:#1DB954;text-decoration:none;font-weight:700} p{color:#8A929A;font-size:14px} button{background:#1DB954;color:white;border:none;padding:12px 24px;border-radius:12px;font-weight:700;margin-top:12px;cursor:pointer}</style>
        </head><body><div class="card"><div class="check">✓</div><h1 style="margin:0 0 8px">Spotify conectado</h1>
        <p>¡Listo! Vuelve a <b>Uranio/Mercurio</b> y haz <b>pull-to-refresh</b>. No necesitas abrir el link.</p>
        <p style="font-size:12px;color:#8A929A">Si tu app no detecta al instante, cierra esta pestaña y vuelve.</p>
        <p><a href="mercurio://callback?success=1">Abrir Mercurio</a> · <a href="uranio://callback?success=1">Abrir Uranio</a> · <a href="el-bunker://callback?success=1">Abrir El Bunker</a></p>
        <button onclick="try{window.close()}catch(e){}; window.location.href='about:blank'">Cerrar ventana</button>
        <p style="margin-top:16px;font-size:12px;color:#8A929A">Se cerrará sola en 3s si tu navegador lo permite…</p>
        </div><script>
        // Intenta deep link con múltiples esquemas (Safari bloquea si no hay gesto, por eso el fallback manual)
        setTimeout(()=>{try{window.location.href='mercurio://callback?success=1'}catch(e){}},500);
        setTimeout(()=>{try{window.location.href='uranio://callback?success=1'}catch(e){}},800);
        setTimeout(()=>{try{window.location.href='el-bunker://callback?success=1'}catch(e){}},1100);
        setTimeout(()=>{try{window.close()}catch(e){}},3000);
        </script></body></html>"""
    )


@router.get("/callback")
async def callback(request: Request, code: str = "", state: str = "", error: str = "", db: Session = Depends(get_db)):
    return await _handle_spotify_callback(code, state, error, db, request)


@router_api.get("/callback")
async def callback_api(request: Request, code: str = "", state: str = "", error: str = "", db: Session = Depends(get_db)):
    return await _handle_spotify_callback(code, state, error, db, request)


@router_api_auth.get("/callback")
async def callback_api_auth(request: Request, code: str = "", state: str = "", error: str = "", db: Session = Depends(get_db)):
    return await _handle_spotify_callback(code, state, error, db, request)

@router.get("/status")
def spotify_status(state: str = "", db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        raise HTTPException(401, "token inválido")
    return {"conectado": bool(user.spotify_refresh_token)}


@router_api.get("/status")
def spotify_status_api(state: str = "", db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        raise HTTPException(401, "token inválido")
    return {"conectado": bool(user.spotify_refresh_token)}


@router_api_auth.get("/status")
def spotify_status_api_auth(state: str = "", db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        raise HTTPException(401, "token inválido")
    return {"conectado": bool(user.spotify_refresh_token)}


# --- Login helper: genera auth_url con base64(user_id) como state (no expone token) ---
@router.get("/login")
def spotify_login(usuario: Usuario = Depends(get_usuario_actual)):
    state = _encode_state(usuario.id)
    params = {
        "client_id": config.SPOTIFY_CLIENT_ID,
        "response_type": "code",
        "redirect_uri": config.SPOTIFY_REDIRECT_URI,
        "scope": SCOPES,
        "state": state,
        "show_dialog": "true",
    }
    auth_url = f"https://accounts.spotify.com/authorize?{urlencode(params)}"
    return {"auth_url": auth_url}


@router_api.get("/login")
def spotify_login_api(usuario: Usuario = Depends(get_usuario_actual)):
    state = _encode_state(usuario.id)
    params = {
        "client_id": config.SPOTIFY_CLIENT_ID,
        "response_type": "code",
        "redirect_uri": config.SPOTIFY_REDIRECT_URI,
        "scope": SCOPES,
        "state": state,
        "show_dialog": "true",
    }
    auth_url = f"https://accounts.spotify.com/authorize?{urlencode(params)}"
    return {"auth_url": auth_url}


@router_api_auth.get("/login")
def spotify_login_api_auth(usuario: Usuario = Depends(get_usuario_actual)):
    state = _encode_state(usuario.id)
    params = {
        "client_id": config.SPOTIFY_CLIENT_ID,
        "response_type": "code",
        "redirect_uri": config.SPOTIFY_REDIRECT_URI,
        "scope": SCOPES,
        "state": state,
        "show_dialog": "true",
    }
    auth_url = f"https://accounts.spotify.com/authorize?{urlencode(params)}"
    return {"auth_url": auth_url}


# Ruta directa /api/spotify/callback sin prefix extra (spec pide @app.get("/api/spotify/callback"))
# Se maneja vía router_api, pero si Spotify está registrado como /api/spotify/callback absoluto, ya está cubierto.
