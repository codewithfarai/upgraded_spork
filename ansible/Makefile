ENV ?= dev

.PHONY: swarm swarm_check

swarm:
	@echo "🐝 Bootstrapping Docker Swarm ($(ENV))..."
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml

swarm_check:
	@echo "🔍 Dry-run Docker Swarm bootstrap ($(ENV))..."
	ANSIBLE_CONFIG=ansible.cfg ENV=$(ENV) poetry run ansible-playbook -i inventory/terraform_inventory.sh playbooks/swarm.yml --check --diff
