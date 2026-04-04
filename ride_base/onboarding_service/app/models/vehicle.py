import uuid
from sqlalchemy import Column, String, Integer, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base

class DriverDetails(Base):
    __tablename__ = "driver_details"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    profile_id = Column(String, ForeignKey("user_profiles.authentik_user_id", ondelete="CASCADE"), unique=True, nullable=False)

    car_make = Column(String, nullable=False)
    car_model = Column(String, nullable=False)
    year = Column(Integer, nullable=False)
    license_plate = Column(String, nullable=False, unique=True)
    national_id = Column(String, nullable=False, unique=True)
    driver_license_number = Column(String, nullable=False, unique=True)
    driver_license_photo_url = Column(String, nullable=False)

    is_available_now = Column(Boolean, default=False, nullable=False)
