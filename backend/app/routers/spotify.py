import base64
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Usuario

router = APIRouter(prefix="/auth/spotify", tags=["spotify"])
# Alias routers para cubrir /api/spotify/callback y /api/auth/spotify/callback (404 fix)
router_api = APIRouter(prefix="/api/spotify", tags=["spotify"])
router_api_auth = APIRouter(prefix="/api/auth/spotify", tags=["spotify"])


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
    # state = token de Mercurio
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
    # Éxito: intenta redirigir a custom scheme mercurio://callback y muestra HTML elegante
    return HTMLResponse(
        """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Mercurio — Spotify conectado</title>
        <style>body{background:#050505;color:#FFF8E7;font-family:Inter,system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
        .card{background:#141414;border:1px solid rgba(255,255,255,0.06);border-radius:18px;padding:32px;max-width:420px;width:100%}
        .check{width:64px;height:64px;background:#1DB954;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 16px;font-size:32px}
        a{color:#1DB954;text-decoration:none;font-weight:700} p{color:#8A929A;font-size:14px}</style>
        </head><body><div class="card"><div class="check">✓</div><h1 style="margin:0 0 8px">Spotify conectado</h1>
        <p>Vuelve a Mercurio — puedes cerrar esta ventana.</p>
        <p><a href="mercurio://callback?success=1">Abrir Mercurio</a></p>
        <p style="margin-top:16px;font-size:12px;color:#8A929A">Se cerrará automáticamente en 2 segundos…</p>
        </div><script>setTimeout(()=>{try{window.location.href='mercurio://callback?success=1'}catch(e){};},300);setTimeout(()=>window.close(),2000)</script></body></html>"""
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


# Ruta directa /api/spotify/callback sin prefix extra (spec pide @app.get("/api/spotify/callback"))
# Se maneja vía router_api, pero si Spotify está registrado como /api/spotify/callback absoluto, ya está cubierto.
