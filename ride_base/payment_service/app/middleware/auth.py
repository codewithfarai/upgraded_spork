import logging

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import settings

logger = logging.getLogger(__name__)

security = HTTPBearer()

_jwks_cache: dict | None = None


async def _get_jwks() -> dict:
    """Fetch and cache JWKS from Authentik."""
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache
    async with httpx.AsyncClient() as client:
        response = await client.get(settings.AUTHENTIK_JWKS_URL)
        response.raise_for_status()
        _jwks_cache = response.json()
    return _jwks_cache


def clear_jwks_cache() -> None:
    """Clear JWKS cache — useful for key rotation."""
    global _jwks_cache
    _jwks_cache = None


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """Validate JWT from Authentik and return the decoded token payload.

    Expected token claims:
      - sub: user ID
      - email: user email
      - preferred_username: display name
    """
    token = credentials.credentials
    try:
        jwks = await _get_jwks()
        # Decode the header to find the key id
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        # Find the matching key
        rsa_key: dict = {}
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                rsa_key = key
                break

        if not rsa_key:
            clear_jwks_cache()
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unable to find matching signing key",
            )

        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],
            audience=settings.AUTHENTIK_AUDIENCE,
            issuer=settings.AUTHENTIK_ISSUER,
        )
        return payload

    except JWTError as e:
        logger.warning("JWT validation failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    except httpx.HTTPError as e:
        logger.error("Failed to fetch JWKS: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unavailable",
        )
