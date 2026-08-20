"""Gestor central de conexiones WebSocket (una por usuario autenticado).

Eventos que circulan por aquí (formato JSON):
    {"type": "status.actualizado", "usuario": {...}}
    {"type": "musica.actualizada",  "usuario": {...}}
    {"type": "drop.nuevo",          "drop": {...}}
    {"type": "voz.nueva",           "nota": {...}}
    {"type": "voz.expirada",        "nota_id": 12}
    {"type": "partida.registrada",  "partida": {...}}
    {"type": "plan.estado",         "plan_id": 1, "usuario": {...}}
Los nombres exactos se acordarán en los routers (paso 2).
"""

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self._sockets: dict[int, WebSocket] = {}

    async def conectar(self, usuario_id: int, ws: WebSocket) -> None:
        # Una sola conexión por usuario: la vieja se cierra para evitar
        # eventos duplicados en el cliente.
        anterior = self._sockets.pop(usuario_id, None)
        if anterior is not None:
            await anterior.close(code=4001)
        await ws.accept()
        self._sockets[usuario_id] = ws

    async def desconectar(self, usuario_id: int) -> None:
        self._sockets.pop(usuario_id, None)

    async def enviar(self, usuario_id: int, evento: dict) -> bool:
        """Envía a un usuario; False si no está conectado."""
        ws = self._sockets.get(usuario_id)
        if ws is None:
            return False
        await ws.send_json(evento)
        return True

    async def transmitir(self, evento: dict, ignorar: int | None = None) -> None:
        """Broadcast a todo el lobby (opcional: sin incluir a un usuario)."""
        for usuario_id, ws in list(self._sockets.items()):
            if usuario_id == ignorar:
                continue
            try:
                await ws.send_json(evento)
            except Exception:
                # Conexión rota: la limpia el handler de /ws al desconectar.
                self._sockets.pop(usuario_id, None)

    def conectados(self) -> list[int]:
        return list(self._sockets.keys())


manager = ConnectionManager()