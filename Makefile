.PHONY: test-commit-scope

# Usage: make test-commit-scope MSG='feat(payment): add webhook retries'
# Stage files first; validation uses staged paths to enforce scope rules.
test-commit-scope:
	@if [ -z "$(MSG)" ]; then \
		echo "Usage: make test-commit-scope MSG='feat(payment): your message'"; \
		exit 1; \
	fi
	@tmp=$$(mktemp); \
	printf "%s\n" "$(MSG)" > "$$tmp"; \
	poetry run pre-commit run validate-commit-scope --hook-stage commit-msg --commit-msg-filename "$$tmp"; \
	rm -f "$$tmp"
