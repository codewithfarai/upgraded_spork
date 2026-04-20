import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from app.middleware.auth import get_current_user
from app.db.database import get_db
from app.models.vehicle import Vehicle, VehicleAssignment, AssignmentStatus
from app.services.rabbitmq import publisher

logger = logging.getLogger(__name__)

router = APIRouter()

def _get_auth_id(current_user: dict) -> str:
    auth_id = current_user.get("authentik_pk") or current_user.get("sub")
    if not auth_id:
        raise HTTPException(status_code=401, detail="Invalid token: missing user identifier")
    return str(auth_id)


class VehicleCreate(BaseModel):
    car_make: str
    car_model: str
    car_colour: str
    year: int
    license_plate: str
    registration_document_url: Optional[str] = None


class VehicleAssignmentCreate(BaseModel):
    driver_id: str


@router.post("/vehicles", status_code=status.HTTP_201_CREATED)
async def create_vehicle(
    payload: VehicleCreate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Register a new vehicle under the current user's fleet."""
    owner_id = _get_auth_id(current_user)

    # Check for duplicate license plate
    result = await db.execute(select(Vehicle).where(Vehicle.license_plate == payload.license_plate))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Vehicle with this license plate already exists.")

    new_vehicle = Vehicle(
        owner_id=owner_id,
        car_make=payload.car_make,
        car_model=payload.car_model,
        car_colour=payload.car_colour,
        year=payload.year,
        license_plate=payload.license_plate,
        registration_document_url=payload.registration_document_url
    )

    db.add(new_vehicle)
    await db.commit()
    await db.refresh(new_vehicle)

    await publisher.publish(
        routing_key="fleet.vehicle_registered",
        message={
            "event_type": "fleet.vehicle_registered",
            "vehicle_id": str(new_vehicle.id),
            "owner_id": owner_id,
            "license_plate": new_vehicle.license_plate
        }
    )

    return {"message": "Vehicle registered successfully", "vehicle_id": str(new_vehicle.id)}


@router.get("/vehicles")
async def get_my_vehicles(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all vehicles owned by the current user."""
    owner_id = _get_auth_id(current_user)

    result = await db.execute(select(Vehicle).where(Vehicle.owner_id == owner_id))
    vehicles = result.scalars().all()

    return [{"id": str(v.id), "make": v.car_make, "model": v.car_model, "plate": v.license_plate} for v in vehicles]


@router.post("/vehicles/{vehicle_id}/assign")
async def assign_vehicle(
    vehicle_id: uuid.UUID,
    payload: VehicleAssignmentCreate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Assign a vehicle to a driver."""
    owner_id = _get_auth_id(current_user)

    # 1. Ensure the user owns this vehicle
    v_result = await db.execute(select(Vehicle).where(Vehicle.id == vehicle_id, Vehicle.owner_id == owner_id))
    vehicle = v_result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=403, detail="Not authorized to manage this vehicle.")

    # 2. Check if the vehicle is currently assigned to someone else
    a_result = await db.execute(
        select(VehicleAssignment).where(
            VehicleAssignment.vehicle_id == vehicle_id,
            VehicleAssignment.status == AssignmentStatus.ACTIVE
        )
    )
    assignment = a_result.scalar_one_or_none()
    if assignment:
        if assignment.driver_id == payload.driver_id:
            return {"message": "Driver is already assigned to this vehicle."}
        else:
            raise HTTPException(status_code=400, detail="Vehicle is currently mapped to another ACTIVE driver. Revoke it first.")

    new_assignment = VehicleAssignment(
        vehicle_id=vehicle_id,
        driver_id=payload.driver_id,
        status=AssignmentStatus.ACTIVE
    )
    db.add(new_assignment)
    await db.commit()

    await publisher.publish(
        routing_key="fleet.driver_assigned",
        message={
            "event_type": "fleet.driver_assigned",
            "vehicle_id": str(vehicle_id),
            "driver_id": payload.driver_id
        }
    )

    return {"message": "Vehicle assigned successfully."}

@router.delete("/vehicles/{vehicle_id}/assign", status_code=status.HTTP_204_NO_CONTENT)
async def unassign_vehicle(
    vehicle_id: uuid.UUID,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Unassign the vehicle from its active driver."""
    owner_id = _get_auth_id(current_user)

    # 1. Ensure the user owns this vehicle
    v_result = await db.execute(select(Vehicle).where(Vehicle.id == vehicle_id, Vehicle.owner_id == owner_id))
    vehicle = v_result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=403, detail="Not authorized to manage this vehicle.")

    a_result = await db.execute(
        select(VehicleAssignment).where(
            VehicleAssignment.vehicle_id == vehicle_id,
            VehicleAssignment.status == AssignmentStatus.ACTIVE
        )
    )
    assignment = a_result.scalar_one_or_none()

    if assignment:
        assignment.status = AssignmentStatus.REVOKED
        await db.commit()

        await publisher.publish(
            routing_key="fleet.driver_unassigned",
            message={
                "event_type": "fleet.driver_unassigned",
                "vehicle_id": str(vehicle_id),
                "driver_id": assignment.driver_id
            }
        )


@router.post("/vehicles/self_assign", status_code=status.HTTP_201_CREATED)
async def self_assign_vehicle(
    payload: VehicleCreate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Aggregator: Registers a new vehicle AND immediately assigns it to the current user."""
    auth_id = _get_auth_id(current_user)

    # 1. Check for duplicate license plate
    result = await db.execute(select(Vehicle).where(Vehicle.license_plate == payload.license_plate))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Vehicle with this license plate already exists.")

    # 2. Create the Vehicle
    new_vehicle = Vehicle(
        owner_id=auth_id,
        car_make=payload.car_make,
        car_model=payload.car_model,
        car_colour=payload.car_colour,
        year=payload.year,
        license_plate=payload.license_plate,
        registration_document_url=payload.registration_document_url
    )
    db.add(new_vehicle)
    await db.commit()
    await db.refresh(new_vehicle)

    # 3. Create the Assignment (Self-Assign)
    new_assignment = VehicleAssignment(
        vehicle_id=new_vehicle.id,
        driver_id=auth_id,
        status=AssignmentStatus.ACTIVE
    )
    db.add(new_assignment)
    await db.commit()

    # Publish both events since this is an aggregator
    await publisher.publish(
        routing_key="fleet.vehicle_registered",
        message={
            "event_type": "fleet.vehicle_registered",
            "vehicle_id": str(new_vehicle.id),
            "owner_id": auth_id,
            "license_plate": new_vehicle.license_plate
        }
    )

    await publisher.publish(
        routing_key="fleet.driver_assigned",
        message={
            "event_type": "fleet.driver_assigned",
            "vehicle_id": str(new_vehicle.id),
            "driver_id": auth_id
        }
    )

    return {
        "message": "Vehicle registered and assigned to you successfully",
        "vehicle_id": str(new_vehicle.id)
    }


import secrets
from datetime import datetime, timedelta, timezone
from app.models.vehicle import VehicleInvite

class InviteAcceptRequest(BaseModel):
    token: str

@router.post("/vehicles/{vehicle_id}/invite")
async def generate_invite(
    vehicle_id: uuid.UUID,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Generate a shareable invite token for a hired driver."""
    owner_id = _get_auth_id(current_user)

    v_result = await db.execute(select(Vehicle).where(Vehicle.id == vehicle_id, Vehicle.owner_id == owner_id))
    vehicle = v_result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=403, detail="Not authorized to manage this vehicle.")

    # Generate a cryptographically secure URL-safe token
    token = secrets.token_urlsafe(32)

    # Expires in 7 days
    expires_at = datetime.now(timezone.utc) + timedelta(days=7)

    invite = VehicleInvite(
        token=token,
        vehicle_id=vehicle_id,
        owner_id=owner_id,
        expires_at=expires_at
    )
    db.add(invite)
    await db.commit()

    await publisher.publish(
        routing_key="fleet.invite_generated",
        message={
            "event_type": "fleet.invite_generated",
            "vehicle_id": str(vehicle_id),
            "owner_id": owner_id,
            "invite_token": token
        }
    )

    return {
        "invite_token": token,
        "expires_at": expires_at.isoformat()
    }


@router.post("/vehicles/accept_invite")
async def accept_invite(
    payload: InviteAcceptRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Accept an invite token and self-assign to the vehicle."""
    driver_id = _get_auth_id(current_user)

    # 1. Find and validate the invite
    i_result = await db.execute(select(VehicleInvite).where(VehicleInvite.token == payload.token))
    invite = i_result.scalar_one_or_none()

    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite token.")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite token has already been used.")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Invite token has expired.")

    # 2. Check if vehicle is already assigned
    a_result = await db.execute(
        select(VehicleAssignment).where(
            VehicleAssignment.vehicle_id == invite.vehicle_id,
            VehicleAssignment.status == AssignmentStatus.ACTIVE
        )
    )
    existing_assignment = a_result.scalar_one_or_none()

    if existing_assignment:
        if existing_assignment.driver_id == driver_id:
            return {"message": "You are already assigned to this vehicle."}
        else:
            raise HTTPException(status_code=400, detail="Vehicle is currently mapped to another ACTIVE driver. They must be unassigned first.")

    # 3. Create the assignment
    new_assignment = VehicleAssignment(
        vehicle_id=invite.vehicle_id,
        driver_id=driver_id,
        status=AssignmentStatus.ACTIVE
    )
    db.add(new_assignment)

    # 4. Burn the token
    invite.is_used = True
    await db.commit()

    await publisher.publish(
        routing_key="fleet.invite_accepted",
        message={
            "event_type": "fleet.invite_accepted",
            "vehicle_id": str(invite.vehicle_id),
            "driver_id": driver_id,
            "invite_token": payload.token
        }
    )

    await publisher.publish(
        routing_key="fleet.driver_assigned",
        message={
            "event_type": "fleet.driver_assigned",
            "vehicle_id": str(invite.vehicle_id),
            "driver_id": driver_id
        }
    )

    return {"message": "Invite accepted! You are now assigned to the vehicle."}
