# Default environment (dev, stage, prod)
ENV ?= dev
# Default node index for SSH (0-indexed)
NODE ?= 0

# Load environment variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: init plan apply destroy destroy_all setup_keys setup_dns sync_secrets view_keys ssh_cleanup verify verify_bastion verify_node_manager verify_node_worker verify_node_database lint

# Helper to get SSH Key Name from public key string in tfvars
# This remains the fallback if not provided via environment
GET_SSH_KEY_NAME = $$(grep -E "^\s*$(ENV)\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $$NF}')

setup_dns:
	@DOMAIN=$$(grep -E '^\s*domain_name\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	TOKEN=$$(grep -E '^\s*hcloud_token\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -z "$$DOMAIN" ] || [ -z "$$TOKEN" ]; then \
		echo "❌ Error: domain_name or hcloud_token not found in terraform.tfvars"; \
		exit 1; \
	fi; \
	echo "🌐 Creating DNS zone for $$DOMAIN..."; \
	RESPONSE=$$(curl -s -w "\n%{http_code}" -X POST "https://api.hetzner.cloud/v1/zones" \
		-H "Authorization: Bearer $$TOKEN" \
		-H "Content-Type: application/json" \
		-d "{\"name\": \"$$DOMAIN\", \"mode\": \"primary\"}"); \
	HTTP_CODE=$$(echo "$$RESPONSE" | tail -1); \
	BODY=$$(echo "$$RESPONSE" | sed '$$d'); \
	if [ "$$HTTP_CODE" = "201" ]; then \
		echo "✅ Zone '$$DOMAIN' created successfully!"; \
		echo "$$BODY" | python3 -c "import sys,json; ns=json.load(sys.stdin).get('zone',{}).get('authoritative_nameservers',{}).get('assigned',[]); print('📋 Nameservers to set in GoDaddy:'); [print(f'   {n}') for n in ns]" 2>/dev/null || true; \
	elif [ "$$HTTP_CODE" = "409" ]; then \
		echo "✅ Zone '$$DOMAIN' already exists (no action needed)."; \
	else \
		echo "❌ Failed to create zone (HTTP $$HTTP_CODE):"; \
		echo "$$BODY"; \
		exit 1; \
	fi

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
	DOMAIN_NAME=$$(grep -E '^\s*domain_name\s*=' terraform.tfvars | sed -E 's/.*"(.*)".*/\1/'); \
	if [ -n "$$DOMAIN_NAME" ]; then \
		gh secret set "TF_VAR_domain_name" --body "$$DOMAIN_NAME" && echo "  ✅ Set: TF_VAR_domain_name"; \
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
	[ -n "$$BASTION_IP" ] && ssh-keygen -f ~/.ssh/known_hosts_$(ENV) -R $$BASTION_IP 2>/dev/null; \
	for ip in $$EDGE_IPS $$INTERNAL_IPS; do \
		ssh-keygen -f ~/.ssh/known_hosts_$(ENV) -R $$ip 2>/dev/null; \
	done; \
	echo "✅ project IPs removed from ~/.ssh/known_hosts_$(ENV)"

keyscan:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	RANGE=$$(terraform output -raw network_ip_range | cut -d'/' -f1 | cut -d'.' -f1,2); \
	INTERNAL_IPS=$$(terraform output -json internal_ips | jq -r '.. | strings' | grep "^$$RANGE" | sort -u); \
	if [ -z "$$INTERNAL_IPS" ]; then echo "⚠️ No internal IPs found to scan."; exit 0; fi; \
	echo "🔍 Scanning Bastion ($$BASTION_IP)..."; \
	ssh-keygen -f ~/.ssh/known_hosts_$(ENV) -R $$BASTION_IP 2>/dev/null; \
	ssh-keyscan -H $$BASTION_IP >> ~/.ssh/known_hosts_$(ENV) 2>/dev/null; \
	echo "🔍 Scanning internal nodes via Bastion..."; \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	IP_LIST=$$(echo $$INTERNAL_IPS | tr '\n' ' '); \
	for ip in $$INTERNAL_IPS; do ssh-keygen -f ~/.ssh/known_hosts_$(ENV) -R $$ip 2>/dev/null; done; \
	ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) provision@$$BASTION_IP "ssh-keyscan $$IP_LIST" 2>/dev/null >> ~/.ssh/known_hosts_$(ENV); \
	echo "✅ All host keys updated in ~/.ssh/known_hosts_$(ENV)"

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

