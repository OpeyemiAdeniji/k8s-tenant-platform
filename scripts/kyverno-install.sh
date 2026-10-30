#!/usr/bin/env bash
# Install Kyverno into the local cluster with Helm, at the pinned chart version.
# Usage: scripts/kyverno-install.sh (or: make kyverno-up)
set -euo pipefail

cd "$(dirname "$0")/.."

CONTEXT="kind-tenant-platform"
VERSION="$(tr -d '[:space:]' < platform/kyverno/chart-version)"

for tool in helm kubectl; do
  command -v "$tool" > /dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
[ -n "$VERSION" ] || { echo "platform/kyverno/chart-version is empty" >&2; exit 1; }

helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update > /dev/null
helm repo update kyverno > /dev/null

start=$SECONDS
kubectl --context "$CONTEXT" apply -f platform/kyverno/cleanup-clusterrole.yaml -f platform/kyverno/cleanup-clusterrolebinding.yaml
echo "==> installing Kyverno chart $VERSION"
helm upgrade --install kyverno kyverno/kyverno \
  --version "$VERSION" \
  --namespace kyverno --create-namespace \
  --kube-context "$CONTEXT" \
  --values platform/kyverno/values.yaml \
  --wait --timeout 10m

kubectl --context "$CONTEXT" apply -f platform/kyverno/platform-exceptions-namespace.yaml
echo "kyverno ready: $((SECONDS - start)) s"
kubectl --context "$CONTEXT" -n kyverno get pods
