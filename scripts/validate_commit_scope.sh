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

if echo "$STAGED_FILES" | grep -qE '^ride_base/payment_service/'; then
  HAS_PAYMENT=true
fi

if echo "$STAGED_FILES" | grep -qE '^ride_base/onboarding_service/'; then
  HAS_ONBOARDING=true
fi

# Ignore auto-generated version bump commits.
if echo "$COMMIT_MSG" | grep -qE '^bump:'; then
  exit 0
fi

if [[ "$HAS_PAYMENT" == true && "$HAS_ONBOARDING" == false ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\(payment\):\s.+'; then
    echo "ERROR: payment_service changes require scope '(payment)'."
    echo "Example: feat(payment): add webhook idempotency guard"
    exit 1
  fi
fi

if [[ "$HAS_ONBOARDING" == true && "$HAS_PAYMENT" == false ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\(onboarding\):\s.+'; then
    echo "ERROR: onboarding_service changes require scope '(onboarding)'."
    echo "Example: fix(onboarding): validate OIDC subject mapping"
    exit 1
  fi
fi

# If both services are touched in one commit, require an explicit shared scope.
if [[ "$HAS_PAYMENT" == true && "$HAS_ONBOARDING" == true ]]; then
  if ! echo "$COMMIT_MSG" | grep -qE '^(build|bump|docs|feat|fix|refactor|chore|test|style|perf|ci)\((infra|root)\):\s.+'; then
    echo "ERROR: commits touching both services must use '(infra)' or '(root)' scope."
    echo "Example: chore(infra): update shared API contracts for onboarding and payment"
    exit 1
  fi
fi
