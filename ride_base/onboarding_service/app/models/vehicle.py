import uuid
from sqlalchemy import Column, String, Integer, ForeignKey, DateTime, func
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base

class DriverDetails(Base):
    __tablename__ = "driver_details"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    profile_id = Column(String, ForeignKey("user_profiles.authentik_user_id", ondelete="CASCADE"), unique=True, nullable=False)

    national_id = Column(String, nullable=False, unique=True)
    national_id_photo_url = Column(String, nullable=False)
    driver_license_number = Column(String, nullable=False, unique=True)
    driver_license_photo_url = Column(String, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
