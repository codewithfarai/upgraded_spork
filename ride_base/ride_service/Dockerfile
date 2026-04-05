# ============================================================================
# Stage 1: Build — install dependencies via Poetry
# ============================================================================
FROM python:3.12-slim AS builder

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libffi-dev && \
    rm -rf /var/lib/apt/lists/*

ENV POETRY_VERSION=1.8.5
RUN pip install --no-cache-dir "poetry==${POETRY_VERSION}"

COPY pyproject.toml poetry.lock ./

RUN poetry export --without dev -f requirements.txt -o requirements.txt && \
    python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ============================================================================
# Stage 2: Runtime — minimal image
# ============================================================================
FROM python:3.12-slim AS runtime

RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -s /bin/false appuser

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY app/ ./app/
COPY alembic.ini ./
COPY migrations/ ./migrations/

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]

# Single worker: WebSocket connection state is in-memory.
# For multi-worker horizontal scaling, replace the in-memory ConnectionManager
# with a Redis pub/sub backed broadcaster.
ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
