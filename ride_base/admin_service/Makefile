# Admin / Fleet Service Makefile

SERVICE_NAME := admin_service
IMAGE_NAME := fwande/ridebase_admin_service
# Extract version from pyproject.toml (tool.commitizen section)
VERSION := $(shell grep -m 1 "version = " pyproject.toml | cut -d '"' -f 2)

.PHONY: build push migrate help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build          Build and push multi-platform image: $(IMAGE_NAME):$(VERSION)"
	@echo "  push           Alias for build (build and push are combined)"
	@echo "  migrate m=msg  Generate a new Alembic migration (autogenerate)"

build push:
	@echo "🔨 Building & pushing $(IMAGE_NAME):$(VERSION) (linux/amd64 + linux/arm64)..."
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):latest \
		.

migrate:
	@test -n "$(m)" || (echo "❌ Usage: make migrate m='your message'"; exit 1)
	@echo "🐘 Starting temporary Postgres..."
	@docker run -d --name alembic_tmp_pg \
		-e POSTGRES_PASSWORD=postgres \
		-e POSTGRES_DB=admin \
		-p 5433:5432 postgres:16-alpine
	@until docker exec alembic_tmp_pg pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	@echo "⬆️  Applying existing migrations to temp DB..."
	@DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5433/admin \
		poetry run alembic upgrade head
	@echo "🔍 Generating new migration: $(m)"
	@DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5433/admin \
		poetry run alembic revision --autogenerate -m "$(m)"
	@docker rm -f alembic_tmp_pg > /dev/null
	@echo "✅ Done. Review the new file in migrations/versions/ before committing."
