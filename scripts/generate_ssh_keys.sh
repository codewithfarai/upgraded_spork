#!/bin/bash
# Generate environment-specific SSH keys for the project
# This script reads the project name from terraform.tfvars and creates keys in ~/.ssh/

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSH_DIR="$HOME/.ssh"

echo -e "${BLUE}=== SSH Key Generation Utility ===${NC}"

# 1. Extract Project Name
TFVARS="terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
    TFVARS="terraform/terraform.tfvars"
fi

if [ ! -f "$TFVARS" ]; then
    echo -e "${YELLOW}Warning: terraform.tfvars not found. Using 'project' as default name.${NC}"
    PROJECT_NAME="project"
else
    PROJECT_NAME=$(grep -E '^\s*project_name\s*=' "$TFVARS" | sed -E 's/.*"(.*)".*/\1/')
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="project"
    fi
fi

echo -e "Project Name: ${GREEN}$PROJECT_NAME${NC}"
echo -e "Target Directory: ${GREEN}$SSH_DIR${NC}"
echo ""

ENVIRONMENTS=("dev" "stage" "prod")
CREATED_KEYS=()

for ENV in "${ENVIRONMENTS[@]}"; do
    KEY_NAME="${PROJECT_NAME}_${ENV}"
    KEY_PATH="$SSH_DIR/$KEY_NAME"

    if [ -f "$KEY_PATH" ]; then
        echo -e "${YELLOW}[SKIP]${NC} Key already exists: $KEY_NAME"
    else
        echo -n "Generating key for $ENV... "
        ssh-keygen -t ed25519 -C "$KEY_NAME" -f "$KEY_PATH" -N "" >/dev/null
        echo -e "${GREEN}DONE${NC}"
    fi

    # Read the public key content
    PUB_KEY=$(cat "${KEY_PATH}.pub")
    CREATED_KEYS+=("  $ENV = \"$PUB_KEY\"")
done

echo ""
echo -e "${BLUE}=== Copy & Paste into your terraform.tfvars ===${NC}"
echo "ssh_keys = {"
for KEY_LINE in "${CREATED_KEYS[@]}"; do
    echo "$KEY_LINE"
done
echo "}"
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo -e "You can now use 'make apply ENV=dev' etc. and the Makefile will find these keys automatically."
