import logging
import httpx
from app.config import settings

logger = logging.getLogger(__name__)

DRIVER_GROUP_NAME = "ridebase_drivers"


async def add_user_to_driver_group(authentik_user_id: str) -> bool:
    """Add a user to the ridebase_drivers group in Authentik.

    Uses the Authentik v3 API:
      1. GET /api/v3/core/groups/?name=ridebase_drivers  → fetch group PK
      2. POST /api/v3/core/groups/{pk}/add_user/         → add user to group
    """
    if not settings.AUTHENTIK_API_TOKEN:
        logger.warning("AUTHENTIK_API_TOKEN not set. Skipping driver group assignment.")
        return False

    headers = {
        "Authorization": f"Bearer {settings.AUTHENTIK_API_TOKEN}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient() as client:
            # Step 1: Look up the ridebase_drivers group PK by name
            groups_resp = await client.get(
                f"{settings.AUTHENTIK_API_URL}/api/v3/core/groups/",
                headers=headers,
                params={"name": DRIVER_GROUP_NAME},
            )
            groups_resp.raise_for_status()
            results = groups_resp.json().get("results", [])

            if not results:
                logger.error("Authentik group '%s' not found", DRIVER_GROUP_NAME)
                return False

            group_pk = results[0]["pk"]

            try:
                user_pk = int(authentik_user_id)
            except ValueError:
                user_pk = authentik_user_id

            # Step 2: Add the user to the group
            add_resp = await client.post(
                f"{settings.AUTHENTIK_API_URL}/api/v3/core/groups/{group_pk}/add_user/",
                headers=headers,
                json={"pk": user_pk},
            )
            add_resp.raise_for_status()

        logger.info("Added user %s to group '%s'", authentik_user_id, DRIVER_GROUP_NAME)
        return True

    except httpx.HTTPStatusError as e:
        logger.error(
            "Authentik API error adding user %s to driver group: %s %s",
            authentik_user_id, e.response.status_code, e.response.text,
        )
        return False
    except Exception as e:
        logger.error("Failed to add user %s to driver group: %s", authentik_user_id, e)
        return False


async def set_email_verified(authentik_user_id: str, verified: bool = True) -> bool:
    """Set the `email_verified` custom attribute on an Authentik user.

    This attribute is exposed in the JWT via a custom scope mapping,
    so the mobile app can check email verification status from the token.
    """
    url = f"{settings.AUTHENTIK_API_URL}/api/v3/core/users/{authentik_user_id}/"
    headers = {
        "Authorization": f"Bearer {settings.AUTHENTIK_API_TOKEN}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            current_attrs = resp.json().get("attributes", {})

            current_attrs["email_verified"] = verified

            patch_resp = await client.patch(
                url,
                headers=headers,
                json={"attributes": current_attrs},
            )
            patch_resp.raise_for_status()

        logger.info(
            "Set email_verified=%s for Authentik user %s",
            verified,
            authentik_user_id,
        )
        return True

    except httpx.HTTPStatusError as e:
        logger.error(
            "Failed to update Authentik user %s: %s %s",
            authentik_user_id,
            e.response.status_code,
            e.response.text,
        )
        return False
    except httpx.HTTPError as e:
        logger.error("Authentik API request failed for user %s: %s", authentik_user_id, e)
        return False
