# Default environment (dev, stage, prod)
ENV ?= dev

# Load environment variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: init plan apply destroy destroy_all setup_keys sync_secrets view_keys ssh_cleanup verify verify_bastion verify_node_manager verify_node_worker lint

setup_keys:
	@bash ../scripts/generate_ssh_keys.sh

sync_secrets:
	@echo "🔐 Syncing secrets to GitHub..."
	@if ! command -v gh &> /dev/null; then \
		echo "❌ Error: GitHub CLI (gh) is not installed. Run 'brew install gh' first."; \
		exit 1; \
	fi
	@if ! gh auth status &> /dev/null; then \
		echo "❌ Error: Not logged into GitHub CLI. Run 'gh auth login' first."; \
		exit 1; \
	fi
	@if [ -f .env ]; then \
		echo "Pushing variables from .env..."; \
		grep -v '^#' .env | grep -v '^$$' | while IFS='=' read -r key value; do \
			gh secret set "$$key" --body "$$value" && echo "  ✅ Set: $$key"; \
		done; \
	else echo "⚠️ No .env file found to sync."; fi
	@echo "Pushing variables from terraform.tfvars..."; \
	HCLOUD_TOKEN=$$(grep -E '^\s*hcloud_token\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$HCLOUD_TOKEN" ]; then \
		gh secret set "HCLOUD_TOKEN" --body "$$HCLOUD_TOKEN" && echo "  ✅ Set: HCLOUD_TOKEN"; \
	fi; \
	PROJECT_NAME=$$(grep -E '^\s*project_name\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$PROJECT_NAME" ]; then \
		gh secret set "TF_VAR_project_name" --body "$$PROJECT_NAME" && echo "  ✅ Set: TF_VAR_project_name"; \
	fi; \
	ALLOWED_SSH_IPS=$$(grep -E '^\s*allowed_ssh_ips\s*=' terraform.tfvars | sed -E 's/^\s*allowed_ssh_ips\s*=\s*(.*)/\1/' | sed 's/^ *//;s/ *$$//'); \
	if [ -n "$$ALLOWED_SSH_IPS" ]; then \
		gh secret set "TF_VAR_allowed_ssh_ips" --body "$$ALLOWED_SSH_IPS" && echo "  ✅ Set: TF_VAR_allowed_ssh_ips"; \
	fi; \
	SSH_DEV=$$(grep -E '^\s*dev\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$SSH_DEV" ]; then \
		gh api -X PUT /repos/{owner}/{repo}/environments/dev --silent 2>/dev/null || true; \
		gh secret set "TF_VAR_ssh_key" --env dev --body "$$SSH_DEV" && echo "  ✅ Set: TF_VAR_ssh_key (dev env)"; \
	fi; \
	SSH_STAGE=$$(grep -E '^\s*stage\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$SSH_STAGE" ]; then \
		gh api -X PUT /repos/{owner}/{repo}/environments/stage --silent 2>/dev/null || true; \
		gh secret set "TF_VAR_ssh_key" --env stage --body "$$SSH_STAGE" && echo "  ✅ Set: TF_VAR_ssh_key (stage env)"; \
	fi; \
	SSH_PROD=$$(grep -E '^\s*prod\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$SSH_PROD" ]; then \
		gh api -X PUT /repos/{owner}/{repo}/environments/prod --silent 2>/dev/null || true; \
		gh secret set "TF_VAR_ssh_key" --env prod --body "$$SSH_PROD" && echo "  ✅ Set: TF_VAR_ssh_key (prod env)"; \
	fi
	@echo "🎉 Sync complete!"

view_keys:
	@PROJECT_NAME=$$(grep -E '^\s*project_name\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	echo "🔍 Project SSH Keys in ~/.ssh/ ($$PROJECT_NAME*):"; \
	ls -la ~/.ssh/$$PROJECT_NAME* 2>/dev/null || echo "No matching keys found for $$PROJECT_NAME"

ssh_cleanup:
	@BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	EDGE_IPS=$$(terraform output -json edge_public_ips | jq -r '.[]'); \
	INTERNAL_IPS=$$(terraform output -json internal_ips | jq -r '.. | arrays | .[]'); \
	echo "🧹 Cleaning up host keys for project IPs..."; \
	[ -n "$$BASTION_IP" ] && ssh-keygen -R $$BASTION_IP 2>/dev/null; \
	for ip in $$EDGE_IPS $$INTERNAL_IPS; do \
		ssh-keygen -R $$ip 2>/dev/null; \
	done; \
	echo "✅ project IPs removed from ~/.ssh/known_hosts"

init:
	terraform init \
		-reconfigure \
		-backend-config="bucket=$(TF_STATE_BUCKET)" \
		-backend-config="key=$(TF_STATE_KEY)-$(ENV)"

plan:
	$(MAKE) init ENV=$(ENV)
	terraform plan -var="environment=$(ENV)"

apply:
	$(MAKE) init ENV=$(ENV)
	terraform apply -var="environment=$(ENV)"

destroy:
	$(MAKE) init ENV=$(ENV)
	terraform destroy -var="environment=$(ENV)"

destroy_all:
	@echo "Destroying all environments (dev, stage, prod)..."
	$(MAKE) destroy ENV=dev
	$(MAKE) destroy ENV=stage
	$(MAKE) destroy ENV=prod

# Security & NAT Verification
ssh:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$$(grep -E "^\s*$(ENV)\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $$NF}'); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	if [ ! -f "$$RAW_KEY" ]; then echo "❌ Error: SSH key $$RAW_KEY not found"; exit 1; fi; \
	echo "🔌 Connecting to Bastion Host ($$BASTION_IP) using key ($$RAW_KEY)..."; \
	ssh -i $$RAW_KEY -o StrictHostKeyChecking=no
	 -o UserKnownHostsFile=/dev/null root@$$BASTION_IP

verify: verify_bastion verify_node_manager verify_node_worker

verify_bastion:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$$(grep -E "^\s*$(ENV)\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $$NF}'); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	if [ ! -f "$$RAW_KEY" ]; then echo "❌ Error: SSH key $$RAW_KEY not found (Derived from tfvars: $$SSH_KEY_NAME)"; exit 1; fi; \
	echo "🔍 Verifying Bastion Host ($$BASTION_IP) using key ($$RAW_KEY)..."; \
	ssh -i $$RAW_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$$BASTION_IP "bash -s" < scripts/verify_security.sh

verify_node_manager:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$$(grep -E "^\s*$(ENV)\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $$NF}'); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	EDGE_IP=$$(terraform output -json edge_public_ips | jq -r '.[0]'); \
	MANAGER_IP=$$(terraform output -json internal_ips | jq -r '.managers[0][0]'); \
	if [ ! -f "$$RAW_KEY" ]; then echo "❌ Error: SSH key $$RAW_KEY not found (Derived from tfvars: $$SSH_KEY_NAME)"; exit 1; fi; \
	echo "🔍 Verifying Manager-1 ($$MANAGER_IP) via Bastion ($$BASTION_IP) using key ($$RAW_KEY)..."; \
	ssh -i $$RAW_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o ProxyCommand="ssh -i $$RAW_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p root@$$BASTION_IP" \
		root@$$MANAGER_IP "bash -s $$EDGE_IP" < scripts/verify_security.sh

verify_node_worker:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$$(grep -E "^\s*$(ENV)\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $$NF}'); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	EDGE_IP=$$(terraform output -json edge_public_ips | jq -r '.[0]'); \
	WORKER_IP=$$(terraform output -json internal_ips | jq -r '.workers[0][0]'); \
	if [ ! -f "$$RAW_KEY" ]; then echo "❌ Error: SSH key $$RAW_KEY not found (Derived from tfvars: $$SSH_KEY_NAME)"; exit 1; fi; \
	echo "🔍 Verifying Worker-1 ($$WORKER_IP) via Bastion ($$BASTION_IP)..."; \
	ssh -i $$RAW_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o ProxyCommand="ssh -i $$RAW_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p root@$$BASTION_IP" \
		root@$$WORKER_IP "bash -s $$EDGE_IP" < scripts/verify_security.sh

lint:
	poetry run pre-commit run --all-files
