# Onboarding Service Makefile

SERVICE_NAME := onboarding_service
IMAGE_NAME := fwande/ridebase_onboarding_service
# Extract version from pyproject.toml (tool.commitizen section)
VERSION := $(shell grep -m 1 "version = " pyproject.toml | cut -d '"' -f 2)

.PHONY: build push help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build    Build the docker image: $(IMAGE_NAME):$(VERSION)"
	@echo "  push     Push the docker image to registry"

build:
	@echo "🔨 Building $(IMAGE_NAME):$(VERSION)..."
	docker build -t $(IMAGE_NAME):$(VERSION) -t $(IMAGE_NAME):latest .

push:
	@echo "🚀 Pushing $(IMAGE_NAME):$(VERSION)..."
	docker push $(IMAGE_NAME):$(VERSION)
	docker push $(IMAGE_NAME):latest
