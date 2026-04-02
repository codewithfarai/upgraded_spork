ENV ?= dev
ARGS ?= -v

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
	@echo "🔑 Refreshing SSH host keys for $(ENV)..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml $(ARGS)

swarm_check:
	@echo "🔍 Dry-run Docker Swarm bootstrap ($(ENV))..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml --check --diff

cleanup:
	@echo "🔥 KILLING EVERYTHING in the Swarm Cluster ($(ENV))..."
	@$(MAKE) -C ../terraform keyscan ENV=$(ENV) 2>/dev/null || true
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV)" poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/cleanup.yml
