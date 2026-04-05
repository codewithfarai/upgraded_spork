#!/usr/bin/env bash
set -euo pipefail

COMMIT_MSG_FILE="${1:-}"
if [[ -z "$COMMIT_MSG_FILE" || ! -f "$COMMIT_MSG_FILE" ]]; then
  echo "ERROR: commit message file not found."
  exit 1
fi

COMMIT_MSG="$(head -n1 "$COMMIT_MSG_FILE")"
STAGED_FILES="$(git diff --cached --name-only)"

HAS_PAYMENT=false
HAS_ONBOARDING=false
HAS_RIDE=false

if echo "$STAGED_FILES" | grep -qE '^ride_base/payment_service/'; then
  HAS_PAYMENT=true
fi

if echo "$STAGED_FILES" | grep -qE '^ride_base/onboarding_service/'; then
  HAS_ONBOARDING=true
fi

if echo "$STAGED_FILES" | grep -qE '^ride_base/ride_service/'; then
  HAS_RIDE=true
fi

# Ignore auto-generated version bump commits.
if echo "$COMMIT_MSG" | grep -qE '^bump:'; then
  exit 0
fi

# Count how many services are touched
SERVICES_TOUCHED=0
[[ "$HAS_PAYMENT" == true ]] && SERVICES_TOUCHED=$((SERVICES_TOUCHED + 1))
[[ "$HAS_ONBOARDING" == true ]] && SERVICES_TOUCHED=$((SERVICES_TOUCHED + 1))
[[ "$HAS_RIDE" == true ]] && SERVICES_TOUCHED=$((SERVICES_TOUCHED + 1))

if [[ "$HAS_PAYMENT" == true && "$SERVICES_TOUCHED" -eq 1 ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\(payment\):\s.+'; then
    echo "ERROR: payment_service changes require scope '(payment)'."
    echo "Example: feat(payment): add webhook idempotency guard"
    exit 1
  fi
fi

if [[ "$HAS_ONBOARDING" == true && "$SERVICES_TOUCHED" -eq 1 ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\(onboarding\):\s.+'; then
    echo "ERROR: onboarding_service changes require scope '(onboarding)'."
    echo "Example: fix(onboarding): validate OIDC subject mapping"
    exit 1
  fi
fi

if [[ "$HAS_RIDE" == true && "$SERVICES_TOUCHED" -eq 1 ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\(ride_service\):\s.+'; then
    echo "ERROR: ride_service changes require scope '(ride_service)'."
    echo "Example: feat(ride_service): add GPS flush loop"
    exit 1
  fi
fi

# If more than one service is touched in one commit, require an explicit shared scope.
if [[ "$SERVICES_TOUCHED" -gt 1 ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\((infra|root)\):\s.+'; then
    echo "ERROR: commits touching multiple services must use '(infra)' or '(root)' scope."
    echo "Example: chore(infra): update shared API contracts"
    exit 1
  fi
fi
