"""Capa de base de datos SQLite (SQLAlchemy 2.0, ORM declarativo).

- `engine`: único motor SQLite del proceso.
- `SessionLocal`: fábrica de sesiones por request (thread-safe con
  `check_same_thread=False`, SQLite bloquea el archivo correctamente).
- `Base`: raíz de todos los modelos (registrados en `models.py`).
- `get_db()`: dependencia FastAPI con cierre garantizado de sesión.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import DATABASE_URL

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=_connect_args)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    """Dependencia de FastAPI: una sesión por request, siempre cerrada."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Crea TODAS las tablas si no existen (idempotente, seguro en cada boot)."""
    # Import dentro de la función: los modelos necesitan Base, y Base
    # está aquí. Sin el import, create_all no sabría qué tablas crear.
    from . import models  # noqa: F401

    Base.metadata.create_all(bind=engine)