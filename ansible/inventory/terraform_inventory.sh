#!/bin/bash
set -e

# Dynamic Ansible Inventory from Terraform Outputs
# Outputs JSON format required by Ansible's dynamic inventory plugin.
#
# Usage: ENV=dev ./terraform_inventory.sh --list
#        ENV=dev ./terraform_inventory.sh --host <hostname>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../../terraform"

ENV="${ENV:-dev}"

# Handle --host (return empty vars for any host)
if [ "$1" = "--host" ]; then
    echo '{}'
    exit 0
fi

# Ensure we're in the terraform directory
cd "$TERRAFORM_DIR"

# Load environment variables (.env has AWS credentials for S3 backend)
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Re-initialize Terraform for the correct environment
if make init ENV="$ENV" > /dev/null 2>&1; then
    echo "✅ Terraform initialized for $ENV" >&2
else
    echo "❌ Terraform init failed for $ENV" >&2
    exit 1
fi

# Get outputs in JSON format
OUTPUTS=$(terraform output -json 2>/dev/null)

if [ -z "$OUTPUTS" ] || [ "$OUTPUTS" = "{}" ]; then
    echo '{"_meta": {"hostvars": {}}}'
    exit 0
fi

# Resolve SSH key name from terraform.tfvars
SSH_KEY_NAME=$(grep -E "^\s*${ENV}\s*=" terraform.tfvars | sed -E 's/.*"(.*)".*/\1/' | awk '{print $NF}')
SSH_KEY_PATH="~/.ssh/${SSH_KEY_NAME}"

# Generate JSON inventory via Python helper (avoids quoting hell)
export ENV SSH_KEY_PATH
echo "$OUTPUTS" | python3 "${SCRIPT_DIR}/inventory_builder.py"
