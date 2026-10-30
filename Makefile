.DEFAULT_GOAL := help
.PHONY: help setup lint secrets hooks-update validate test-contract chart-test test-isolation cluster-up cluster-down tenants-apply kyverno-up

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

validate: ## Validate the tenant files against the contract
	python3 scripts/validate_tenants.py tenants/*.yaml

test-contract: ## Run the contract tests (valid files pass, invalid files fail)
	bash tests/contract/run.sh

cluster-up: ## Build the kind cluster and install Calico
	bash scripts/cluster-up.sh

cluster-down: ## Delete the kind cluster
	bash scripts/cluster-down.sh

chart-test: ## Lint and render the tenant chart for every tenant file
	bash scripts/chart-test.sh

tenants-apply: ## Render every tenant file and apply it to the local cluster
	bash scripts/tenants-apply.sh

test-isolation: ## Run the isolation tests against the local cluster
	bash tests/isolation/run.sh

kyverno-up: ## Install Kyverno into the local cluster at the pinned chart version
	bash scripts/kyverno-install.sh