# Common logic for SSH connectivity
ssh_bastion:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	if [ ! -f "$$RAW_KEY" ]; then echo "❌ Error: SSH key $$RAW_KEY not found"; exit 1; fi; \
	echo "🔌 Connecting to Bastion Host ($$BASTION_IP)..."; \
	ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) provision@$$BASTION_IP

ssh_manager:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	MANAGER_IP=$$(terraform output -json internal_ips | jq -r ".managers[$(NODE)][0]"); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	echo "🔌 Connecting to Manager Node ($$MANAGER_IP) [index $(NODE)] via Bastion..."; \
	ssh -i $$RAW_KEY \
		-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
		-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
		provision@$$MANAGER_IP

ssh_worker:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	WORKER_IP=$$(terraform output -json internal_ips | jq -r ".workers[$(NODE)][0]"); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	echo "🔌 Connecting to Worker Node ($$WORKER_IP) [index $(NODE)] via Bastion..."; \
	ssh -i $$RAW_KEY \
		-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
		-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
		provision@$$WORKER_IP

ssh_db: ssh_database
ssh_database:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	DB_IP=$$(terraform output -json internal_ips | jq -r ".database[$(NODE)][0]"); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	echo "🔌 Connecting to Database Node ($$DB_IP) [index $(NODE)] via Bastion..."; \
	ssh -i $$RAW_KEY \
		-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
		-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
		provision@$$DB_IP

# Verification targets
verify: verify_bastion verify_node_manager verify_node_worker verify_node_database

verify_bastion:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	echo "🔍 Verifying Bastion Host ($$BASTION_IP)..."; \
	ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) provision@$$BASTION_IP "bash -s" < scripts/verify_security.sh

verify_node_manager:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	EDGE_IPS=$$(terraform output -json edge_public_ips | jq -r '. | join(" ")'); \
	MANAGER_IPS=$$(terraform output -json internal_ips | jq -r '.managers[] | .[]'); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	for ip in $$MANAGER_IPS; do \
		echo "🔍 Verifying Manager ($$ip) via Bastion..."; \
		ssh -i $$RAW_KEY \
			-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
			-o StrictHostKeyChecking=accept-new \
			-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
			provision@$$ip "bash -s $$EDGE_IPS" < scripts/verify_security.sh; \
	done

verify_node_worker:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	EDGE_IPS=$$(terraform output -json edge_public_ips | jq -r '. | join(" ")'); \
	WORKER_IPS=$$(terraform output -json internal_ips | jq -r '.workers[] | .[]'); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	for ip in $$WORKER_IPS; do \
		echo "🔍 Verifying Worker ($$ip) via Bastion..."; \
		ssh -i $$RAW_KEY \
			-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
			-o StrictHostKeyChecking=accept-new \
			-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
			provision@$$ip "bash -s $$EDGE_IPS" < scripts/verify_security.sh; \
	done

verify_node_database:
	@$(MAKE) init ENV=$(ENV) >/dev/null; \
	BASTION_IP=$$(terraform output -raw bastion_public_ip); \
	EDGE_IPS=$$(terraform output -json edge_public_ips | jq -r '. | join(" ")'); \
	DB_IPS=$$(terraform output -json internal_ips | jq -r '.database[] | .[]'); \
	SSH_KEY_NAME=$(GET_SSH_KEY_NAME); \
	SSH_KEY=$${SSH_KEY:-~/.ssh/$$SSH_KEY_NAME}; \
	RAW_KEY=$$(eval echo $$SSH_KEY); \
	for ip in $$DB_IPS; do \
		echo "🔍 Verifying Database Node ($$ip) via Bastion..."; \
		ssh -i $$RAW_KEY \
			-o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) \
			-o StrictHostKeyChecking=accept-new \
			-o ProxyCommand="ssh -i $$RAW_KEY -o UserKnownHostsFile=~/.ssh/known_hosts_$(ENV) -W %h:%p provision@$$BASTION_IP" \
			provision@$$ip "bash -s $$EDGE_IPS" < scripts/verify_security.sh; \
	done

lint:
	poetry run pre-commit run --all-files
