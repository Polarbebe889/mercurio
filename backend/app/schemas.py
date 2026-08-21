"""Esquemas Pydantic (v2) para request/response de la API."""

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict, Field


class EstadoPlanIn(str, Enum):
    alistandome = "alistandome"
    en_camino = "en_camino"
    llegue = "llegue"


# ---------------------------------------------------------------------------
# Auth - Login persistente con PIN 4 dígitos
# ---------------------------------------------------------------------------
class RegistroIn(BaseModel):
    username: str = Field(min_length=2, max_length=32)
    display_name: str = Field(min_length=1, max_length=40, default="")
    join_code: str
    emoji: str = "🫡"
    avatar_color: str = "#EDE9E2"
    pin: str = Field(default="0000", min_length=4, max_length=4, pattern=r"^\d{4}$")


class LoginIn(BaseModel):
    username: str = Field(min_length=2, max_length=32)
    pin: str = Field(min_length=4, max_length=4, pattern=r"^\d{4}$")


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: str
    emoji: str
    avatar_color: str
    elo: int
    status_text: str | None = None
    status_updated_at: datetime | None = None


class RegistroOut(BaseModel):
    usuario: UsuarioOut
    token: str


# ---------------------------------------------------------------------------
# Lobby y música
# ---------------------------------------------------------------------------
class StatusIn(BaseModel):
    status_text: str = Field(max_length=120)


class MusicaIn(BaseModel):
    provider: str = "spotify"  # spotify | music_kit
    titulo: str = Field(max_length=200)
    artista: str = Field(max_length=120)
    album: str = Field(max_length=120, default="")
    artwork_url: str = Field(max_length=500, default="")
    reproduciendo: bool = True


# ---------------------------------------------------------------------------
# Partidas (Elo)
# ---------------------------------------------------------------------------
class PartidaIn(BaseModel):
    contrincante_id: int
    marcador1: int = Field(ge=0)
    marcador2: int = Field(ge=0)
    juego: str = Field(default="retas", max_length=40)


# ---------------------------------------------------------------------------
# Planes
# ---------------------------------------------------------------------------
class PlanIn(BaseModel):
    titulo: str = Field(min_length=1, max_length=80)
    descripcion: str = Field(default="", max_length=2000)
    lugar: str = Field(default="", max_length=120)
    lat: float | None = None
    lng: float | None = None
    starts_at: datetime


class PlanEstadoIn(BaseModel):
    estado: EstadoPlanIn