import logging
from typing import Optional

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import settings

logger = logging.getLogger(__name__)

security = HTTPBearer()

_jwks_cache: dict | None = None


async def _get_jwks() -> dict:
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache
    async with httpx.AsyncClient() as client:
        response = await client.get(settings.AUTHENTIK_JWKS_URL)
        response.raise_for_status()
        _jwks_cache = response.json()
    return _jwks_cache


def _clear_jwks_cache() -> None:
    global _jwks_cache
    _jwks_cache = None


def _decode_token(token: str, jwks: dict) -> dict:
    unverified_header = jwt.get_unverified_header(token)
    kid = unverified_header.get("kid")
    rsa_key: dict = {}
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            rsa_key = key
            break
    if not rsa_key:
        return {}
    return jwt.decode(
        token,
        rsa_key,
        algorithms=["RS256"],
        audience=settings.AUTHENTIK_AUDIENCE,
        issuer=settings.AUTHENTIK_ISSUER,
    )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """Validate JWT from Authentik and return the decoded token payload."""
    token = credentials.credentials
    try:
        jwks = await _get_jwks()
        try:
            payload = _decode_token(token, jwks)
        except JWTError:
            # Key may have rotated; retry with fresh JWKS
            _clear_jwks_cache()
            jwks = await _get_jwks()
            payload = _decode_token(token, jwks)

        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unable to find matching signing key",
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


async def authenticate_websocket(token: str) -> Optional[dict]:
    """Validate a token for WebSocket connections. Returns payload or None."""
    try:
        jwks = await _get_jwks()
        try:
            payload = _decode_token(token, jwks)
        except JWTError:
            _clear_jwks_cache()
            jwks = await _get_jwks()
            payload = _decode_token(token, jwks)
        return payload if payload else None
    except (JWTError, httpx.HTTPError):
        return None
