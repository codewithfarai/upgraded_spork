# Payment Service Makefile

SERVICE_NAME := payment_service
IMAGE_NAME := fwande/ridebase_payment_service
# Extract version from pyproject.toml (tool.commitizen section)
VERSION := $(shell grep -m 1 "version = " pyproject.toml | cut -d '"' -f 2)

.PHONY: build push help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build    Build and push multi-platform image: $(IMAGE_NAME):$(VERSION)"
	@echo "  push     Alias for build (build and push are combined)"

build push:
	@echo "🔨 Building & pushing $(IMAGE_NAME):$(VERSION) (linux/amd64 + linux/arm64)..."
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):latest \
		.
