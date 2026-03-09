#!/bin/bash
# Generate Authentik secrets and write to .env if not already set
# Usage: ./scripts/generate_authentik_secrets.sh
set -e

ENV_FILE="$(dirname "$0")/../.env"

# Create .env if it doesn't exist
touch "$ENV_FILE"

generate_secret() {
    local var_name="$1"
    local length="${2:-40}"

    if grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null; then
        echo "  ✅ ${var_name} already set"
    else
        local value
        value=$(openssl rand -base64 "$length" | tr -d '/+=' | head -c "$length")
        echo "${var_name}=${value}" >> "$ENV_FILE"
        echo "  🔑 ${var_name} generated"
    fi
}

echo "🔐 Generating Authentik secrets..."
generate_secret "AUTHENTIK_SECRET_KEY" 50
generate_secret "AUTHENTIK_DB_PASSWORD" 32
generate_secret "AUTHENTIK_BOOTSTRAP_TOKEN" 40
generate_secret "AUTHENTIK_ADMIN_PASSWORD" 24

if ! grep -q "^AUTHENTIK_ADMIN_EMAIL=" "$ENV_FILE" 2>/dev/null; then
    echo "AUTHENTIK_ADMIN_EMAIL=admin@uzuri.co.uk" >> "$ENV_FILE"
    echo "  📧 AUTHENTIK_ADMIN_EMAIL set to default (admin@uzuri.co.uk)"
else
    echo "  ✅ AUTHENTIK_ADMIN_EMAIL already set"
fi

echo ""
echo "✅ Secrets stored in: $ENV_FILE"
echo "⚠️  This file is gitignored — never commit it."
echo ""
echo "📋 Current secrets:"
grep "^AUTHENTIK_" "$ENV_FILE"
