"""Coordinador de salidas: planes rápidos + botones de 1 toque.
"En camino" emite un evento por WebSocket para que la app lance la push
de alerta a los otros 5."""

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import EstadoPlan, EstadoPlanRegistro, Plan, Usuario
from ..schemas import PlanEstadoIn, PlanIn
from ..services.fcm_service import notificar_a_todos
from ..services.serializers import plan_dict, usuario_dict
from ..ws.manager import manager
from .auth import get_usuario_actual

router = APIRouter(prefix="/planes", tags=["planes"])


@router.get("")
def listar_planes(
    activo: bool = True,
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_usuario_actual),
):
    q = db.query(Plan)
    if activo:
        # Muestra el de hoy y lo que venga después de la hora pasada.
        q = q.filter(Plan.starts_at >= datetime.utcnow() - timedelta(hours=1))
    planes = q.order_by(Plan.starts_at.asc()).limit(30).all()
    return {
        "planes": [
            {
                **plan_dict(p),
                "creador": {"id": p.creador.id, "display_name": p.creador.display_name},
            }
            for p in planes
        ]
    }


@router.post("", status_code=201)
async def crear_plan(
    datos: PlanIn,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    plan = Plan(
        creador_id=usuario.id,
        titulo=datos.titulo,
        descripcion=datos.descripcion,
        lugar=datos.lugar,
        lat=datos.lat,
        lng=datos.lng,
        starts_at=datos.starts_at,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)

    # El creador arranca en "alistándome" por defecto.
    estado = EstadoPlanRegistro(plan_id=plan.id, usuario_id=usuario.id, estado=EstadoPlan.ALISTANDO)
    db.add(estado)
    db.commit()
    db.refresh(plan)

    await manager.transmitir({"type": "plan.nuevo", "plan": plan_dict(plan)})
    try:
        await notificar_a_todos(
            db,
            titulo=f"Nuevo plan: {plan.titulo} 📅",
            cuerpo=plan.lugar or "Toca para ver",
            data={"type": "plan.nuevo", "plan_id": str(plan.id)},
            excluir=usuario.id,
        )
    except Exception:
        pass
    return plan_dict(plan)


@router.put("/{plan_id}/estado")
async def cambiar_estado(
    plan_id: int,
    datos: PlanEstadoIn,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_usuario_actual),
):
    plan = db.get(Plan, plan_id)
    if plan is None:
        raise HTTPException(404, "plan no existe")
    if plan.starts_at < datetime.utcnow() - timedelta(hours=6):
        raise HTTPException(410, "ese plan ya pasó")

    nuevo = EstadoPlan(datos.estado.value)
    registro = (
        db.query(EstadoPlanRegistro)
        .filter(EstadoPlanRegistro.plan_id == plan_id, EstadoPlanRegistro.usuario_id == usuario.id)
        .first()
    )
    if registro is None:
        registro = EstadoPlanRegistro(plan_id=plan_id, usuario_id=usuario.id, estado=nuevo)
        db.add(registro)
    else:
        registro.estado = nuevo
    db.commit()

    payload = {
        "type": "plan.estado",
        "plan_id": plan_id,
        "usuario": {
            "id": usuario.id,
            "display_name": usuario.display_name,
            "emoji": usuario.emoji,
            "estado": nuevo.value,
        },
    }

    # El momento clave: "En camino" → alerta push en tiempo real a los
    # otros (el cliente Flutter dispara la notificación local al recibir
    # este evento; a los otros 5, no a quien tocó el botón).
    if nuevo == EstadoPlan.EN_CAMINO:
        await manager.transmitir({**payload, "type": "plan.impulso_push"}, ignorar=usuario.id)
        try:
            await notificar_a_todos(
                db,
                titulo=f"{usuario.display_name} va en camino 🚗",
                cuerpo=plan.titulo,
                data={"type": "plan.impulso_push", "plan_id": str(plan_id)},
                excluir=usuario.id,
            )
        except Exception:
            pass
    await manager.transmitir(payload)
    # Notificación general para cualquier cambio de estado (opcional, no spam)
    try:
        if nuevo != EstadoPlan.EN_CAMINO:
            await notificar_a_todos(
                db,
                titulo=f"{usuario.display_name}: {nuevo.value}",
                cuerpo=plan.titulo,
                data={"type": "plan.estado", "plan_id": str(plan_id)},
                excluir=usuario.id,
            )
    except Exception:
        pass
    return payload