import uuid
import logging
import aioboto3
from fastapi import UploadFile
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from botocore.config import Config

from app.config import settings

logger = logging.getLogger(__name__)

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type(Exception),
    reraise=True
)
async def upload_file_to_s3(file: UploadFile, directory: str = "licenses", user_id: str | None = None) -> str | None:
    """Uploads a FastApi UploadFile to S3/MinIO and returns the URL.

    Automates bucket creation if it doesn't exist and handles ACL fallbacks.
    Uses exponential backoff retries for robustness.
    """
    session = aioboto3.Session()

    file_extension = file.filename.split(".")[-1] if file.filename else "jpg"
    name_prefix = f"user-{user_id}_" if user_id else ""
    unique_filename = f"{directory}/{name_prefix}{uuid.uuid4().hex[:8]}.{file_extension}"

    try:
        async with session.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT_URL,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION_NAME,
            config=Config(signature_version='s3v4')
        ) as s3_client:

            # 1. Ensure the bucket exists (Fail-safe)
            try:
                await s3_client.head_bucket(Bucket=settings.S3_BUCKET_NAME)
            except Exception:
                logger.info(f"Bucket {settings.S3_BUCKET_NAME} not found. Attempting to create...")
                try:
                    await s3_client.create_bucket(Bucket=settings.S3_BUCKET_NAME)
                    logger.info(f"Successfully created bucket {settings.S3_BUCKET_NAME}")
                except Exception as create_err:
                    logger.error(f"Failed to create bucket: {create_err}")
                    # Continue anyway, put_object might give a better error

            # 2. Upload file
            # Important: Since we might retry, we must seek(0) in case a previous attempt partially read it
            await file.seek(0)
            content = await file.read()

            try:
                # Try with public-read first
                await s3_client.put_object(
                    Bucket=settings.S3_BUCKET_NAME,
                    Key=unique_filename,
                    Body=content,
                    ContentType=file.content_type,
                    ACL="public-read"
                )
            except Exception as acl_err:
                logger.warning(f"Failed to set public-read ACL (common on some providers), retrying without ACL: {acl_err}")
                # Retry without explicit ACL (use bucket defaults)
                await s3_client.put_object(
                    Bucket=settings.S3_BUCKET_NAME,
                    Key=unique_filename,
                    Body=content,
                    ContentType=file.content_type
                )

            # Construct public URL assuming path-style addressing
            url = f"{settings.S3_ENDPOINT_URL}/{settings.S3_BUCKET_NAME}/{unique_filename}"
            logger.info(f"Successfully uploaded {file.filename} to {url}")
            return url

    except Exception as e:
        logger.error(f"Failed to upload file to S3: {e}")
        raise e # Reraise for tenacity
