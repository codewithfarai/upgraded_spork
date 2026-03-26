#!/bin/bash
set -e # Stop on any error

# ------------------------------------------------------------------------------
# Environment Validation
# ------------------------------------------------------------------------------
ENV=$1

if [[ -z "$ENV" ]]; then
    echo "❌ Error: No environment specified."
    echo "Usage: ./bootstrap.sh [dev|stage|prod]"
    exit 1
fi

if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
    echo "❌ Error: Invalid environment '$ENV'. Must be dev, stage, or prod."
    exit 1
fi

echo "🚀 Starting Full $(echo $ENV | tr '[:lower:]' '[:upper:]') Deployment..."

# Get the script's root directory
ROOT_DIR=$(pwd)

# ------------------------------------------------------------------------------
# Step 1: Terraform Infrastructure
# ------------------------------------------------------------------------------
echo "🔨 Deploying Terraform Infrastructure ($ENV)..."
cd "$ROOT_DIR/terraform"
make apply ENV=$ENV ARGS="-auto-approve"

echo "⏳ Sleeping 10m for SSH and cloud-init to finish..."
sleep 600

# ------------------------------------------------------------------------------
# Step 2: SSH Keyscan
# ------------------------------------------------------------------------------
echo "🔑 Running keyscan..."
make keyscan ENV=$ENV
sleep 300

# ------------------------------------------------------------------------------
# Step 3: Verify Nodes
# ------------------------------------------------------------------------------
echo "🔍 Verifying node health..."
make verify ENV=$ENV
sleep 300

# ------------------------------------------------------------------------------
# Step 4: Ansible Initial Deploy
# ------------------------------------------------------------------------------
echo "🐝 Deploying Swarm (Pass 1 - Bootstrap)..."
cd "$ROOT_DIR/ansible"
make swarm ENV=$ENV
sleep 300

# ------------------------------------------------------------------------------
# Step 5: Ansible Second Deploy
# ------------------------------------------------------------------------------
echo "🔁 Redeploying Swarm (Pass 2 - Stabilization)..."
make swarm ENV=$ENV
sleep 300

# ------------------------------------------------------------------------------
# Step 6: Authentik Setup
# ------------------------------------------------------------------------------
echo "🔐 Deploying Authentik Configuration..."
cd "$ROOT_DIR/terraform_authentik"
make apply ENV=$ENV ARGS="-auto-approve"

echo "✨ $(echo $ENV | tr '[:lower:]' '[:upper:]') ENVIRONMENT READY! ✨"
