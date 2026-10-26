#!/usr/bin/env bash
# Render every tenant file and apply it to the local cluster.
# In v0.3 Argo CD replaces this step. Removing a tenant file does not remove the
# tenant here, because kubectl apply does not prune.
# Usage: scripts/tenants-apply.sh (or: make tenants-apply)
set -euo pipefail

cd "$(dirname "$0")/.."

CONTEXT="kind-tenant-platform"

for tool in helm kubectl; do
  command -v "$tool" > /dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

for file in tenants/*.yaml; do
  name="$(basename "$file" .yaml)"
  echo "==> applying tenant $name"
  helm template "tenant-$name" platform/charts/tenant -f "$file" \
    | kubectl --context "$CONTEXT" apply -f -
done
