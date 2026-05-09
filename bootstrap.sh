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
# Step 1: Build & Push Service Images (Parallelized)
# ------------------------------------------------------------------------------
echo "🔨 Building and pushing service images in parallel..."
(cd "$ROOT_DIR/ride_base/payment_service" && make build) &
(cd "$ROOT_DIR/ride_base/onboarding_service" && make build) &
(cd "$ROOT_DIR/ride_base/admin_service" && make build) &

wait # Wait for all builds to finish

# ------------------------------------------------------------------------------
# Step 2: Terraform Infrastructure
# ------------------------------------------------------------------------------
echo "🔨 Deploying Terraform Infrastructure ($ENV)..."
cd "$ROOT_DIR/terraform"
make apply ENV=$ENV ARGS="-auto-approve"

# ------------------------------------------------------------------------------
# Step 3: SSH Keyscan & Verification
# ------------------------------------------------------------------------------
echo "🔑 Running keyscan..."
make keyscan ENV=$ENV
sleep 60

echo "🔍 Verifying node health..."
make verify ENV=$ENV
echo "⏳ Waiting 60s for cloud-init and networking to settle..."
sleep 60

# ------------------------------------------------------------------------------
# Step 4: Ansible Initial Deploy (Pass 1 - Infrastructure Only)
# ------------------------------------------------------------------------------
echo "🐝 Deploying Swarm (Pass 1 - Database & Core Infra)..."
cd "$ROOT_DIR/ansible"

# Retry loop for initial swarm setup (handles transient join/label races)
for i in {1..3}; do
    if AUTHENTIK_BOOTSTRAP_REPLICAS=1 make swarm ENV=$ENV EXTRA_VARS="payment_service_enabled=false onboarding_service_enabled=false admin_service_enabled=false map_service_enabled=false monitoring_enabled=false"; then
        echo "✅ Pass 1 successful."
        break
    else
        if [ $i -eq 3 ]; then echo "❌ Pass 1 failed after 3 attempts."; exit 1; fi
        echo "⚠️ Pass 1 failed. Retrying in 30s..."
        sleep 30
    fi
done

# ------------------------------------------------------------------------------
# Step 5: Wait for Database HA Stability
# ------------------------------------------------------------------------------
echo "⏳ Waiting for Database HA to stabilize..."
sleep 30

# ------------------------------------------------------------------------------
# Step 6: Authentik Setup (Terraform)
# ------------------------------------------------------------------------------
echo "🔐 Configuring Authentik Identity Provider..."
cd "$ROOT_DIR/terraform_authentik"
for i in {1..3}; do
    if make apply ENV=$ENV ARGS="-auto-approve"; then
        echo "✅ Authentik configuration applied."
        break
    else
        if [ $i -eq 3 ]; then echo "❌ Authentik config failed after 3 attempts."; exit 1; fi
        echo "⚠️ Authentik not ready yet. Retrying in 60s..."
        sleep 60
    fi
done

# ------------------------------------------------------------------------------
# Step 7: Final Ansible Deploy (Full Scale)
# ------------------------------------------------------------------------------
echo "🚀 Deploying Swarm (Pass 2 - Scaling up all services)..."
cd "$ROOT_DIR/ansible"
make swarm ENV=$ENV

echo "✨ $(echo $ENV | tr '[:lower:]' '[:upper:]') ENVIRONMENT READY! ✨"
