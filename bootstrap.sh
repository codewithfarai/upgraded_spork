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
# Step 1: Build & Push Service Images
# ------------------------------------------------------------------------------
echo "🔨 Building and pushing service images..."
cd "$ROOT_DIR/ride_base/payment_service"
make build && make push

cd "$ROOT_DIR/ride_base/onboarding_service"
make build && make push

cd "$ROOT_DIR/ride_base/admin_service"
make build && make push

# ------------------------------------------------------------------------------
# Step 2: Terraform Infrastructure
# ------------------------------------------------------------------------------
echo "🔨 Deploying Terraform Infrastructure ($ENV)..."
cd "$ROOT_DIR/terraform"
make apply ENV=$ENV ARGS="-auto-approve"

echo "⏳ Sleeping 10m for SSH and cloud-init to finish..."
sleep 300

# ------------------------------------------------------------------------------
# Step 3: SSH Keyscan
# ------------------------------------------------------------------------------
echo "🔑 Running keyscan..."
make keyscan ENV=$ENV
sleep 3

# ------------------------------------------------------------------------------
# Step 4: Verify Nodes
# ------------------------------------------------------------------------------
echo "🔍 Verifying node health..."
make verify ENV=$ENV
sleep 300

# ------------------------------------------------------------------------------
# Step 300: Ansible Initial Deploy (without services — Authentik not ready yet)
# Single Authentik replica to avoid migration lock race condition on fresh DB.
# ------------------------------------------------------------------------------
echo "🐝 Deploying Swarm (Pass 1 - Bootstrap, services disabled)..."
cd "$ROOT_DIR/ansible"
AUTHENTIK_BOOTSTRAP_REPLICAS=1 make swarm ENV=$ENV EXTRA_VARS="payment_service_enabled=false onboarding_service_enabled=false admin_service_enabled=false"
sleep 300

# ------------------------------------------------------------------------------
# Step 6: Ansible Second Deploy (still without services — stabilization)
# ------------------------------------------------------------------------------
echo "🔁 Redeploying Swarm (Pass 2 - Stabilization, services disabled)..."
make swarm ENV=$ENV EXTRA_VARS="payment_service_enabled=false onboarding_service_enabled=false admin_service_enabled=false"
sleep 300

# ------------------------------------------------------------------------------
# Step 7: Authentik Setup
# ------------------------------------------------------------------------------
echo "🔐 Deploying Authentik Configuration..."
cd "$ROOT_DIR/terraform_authentik"
make apply ENV=$ENV ARGS="-auto-approve"
sleep 300


# ------------------------------------------------------------------------------
# Step 8: Ansible Third Deploy (with services — Authentik token now exists)
# ------------------------------------------------------------------------------
echo "🚀 Deploying Swarm (Pass 3 - Full deploy with services)..."
cd "$ROOT_DIR/ansible"
make swarm ENV=$ENV

echo "✨ $(echo $ENV | tr '[:lower:]' '[:upper:]') ENVIRONMENT READY! ✨"
