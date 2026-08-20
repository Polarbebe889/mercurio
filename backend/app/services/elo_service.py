"""Cálculo Elo estándar (K=32; empate 0.5 cada uno)."""

from math import log10

from .. import config


def esperado(ra: int, rb: int) -> float:
    """Puntuación esperada del jugador A contra B (0..1)."""
    return 1.0 / (1.0 + 10 ** ((rb - ra) / 400))


def aplicar_elo(ra: int, rb: int, resultado: float) -> tuple[int, int]:
    """Devuelve (nuevo_ra, nuevo_rb).

    resultado: 1.0 gana A, 0.5 empate, 0.0 gana B.
    """
    ea = esperado(ra, rb)
    na = round(ra + config.ELO_K * (resultado - ea))
    nb = round(rb + config.ELO_K * (ea - resultado))
    return na, nb