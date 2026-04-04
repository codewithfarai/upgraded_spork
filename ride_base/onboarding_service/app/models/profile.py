import uuid
import enum
from sqlalchemy import Column, String, Enum
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base

class RoleEnum(str, enum.Enum):
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

    role = Column(Enum(RoleEnum), default=RoleEnum.RIDER, nullable=False)
