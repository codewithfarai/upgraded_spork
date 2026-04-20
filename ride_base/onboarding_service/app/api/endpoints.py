import logging
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, Form, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.middleware.auth import get_current_user
from app.db.database import get_db
from app.models.profile import UserProfile, RoleIntentEnum
from app.models.vehicle import DriverDetails
from app.services.s3 import upload_file_to_s3
from app.services.rabbitmq import publisher
from app.services.otp import generate_otp, verify_otp

logger = logging.getLogger(__name__)

router = APIRouter()

def _get_auth_id(current_user: dict) -> str:
    auth_id = current_user.get("authentik_pk") or current_user.get("sub")
    if not auth_id:
        raise HTTPException(status_code=401, detail="Invalid token: missing user identifier")
    return str(auth_id)

@router.get("/me")
async def get_my_profile(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Check if the user has an onboarding profile."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(
        select(UserProfile).where(UserProfile.authentik_user_id == auth_id)
    )
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found, please onboard.")

    return {
        "full_name": profile.full_name,
        "phone_number": profile.phone_number,
        "city": profile.city,
        "email": profile.email,
        "is_rider": profile.is_rider,
        "is_driver": profile.is_driver,
        "role_intent": profile.role_intent.value
    }


@router.patch("/me")
async def update_my_profile(
    full_name: str | None = Form(None),
    phone_number: str | None = Form(None),
    city: str | None = Form(None),
    role_intent: str | None = Form(None),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update profile fields. role_intent can be updated but doesn't grant permissions."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found, please onboard.")

    if full_name is not None:
        profile.full_name = full_name
    if phone_number is not None:
        profile.phone_number = phone_number
    if city is not None:
        profile.city = city
    if role_intent is not None:
        try:
            profile.role_intent = RoleIntentEnum(role_intent.upper())
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid role_intent. Must be RIDER or DRIVER.")

    # Always ensure these are confirmed from the app flow
    profile.location_enabled = True
    profile.details_confirmed = True

    await db.commit()

    return {
        "message": "Profile updated.",
        "full_name": profile.full_name,
        "phone_number": profile.phone_number,
        "city": profile.city,
        "is_rider": profile.is_rider,
        "is_driver": profile.is_driver,
        "role_intent": profile.role_intent.value,
    }


@router.post("/profile")
async def create_profile(
    full_name: str = Form(...),
    phone_number: str = Form(...),
    city: str = Form(...),
    role: str = Form(...),
    email: str = Form(...),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Step 1 & 2: Save metadata and intent. Everyone is a Rider by default."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Profile already exists.")

    try:
        intent = RoleIntentEnum(role.upper())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid role. Must be RIDER or DRIVER.")

    new_profile = UserProfile(
        authentik_user_id=auth_id,
        full_name=full_name,
        phone_number=phone_number,
        city=city,
        email=email,
        role_intent=intent,
        is_rider=True,          # Everyone is a Rider
        is_driver=False,         # Not a Driver until confirmed (Step 3)
        location_enabled=True,
        details_confirmed=True
    )

    db.add(new_profile)
    await db.commit()

    otp_sent = False
    try:
        otp_code = await generate_otp(auth_id)
        otp_sent = await publisher.publish(
            routing_key="onboarding.send_otp_email",
            message={"email": email, "code": otp_code},
        )
    except Exception:
        logger.exception("Failed to generate/send OTP for user %s", auth_id)

    return {
        "message": "Profile created successfully",
        "is_rider": new_profile.is_rider,
        "is_driver": new_profile.is_driver,
        "role_intent": intent.value,
        "email_otp_sent": otp_sent
    }


class VerifyOtpRequest(BaseModel):
    code: str


@router.post("/verify_email")
async def verify_email(
    body: VerifyOtpRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Verify the 6-digit OTP code sent to the user's email."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found. Complete onboarding first.")

    if profile.email_verified:
        return {"message": "Email already verified."}

    if not await verify_otp(auth_id, body.code):
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    profile.email_verified = True
    await db.commit()

    # Publish to RabbitMQ so the consumer syncs email_verified to Authentik JWT attribute
    await publisher.publish(
        routing_key="onboarding.email_verified",
        message={
            "event_type": "onboarding.email_verified",
            "authentik_user_id": auth_id,
        },
    )

    return {"message": "Email verified successfully."}


@router.post("/resend_otp")
async def resend_otp(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Resend the 6-digit OTP code to the user's email."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found.")

    if profile.email_verified:
        return {"message": "Email already verified."}

    otp_code = await generate_otp(auth_id)
    await publisher.publish(
        routing_key="onboarding.send_otp_email",
        message={"email": profile.email, "code": otp_code},
    )

    return {"message": "Verification code resent."}


@router.post("/driver_setup")
async def setup_driver(
    national_id: str = Form(...),
    driver_license_number: str = Form(...),
    license_photo: UploadFile = File(...),
    national_id_photo: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Step 3: Driver onboarding flow (Only accessible if role == DRIVER)."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Complete your basic profile first.")

    # Prevent duplicate driver setup
    driver_result = await db.execute(select(DriverDetails).where(DriverDetails.profile_id == auth_id))
    if driver_result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Driver details already submitted.")

    # 1. Validate file types
    allowed = ["image/jpeg", "image/png", "application/pdf"]
    if license_photo.content_type not in allowed:
        raise HTTPException(status_code=400, detail="Invalid file type for license_photo. Only JPEG, PNG, or PDF are allowed.")
    if national_id_photo.content_type not in allowed:
        raise HTTPException(status_code=400, detail="Invalid file type for national_id_photo. Only JPEG, PNG, or PDF are allowed.")

    # 2. Upload photos to S3/MinIO
    license_photo_url = await upload_file_to_s3(license_photo, user_id=auth_id)
    if not license_photo_url:
        raise HTTPException(status_code=500, detail="Failed to upload license photo.")

    national_id_photo_url = await upload_file_to_s3(national_id_photo, user_id=auth_id)
    if not national_id_photo_url:
        raise HTTPException(status_code=500, detail="Failed to upload national ID photo.")

    # 3. Save Driver Details
    details = DriverDetails(
        profile_id=auth_id,
        national_id=national_id,
        national_id_photo_url=national_id_photo_url,
        driver_license_number=driver_license_number,
        driver_license_photo_url=license_photo_url,
    )

    db.add(details)

    # GRANT DRIVER STATUS NOW
    profile.is_driver = True

    await db.commit()

    # SYNC TO AUTHENTIK NOW
    await publisher.publish(
        routing_key="onboarding.driver_role_assigned",
        message={
            "event_type": "onboarding.driver_role_assigned",
            "authentik_user_id": auth_id,
            "full_name": profile.full_name,
        },
    )

    return {
        "message": "Driver setup complete! You are now an authorized Driver.",
        "vehicle_id": str(details.id)
    }


@router.patch("/driver_setup")
async def update_driver(
    national_id: str | None = Form(None),
    driver_license_number: str | None = Form(None),
    license_photo: UploadFile | None = File(None),
    national_id_photo: UploadFile | None = File(None),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update driver details. All fields are optional — only provided fields are changed."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(DriverDetails).where(DriverDetails.profile_id == auth_id))
    details = result.scalar_one_or_none()

    if not details:
        raise HTTPException(status_code=404, detail="Driver details not found. Complete driver setup first.")

    # Update scalar fields if provided
    if national_id is not None:
        details.national_id = national_id
    if driver_license_number is not None:
        details.driver_license_number = driver_license_number

    # Re-upload photos only if new files were provided
    allowed = ["image/jpeg", "image/png", "application/pdf"]

    if license_photo is not None:
        if license_photo.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Invalid file type for license_photo. Only JPEG, PNG, or PDF are allowed.")
        new_url = await upload_file_to_s3(license_photo, user_id=auth_id)
        if not new_url:
            raise HTTPException(status_code=500, detail="Failed to upload license photo.")
        details.driver_license_photo_url = new_url

    if national_id_photo is not None:
        if national_id_photo.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Invalid file type for national_id_photo. Only JPEG, PNG, or PDF are allowed.")
        new_url = await upload_file_to_s3(national_id_photo, user_id=auth_id)
        if not new_url:
            raise HTTPException(status_code=500, detail="Failed to upload national ID photo.")
        details.national_id_photo_url = new_url

    await db.commit()

    return {
        "message": "Driver details updated.",
        "vehicle_id": str(details.id)
    }


@router.delete("/driver_setup", status_code=status.HTTP_204_NO_CONTENT)
async def delete_driver_setup(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete driver vehicle record only. Profile is preserved and can re-submit driver_setup."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(DriverDetails).where(DriverDetails.profile_id == auth_id))
    details = result.scalar_one_or_none()

    if not details:
        raise HTTPException(status_code=404, detail="No driver details found.")

    await db.delete(details)
    await db.commit()


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_profile(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete profile and all associated data (driver details cascade via FK)."""
    auth_id = _get_auth_id(current_user)

    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found.")

    await db.delete(profile)
    await db.commit()
