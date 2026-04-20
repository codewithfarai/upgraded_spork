ENV ?= dev
ARGS ?= -v
EXTRA_VARS ?=

# Auto-detect service versions from pyproject.toml
PAYMENT_VERSION    := $(shell grep -m 1 '^version = ' ../ride_base/payment_service/pyproject.toml | cut -d '"' -f2)
ONBOARDING_VERSION := $(shell grep -m 1 '^version = ' ../ride_base/onboarding_service/pyproject.toml | cut -d '"' -f2)
ADMIN_VERSION      := $(shell grep -m 1 '^version = ' ../ride_base/admin_service/pyproject.toml | cut -d '"' -f2)

# Load secrets from .env if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: swarm swarm_check cleanup generate_secrets

generate_secrets:
	@chmod +x scripts/generate_authentik_secrets.sh
	@bash scripts/generate_authentik_secrets.sh

swarm:
	@echo "🐝 Bootstrapping Docker Swarm ($(ENV))..."
	@echo "📦 payment_service=$(PAYMENT_VERSION)  onboarding_service=$(ONBOARDING_VERSION)  admin_service=$(ADMIN_VERSION)"
	@echo "🔑 Refreshing SSH host keys for $(ENV)..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml $(ARGS) \
		-e "payment_service_version=$(PAYMENT_VERSION)" \
		-e "onboarding_service_version=$(ONBOARDING_VERSION)" \
		-e "admin_service_version=$(ADMIN_VERSION)" \
		$(if $(EXTRA_VARS),-e "$(EXTRA_VARS)")

swarm_check:
	@echo "🔍 Dry-run Docker Swarm bootstrap ($(ENV))..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml --check --diff

cleanup:
	@echo "🔥 KILLING EVERYTHING in the Swarm Cluster ($(ENV))..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/cleanup.yml
