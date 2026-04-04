# ============================================================================
# Stage 1: Build — install dependencies via Poetry
# ============================================================================
FROM python:3.12-slim AS builder

WORKDIR /build

# System deps for building Python packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libffi-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Poetry (pinned version)
ENV POETRY_VERSION=1.8.5
RUN pip install --no-cache-dir "poetry==${POETRY_VERSION}"

# Copy dependency manifests first (Docker layer caching)
COPY pyproject.toml poetry.lock ./

# Export to requirements.txt and install into a virtual env
RUN poetry export --without dev -f requirements.txt -o requirements.txt && \
    python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ============================================================================
# Stage 2: Runtime — minimal image
# ============================================================================
FROM python:3.12-slim AS runtime

# Run as non-root user (matches cluster pattern: UID 1000)
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -s /bin/false appuser

WORKDIR /app

# Copy venv from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application code
COPY app/ ./app/

# Copy Alembic config for migrations
COPY alembic.ini ./
COPY migrations/ ./migrations/

# Own everything by appuser
RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]

ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
