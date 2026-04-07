import uuid
import enum
from sqlalchemy import Boolean, Column, String, Enum, DateTime, func
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base

class RoleIntentEnum(str, enum.Enum):
    RIDER = "RIDER"
    DRIVER = "DRIVER"

class UserProfile(Base):
    __tablename__ = "user_profiles"

    # We use Authentik's UUID (or numeric ID if using PKs) as the primary ID here.
    # For safety, let's treat the Authentik UUID/PK as string to be flexible.
    authentik_user_id = Column(String, primary_key=True, index=True)

    full_name = Column(String, nullable=False)
    phone_number = Column(String, nullable=False)
    city = Column(String, nullable=False)
    email = Column(String, nullable=False)
    email_verified = Column(Boolean, default=False, nullable=False)

    # Multi-role support
    # is_rider is True for everyone by default (Drivers can also book rides).
    # is_driver only becomes True after Step 3 (Vehicle Setup) is confirmed.
    is_rider = Column(Boolean, default=True, nullable=False)
    is_driver = Column(Boolean, default=False, nullable=False)

    # Tracks what the user signed up as, so the app knows which flow to show.
    role_intent = Column(Enum(RoleIntentEnum), default=RoleIntentEnum.RIDER, nullable=False)

    location_enabled = Column(Boolean, default=False, nullable=False)
    details_confirmed = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
