#!/usr/bin/env bash
# Install pinned versions of kind, kubectl and helm. Every download is checked
# against its published checksum before it is installed.
# Usage: scripts/install-tools.sh [INSTALL_DIR]   (default: $HOME/.local/bin)
set -euo pipefail

KIND_VERSION="v0.33.0"
KUBECTL_VERSION="v1.37.1"
HELM_VERSION="v4.3.1"

dir="${1:-$HOME/.local/bin}"
mkdir -p "$dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

echo "==> kind $KIND_VERSION"
curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64.sha256sum"
sha256sum -c kind-linux-amd64.sha256sum
install -m 0755 kind-linux-amd64 "$dir/kind"

echo "==> kubectl $KUBECTL_VERSION"
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
install -m 0755 kubectl "$dir/kubectl"

echo "==> helm $HELM_VERSION"
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"
sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"
tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
install -m 0755 linux-amd64/helm "$dir/helm"

echo "installed into $dir"
"$dir/kind" version
"$dir/kubectl" version --client
"$dir/helm" version
