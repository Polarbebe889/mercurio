"""FCM push para Mercurio (6 usuarios, fan-out).

Requiere:
- pip install firebase-admin
- Variable FIREBASE_CREDENTIALS_JSON o archivo /etc/secrets/firebase.json
  con el service account JSON de Firebase. Si no está, el servicio hace no-op
  (no rompe la API, solo loguea).
"""

import json
import logging
import os
from typing import List

log = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    try:
        import firebase_admin
        from firebase_admin import credentials

        # 1. Intenta desde env var JSON directo
        cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
        if cred_json:
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
            _firebase_app = firebase_admin.initialize_app(cred)
            log.info("[FCM] Firebase inicializado desde FIREBASE_CREDENTIALS_JSON")
            return _firebase_app
        # 2. Intenta desde archivo (Render Secret File)
        for path in ["/etc/secrets/firebase.json", "firebase.json", "backend/firebase.json"]:
            if os.path.exists(path):
                cred = credentials.Certificate(path)
                _firebase_app = firebase_admin.initialize_app(cred)
                log.info(f"[FCM] Firebase inicializado desde {path}")
                return _firebase_app
        log.warning("[FCM] No hay credenciales Firebase, push deshabilitado (solo WS)")
        return None
    except Exception as e:
        log.warning(f"[FCM] init failed (push deshabilitado): {e}")
        return None


async def enviar_push_a_tokens(tokens: List[str], titulo: str, cuerpo: str, data: dict | None = None):
    if not tokens:
        return
    app = _get_firebase_app()
    if app is None:
        log.info(f"[FCM] no-op (sin credenciales) -> {titulo}: {cuerpo} a {len(tokens)} tokens")
        return
    try:
        from firebase_admin import messaging

        # FCM multicast (hasta 500 tokens, nosotros max 6)
        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=titulo, body=cuerpo),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound="default"))),
        )
        resp = messaging.send_each_for_multicast(message)
        log.info(f"[FCM] enviado {titulo} -> {resp.success_count}/{len(tokens)} ok, {resp.failure_count} fail")
        if resp.failure_count:
            for r in resp.responses:
                if not r.success:
                    log.warning(f"[FCM] fallo token: {r.exception}")
    except Exception as e:
        log.warning(f"[FCM] send failed: {e}")


async def notificar_a_usuarios(db, usuario_ids: List[int], titulo: str, cuerpo: str, data: dict | None = None, excluir: int | None = None):
    """Fan-out a todos los tokens de los usuarios_ids (excluye al autor si se pide)."""
    from ..models import FcmToken

    if excluir is not None:
        usuario_ids = [uid for uid in usuario_ids if uid != excluir]
    if not usuario_ids:
        return
    tokens = [t.token for t in db.query(FcmToken).filter(FcmToken.usuario_id.in_(usuario_ids)).all()]
    # dedup
    tokens = list(dict.fromkeys(tokens))
    await enviar_push_a_tokens(tokens, titulo, cuerpo, data)


async def notificar_a_todos(db, titulo: str, cuerpo: str, data: dict | None = None, excluir: int | None = None):
    """A todos los usuarios registrados (max 6)."""
    from ..models import Usuario, FcmToken

    q = db.query(FcmToken)
    if excluir is not None:
        # filtra tokens cuyo usuario_id != excluir
        q = q.filter(FcmToken.usuario_id != excluir)
    tokens = [t.token for t in q.all()]
    tokens = list(dict.fromkeys(tokens))
    await enviar_push_a_tokens(tokens, titulo, cuerpo, data)
