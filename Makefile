.DEFAULT_GOAL := help
.PHONY: help setup lint secrets hooks-update

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

setup: ## Install the git hooks (pre-commit is installed with pipx)
	@command -v pre-commit >/dev/null || (echo 'Install pre-commit first: pipx install pre-commit'; exit 1)
	pre-commit install --install-hooks
	pre-commit install --hook-type commit-msg

lint: ## Run every pre-commit hook against all files
	pre-commit run --all-files

secrets: ## Scan the full git history for leaked secrets
	gitleaks git --redact

hooks-update: ## Bump pinned hook versions in .pre-commit-config.yaml
	pre-commit autoupdate
