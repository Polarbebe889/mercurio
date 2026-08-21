import base64
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session

from .. import config
from ..database import get_db
from ..models import Usuario

router = APIRouter(prefix="/auth/spotify", tags=["spotify"])

@router.get("/callback")
async def callback(code: str = "", state: str = "", error: str = "", db: Session = Depends(get_db)):
    if error:
        return HTMLResponse(f"<h1>Spotify error: {error}</h1>", status_code=400)
    if not code or not state:
        raise HTTPException(400, "code/state faltan")
    # state = token de Mercurio
    user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        return HTMLResponse("<h1>Token de Mercurio inválido</h1>", status_code=401)
    if not config.SPOTIFY_CLIENT_SECRET:
        return HTMLResponse("<h1>SPOTIFY_CLIENT_SECRET no configurado en Render</h1>", status_code=500)
    # intercambiar code por tokens
    auth = base64.b64encode(f"{config.SPOTIFY_CLIENT_ID}:{config.SPOTIFY_CLIENT_SECRET}".encode()).decode()
    async with httpx.AsyncClient() as client:
        r = await client.post("https://accounts.spotify.com/api/token", data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.SPOTIFY_REDIRECT_URI,
        }, headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"})
    if r.status_code != 200:
        return HTMLResponse(f"<h1>Spotify token error {r.status_code}: {r.text}</h1>", status_code=400)
    j = r.json()
    user.spotify_access_token = j.get("access_token")
    if j.get("refresh_token"):
        user.spotify_refresh_token = j.get("refresh_token")
    db.commit()
    return HTMLResponse("<h1>✓ Spotify conectado — vuelve a Mercurio</h1><script>setTimeout(()=>window.close(),2000)</script>")

@router.get("/status")
def spotify_status(state: str = "", db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.token == state).first()
    if not user:
        raise HTTPException(401, "token inválido")
    return {"conectado": bool(user.spotify_refresh_token)}
