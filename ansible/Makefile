ENV ?= dev

# Load secrets from .env if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: swarm swarm_check generate_secrets

generate_secrets:
	@chmod +x scripts/generate_authentik_secrets.sh
	@bash scripts/generate_authentik_secrets.sh

swarm:
	@echo "🐝 Bootstrapping Docker Swarm ($(ENV))..."
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml

swarm_check:
	@echo "🔍 Dry-run Docker Swarm bootstrap ($(ENV))..."
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml --check --diff
