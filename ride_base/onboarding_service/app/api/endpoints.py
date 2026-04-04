import logging
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, Form, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.middleware.auth import get_current_user
from app.db.database import get_db
from app.models.profile import UserProfile, RoleEnum
from app.models.vehicle import DriverDetails
from app.services.s3 import upload_file_to_s3
from app.services.rabbitmq import publisher

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
        "role": profile.role.value
    }


@router.patch("/me")
async def update_my_profile(
    full_name: str | None = Form(None),
    phone_number: str | None = Form(None),
    city: str | None = Form(None),
    role: str | None = Form(None),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update profile fields. All fields optional. Role change triggers Authentik group sync."""
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

    role_changed_to_driver = False
    if role is not None:
        try:
            new_role = RoleEnum(role.upper())
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid role. Must be RIDER or DRIVER.")
        if new_role != profile.role:
            if new_role == RoleEnum.DRIVER:
                role_changed_to_driver = True
            profile.role = new_role

    await db.commit()

    if role_changed_to_driver:
        success = await publisher.publish(
            routing_key="onboarding.driver_role_assigned",
            message={
                "event_type": "onboarding.driver_role_assigned",
                "authentik_user_id": auth_id,
                "full_name": profile.full_name,
            },
        )
        if not success:
            logger.error("Failed to enqueue driver role assignment for user %s", auth_id)
            return {
                "message": "Profile updated, but backend sync is delayed.",
                "role": profile.role.value,
                "warning": "sync_delayed",
            }

    return {
        "message": "Profile updated.",
        "full_name": profile.full_name,
        "phone_number": profile.phone_number,
        "city": profile.city,
        "role": profile.role.value,
    }


@router.post("/profile")
async def create_profile(
    full_name: str = Form(...),
    phone_number: str = Form(...),
    city: str = Form(...),
    role: str = Form(...),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Step 1 & 2: Save the user's basic info and their choice to be a Driver/Rider."""
    auth_id = _get_auth_id(current_user)

    # Check if exists
    result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == auth_id))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Profile already exists.")

    try:
        role_enum = RoleEnum(role.upper())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid role. Must be RIDER or DRIVER.")

    new_profile = UserProfile(
        authentik_user_id=auth_id,
        full_name=full_name,
        phone_number=phone_number,
        city=city,
        role=role_enum
    )

    db.add(new_profile)
    await db.commit()

    # If driver, publish to RabbitMQ — consumer handles the slow Authentik API call
    if role_enum == RoleEnum.DRIVER:
        success = await publisher.publish(
            routing_key="onboarding.driver_role_assigned",
            message={
                "event_type": "onboarding.driver_role_assigned",
                "authentik_user_id": auth_id,
                "full_name": full_name,
            },
        )
        if not success:
            logger.error("Failed to enqueue driver role assignment for user %s", auth_id)
            return {"message": "Profile created successfully, but backend sync is delayed.", "role": role_enum.value, "warning": "sync_delayed"}

    return {"message": "Profile created successfully", "role": role_enum.value}


@router.post("/driver_setup")
async def setup_driver(
    car_make: str = Form(...),
    car_model: str = Form(...),
    car_colour: str = Form(...),
    year: int = Form(...),
    license_plate: str = Form(...),
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

    if profile.role != RoleEnum.DRIVER:
        raise HTTPException(status_code=403, detail="Only drivers can access vehicle setup.")

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
        car_make=car_make,
        car_model=car_model,
        car_colour=car_colour,
        year=year,
        license_plate=license_plate,
        national_id=national_id,
        national_id_photo_url=national_id_photo_url,
        driver_license_number=driver_license_number,
        driver_license_photo_url=license_photo_url,
    )

    db.add(details)
    await db.commit()

    return {"message": "Driver setup complete!", "vehicle_id": str(details.id)}


@router.patch("/driver_setup")
async def update_driver(
    car_make: str | None = Form(None),
    car_model: str | None = Form(None),
    car_colour: str | None = Form(None),
    year: int | None = Form(None),
    license_plate: str | None = Form(None),
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
    if car_make is not None:
        details.car_make = car_make
    if car_model is not None:
        details.car_model = car_model
    if car_colour is not None:
        details.car_colour = car_colour
    if year is not None:
        details.year = year
    if license_plate is not None:
        details.license_plate = license_plate
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

    return {"message": "Driver details updated.", "vehicle_id": str(details.id)}


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
