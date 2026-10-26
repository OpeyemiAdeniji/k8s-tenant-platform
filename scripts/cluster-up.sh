#!/usr/bin/env bash
# Build the local kind cluster and install Calico.
# Usage: scripts/cluster-up.sh (or: make cluster-up)
set -euo pipefail

CLUSTER_NAME="tenant-platform"
CALICO_VERSION="v3.33.0"
CALICO_BASE="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests"

cd "$(dirname "$0")/.."

for tool in docker kind kubectl; do
  command -v "$tool" > /dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
docker info > /dev/null 2>&1 || { echo "Docker is not running" >&2; exit 1; }

if kind get clusters 2> /dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "cluster $CLUSTER_NAME already exists. Run 'make cluster-down' first." >&2
  exit 1
fi

# Always talk to our own cluster, never to whatever context is current.
k() { kubectl --context "kind-${CLUSTER_NAME}" "$@"; }

start=$SECONDS

echo "==> creating kind cluster $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --config platform/kind/kind-config.yaml
after_create=$SECONDS

echo "==> installing Calico $CALICO_VERSION"
k create -f "${CALICO_BASE}/v3_projectcalico_org.yaml"
k create -f "${CALICO_BASE}/tigera-operator.yaml"
k wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
k create -f "${CALICO_BASE}/custom-resources.yaml"

echo "==> waiting for nodes and DNS"
k wait --for=condition=Ready node --all --timeout=600s
k -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=300s

echo "cluster ready: kind create took $((after_create - start))s, total $((SECONDS - start))s"
