"""Modelos ORM de El Bunker.

Diagrama de tablas:
- usuarios                -> identidad, estado del lobby y puntuación Elo
- drops_fotos             -> pines de foto permanentes (sin pérdida de calidad)
- notas_voz               -> historias de voz de 24 h (índice en expires_at)
- pines_audio             -> notas de voz fijadas de forma permanente
- partidas                -> retas/juegos registrados con Elo antes/después
- planes                  -> salidas y planes rápidos con ubicación + hora
- estados_plan            -> botones de 1 toque por usuario y por plan
- ahora_escuchando        -> canción vigente (Spotify / MusicKit) por usuario
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class EstadoPlan(PyEnum):
    """Botones de 1 toque del coordinador de salidas."""

    SIN_ESTADO = "sin_estado"
    ALISTANDO = "alistandome"
    EN_CAMINO = "en_camino"
    LLEGUE = "llegue"


class ProviderMusica(PyEnum):
    SPOTIFY = "spotify"
    MUSIC_KIT = "music_kit"


def _utcnow() -> datetime:
    return datetime.utcnow()


# ---------------------------------------------------------------------------
# Usuarios
# ---------------------------------------------------------------------------
class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(40))
    emoji: Mapped[str] = mapped_column(String(8), default="🫡")
    avatar_color: Mapped[str] = mapped_column(String(9), default="#EDE9E2")
    # Token de acceso de la app (cerrado: sin contraseñas, solo el grupo).
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # PIN 4 dígitos para login persistente (ej. 'ova' + 1234). Guarda bcrypt hash (60) o plain legacy (4) para compat.
    pin: Mapped[str | None] = mapped_column(String(72), nullable=True)
    # Estado del lobby ("Jugando Xbox", "En camino"…)
    status_text: Mapped[str | None] = mapped_column(String(120), nullable=True)
    status_updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Spotify OAuth
    spotify_refresh_token: Mapped[str | None] = mapped_column(String(500), nullable=True)
    spotify_access_token: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # Puntuación Elo
    elo: Mapped[int] = mapped_column(Integer, default=1000)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)

    drops: Mapped[list["DropsFoto"]] = relationship(back_populates="autor", cascade="all, delete-orphan")
    notas_voz: Mapped[list["NotaVoz"]] = relationship(back_populates="autor", cascade="all, delete-orphan")
    pines_audio: Mapped[list["PinAudio"]] = relationship(back_populates="autor", cascade="all, delete-orphan")
    partidas_como_j1: Mapped[list["Partida"]] = relationship(
        back_populates="jugador1", foreign_keys="Partida.jugador1_id", cascade="all, delete-orphan"
    )
    partidas_como_j2: Mapped[list["Partida"]] = relationship(
        back_populates="jugador2", foreign_keys="Partida.jugador2_id", cascade="all, delete-orphan"
    )
    planes_creados: Mapped[list["Plan"]] = relationship(back_populates="creador", cascade="all, delete-orphan")
    estados_plan: Mapped[list["EstadoPlanRegistro"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )
    musica: Mapped["AhoraEscuchando | None"] = relationship(
        back_populates="usuario", cascade="all, delete-orphan", uselist=False
    )


# ---------------------------------------------------------------------------
# Drops: pines de foto permanentes
# ---------------------------------------------------------------------------
class DropsFoto(Base):
    __tablename__ = "drops_fotos"
    __table_args__ = (Index("ix_drops_creado", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    filename: Mapped[str] = mapped_column(String(255))
    mime_type: Mapped[str] = mapped_column(String(32))
    size_bytes: Mapped[int] = mapped_column(Integer, default=0)
    caption: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)

    autor: Mapped["Usuario"] = relationship(back_populates="drops")


# ---------------------------------------------------------------------------
# Notas de voz
# ---------------------------------------------------------------------------
class NotaVoz(Base):
    """Historia de voz: se borra (fila + archivo) tras 24 horas."""

    __tablename__ = "notas_voz"
    __table_args__ = (Index("ix_notas_expira", "expires_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    filename: Mapped[str] = mapped_column(String(255))
    mime_type: Mapped[str] = mapped_column(String(32))
    duration_s: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)

    autor: Mapped["Usuario"] = relationship(back_populates="notas_voz")


class PinAudio(Base):
    """Memes internos / audios graciosos fijados de forma permanente."""

    __tablename__ = "pines_audio"
    __table_args__ = (Index("ix_pines_audio_creado", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    filename: Mapped[str] = mapped_column(String(255))
    mime_type: Mapped[str] = mapped_column(String(32))
    duration_s: Mapped[int] = mapped_column(Integer, default=0)
    caption: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)

    autor: Mapped["Usuario"] = relationship(back_populates="pines_audio")


# ---------------------------------------------------------------------------
# Competitivo: partidas + Elo
# ---------------------------------------------------------------------------
class Partida(Base):
    __tablename__ = "partidas"
    __table_args__ = (Index("ix_partidas_creado", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    jugador1_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    jugador2_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    marcador1: Mapped[int] = mapped_column(Integer, default=0)
    marcador2: Mapped[int] = mapped_column(Integer, default=0)
    # Ganador (null = empate). Elo solo se mueve si hay ganador.
    ganador_id: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id", ondelete="SET NULL"), nullable=True)
    juego: Mapped[str] = mapped_column(String(40), default="retas")
    # Reacción de voz vinculada al historial de la partida.
    reaction_audio: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Snapshot Elo para el historial (antes → después de cada jugador).
    elo1_antes: Mapped[int] = mapped_column(Integer)
    elo2_antes: Mapped[int] = mapped_column(Integer)
    elo1_despues: Mapped[int] = mapped_column(Integer)
    elo2_despues: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)

    jugador1: Mapped["Usuario"] = relationship(back_populates="partidas_como_j1", foreign_keys=[jugador1_id])
    jugador2: Mapped["Usuario"] = relationship(back_populates="partidas_como_j2", foreign_keys=[jugador2_id])


# ---------------------------------------------------------------------------
# Coordinador de salidas
# ---------------------------------------------------------------------------
class Plan(Base):
    __tablename__ = "planes"
    __table_args__ = (Index("ix_planes_inicio", "starts_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    creador_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    titulo: Mapped[str] = mapped_column(String(80))
    descripcion: Mapped[str] = mapped_column(Text, default="")
    lugar: Mapped[str] = mapped_column(String(120), default="")
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)

    creador: Mapped["Usuario"] = relationship(back_populates="planes_creados")
    estados: Mapped[list["EstadoPlanRegistro"]] = relationship(
        back_populates="plan", cascade="all, delete-orphan"
    )


class EstadoPlanRegistro(Base):
    """Estado de 1 toque de cada usuario para un plan concreto."""

    __tablename__ = "estados_plan"
    __table_args__ = (UniqueConstraint("plan_id", "usuario_id", name="uq_plan_usuario"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("planes.id", ondelete="CASCADE"), index=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"), index=True)
    estado: Mapped[EstadoPlan] = mapped_column(
        Enum(EstadoPlan, native_enum=False, length=16), default=EstadoPlan.SIN_ESTADO
    )
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, onupdate=_utcnow)

    plan: Mapped["Plan"] = relationship(back_populates="estados")
    usuario: Mapped["Usuario"] = relationship(back_populates="estados_plan")


# ---------------------------------------------------------------------------
# Música en vivo (ahora escuchando)
# ---------------------------------------------------------------------------
class AhoraEscuchando(Base):
    __tablename__ = "ahora_escuchando"

    usuario_id: Mapped[int] = mapped_column(
        ForeignKey("usuarios.id", ondelete="CASCADE"), primary_key=True
    )
    provider: Mapped[ProviderMusica] = mapped_column(
        Enum(ProviderMusica, native_enum=False, length=12), default=ProviderMusica.SPOTIFY
    )
    titulo: Mapped[str] = mapped_column(String(200), default="")
    artista: Mapped[str] = mapped_column(String(120), default="")
    album: Mapped[str] = mapped_column(String(120), default="")
    artwork_url: Mapped[str] = mapped_column(String(500), default="")
    reproduciendo: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, onupdate=_utcnow)

    usuario: Mapped["Usuario"] = relationship(back_populates="musica")