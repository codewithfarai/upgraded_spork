"""Authentik user attribute sync.

Sets `is_subscribed: true/false` on the driver's user profile in Authentik.
This attribute is then exposed in the JWT via a custom scope mapping,
so the mobile app and other services can check subscription status directly
from the token without calling this service.
"""

import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


async def set_subscription_status(authentik_user_id: str, is_subscribed: bool) -> bool:
    """Update the `is_subscribed` custom attribute on an Authentik user.

    Uses PATCH /api/v3/core/users/{id}/ to set attributes.is_subscribed.

    Args:
        authentik_user_id: The Authentik user's numeric PK (from `sub` claim).
        is_subscribed: Whether the driver has an active subscription.

    Returns:
        True if the update succeeded, False otherwise.
    """
    url = f"{settings.AUTHENTIK_API_URL}/api/v3/core/users/{authentik_user_id}/"
    headers = {
        "Authorization": f"Bearer {settings.AUTHENTIK_API_TOKEN}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient() as client:
            # First GET current attributes so we don't overwrite others
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            current_attrs = resp.json().get("attributes", {})

            # Merge in our attribute
            current_attrs["is_subscribed"] = is_subscribed

            # PATCH the user
            patch_resp = await client.patch(
                url,
                headers=headers,
                json={"attributes": current_attrs},
            )
            patch_resp.raise_for_status()

        logger.info(
            "Set is_subscribed=%s for Authentik user %s",
            is_subscribed,
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


async def get_authentik_user_id_from_customer(customer_id: str) -> str | None:
    """Look up the Authentik numeric PK from a Stripe customer's metadata.

    Reads `authentik_pk` from the Stripe customer metadata (stored at
    customer creation during checkout). This is the reliable numeric PK
    needed for Authentik API calls.
    """
    import stripe
    try:
        customer = stripe.Customer.retrieve(customer_id)
        metadata = getattr(customer, "metadata", None)
        if metadata is None:
            return None
        # Prefer authentik_pk (numeric PK), set during checkout
        pk = getattr(metadata, "authentik_pk", None)
        if pk:
            return str(pk)
        logger.warning("Stripe customer %s has no authentik_pk in metadata", customer_id)
        return None
    except Exception as e:
        logger.error("Failed to retrieve Stripe customer %s: %s", customer_id, e)
        return None
