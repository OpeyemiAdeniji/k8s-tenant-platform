#!/usr/bin/env bash
# Install pinned versions of kind, kubectl, helm and the kyverno CLI. Every download is
# checked against its published checksum before it is installed.
# Usage: scripts/install-tools.sh [INSTALL_DIR [TOOL...]]
#   INSTALL_DIR defaults to $HOME/.local/bin.
#   TOOL is kind, kubectl, helm or kyverno. With no TOOL, all four are installed.
# The kyverno version is read from platform/kyverno/app-version.
set -euo pipefail

KIND_VERSION="v0.33.0"
KUBECTL_VERSION="v1.37.1"
HELM_VERSION="v4.3.1"

root="$(cd "$(dirname "$0")/.." && pwd)"
KYVERNO_VERSION="$(tr -d '[:space:]' < "$root/platform/kyverno/app-version")"

dir="${1:-$HOME/.local/bin}"
shift || true
all_tools=(kind kubectl helm kyverno)
selected=("$@")
if [ "${#selected[@]}" -eq 0 ]; then
  selected=("${all_tools[@]}")
fi
for t in "${selected[@]}"; do
  case " ${all_tools[*]} " in
    *" $t "*) ;;
    *) echo "unknown tool: $t (choose from: ${all_tools[*]})" >&2; exit 2 ;;
  esac
done

mkdir -p "$dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

install_kind() {
  echo "==> kind $KIND_VERSION"
  curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
  curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64.sha256sum"
  sha256sum -c kind-linux-amd64.sha256sum
  install -m 0755 kind-linux-amd64 "$dir/kind"
}

install_kubectl() {
  echo "==> kubectl $KUBECTL_VERSION"
  curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
  install -m 0755 kubectl "$dir/kubectl"
}

install_helm() {
  echo "==> helm $HELM_VERSION"
  curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"
  sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"
  tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
  install -m 0755 linux-amd64/helm "$dir/helm"
}

install_kyverno() {
  echo "==> kyverno $KYVERNO_VERSION"
  local base="https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}"
  local archive="kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz"
  curl -fsSLO "${base}/${archive}"
  curl -fsSLO "${base}/checksums.txt"
  grep " ${archive}\$" checksums.txt | sha256sum -c -
  tar -xzf "$archive" kyverno
  install -m 0755 kyverno "$dir/kyverno"
}

for t in "${selected[@]}"; do
  "install_$t"
done

echo "installed into $dir"
for t in "${selected[@]}"; do
  case "$t" in
    kind) "$dir/kind" version ;;
    kubectl) "$dir/kubectl" version --client ;;
    helm) "$dir/helm" version ;;
    kyverno) "$dir/kyverno" version ;;
  esac
done
