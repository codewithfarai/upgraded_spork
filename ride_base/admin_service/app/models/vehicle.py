import uuid
import enum
from sqlalchemy import Column, String, Integer, DateTime, func, Enum, ForeignKey, Boolean
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base

class AssignmentStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    REVOKED = "REVOKED"

class Vehicle(Base):
    """
    A Vehicle represents a car in the platform.
    It is owned by a Fleet Owner (or an independent driver).
    """
    __tablename__ = "vehicles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # The Authentik UUID of the fleet owner who registered this vehicle.
    owner_id = Column(String, index=True, nullable=False)

    car_make = Column(String, nullable=False)
    car_model = Column(String, nullable=False)
    car_colour = Column(String, nullable=False)
    year = Column(Integer, nullable=False)
    license_plate = Column(String, nullable=False, unique=True)

    # E.g. registration documents
    registration_document_url = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

class VehicleAssignment(Base):
    """
    A mapping from a Driver to a Vehicle.
    """
    __tablename__ = "vehicle_assignments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    # The Authentik UUID of the driver who is assigned to drive this vehicle.
    driver_id = Column(String, index=True, nullable=False)

    status = Column(Enum(AssignmentStatus), default=AssignmentStatus.ACTIVE, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class VehicleInvite(Base):
    """
    A temporary token used to invite a driver to a vehicle.
    """
    __tablename__ = "vehicle_invites"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    token = Column(String, unique=True, index=True, nullable=False)

    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    owner_id = Column(String, nullable=False)

    is_used = Column(Boolean, default=False, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
