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

# The kyverno CLI is pinned in platform/kyverno/app-version. The chart must install the same version.
chart_app="$(helm show chart kyverno/kyverno --version "$VERSION" | awk '/^appVersion:/ {print $2}' | tr -d '"')"
want_app="$(tr -d '[:space:]' < platform/kyverno/app-version)"
if [ "${chart_app#v}" != "${want_app#v}" ]; then
  echo "chart $VERSION installs Kyverno '${chart_app:-unknown}', but platform/kyverno/app-version says $want_app" >&2
  exit 1
fi

start=$SECONDS
kubectl --context "$CONTEXT" apply -f platform/kyverno/cleanup-clusterrole.yaml -f platform/kyverno/cleanup-clusterrolebinding.yaml
echo "==> installing Kyverno chart $VERSION"
echo "    Helm waits for the pods and prints nothing meanwhile (up to about 3 minutes). Do not press Ctrl+C: it leaves the release in a pending state."
helm upgrade --install kyverno kyverno/kyverno \
  --version "$VERSION" \
  --namespace kyverno --create-namespace \
  --kube-context "$CONTEXT" \
  --values platform/kyverno/values.yaml \
  --wait --timeout 10m

kubectl --context "$CONTEXT" apply -f platform/kyverno/platform-exceptions-namespace.yaml
echo "==> applying the policies"
# Helm --wait returns when the deployment is ready, and in one CI run the next command ran 70 ms later and
# got "connection refused" from the service. Wait until the service has an address behind it first.
kubectl --context "$CONTEXT" -n kyverno wait --for=condition=Available deployment/kyverno-admission-controller --timeout=120s
for _ in $(seq 1 24); do
  addresses="$(kubectl --context "$CONTEXT" -n kyverno get endpointslices -l kubernetes.io/service-name=kyverno-svc -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{" "}{.addresses[0]}{"\n"}{end}' 2> /dev/null | grep -E '^true ' || true)"
  [ -n "$addresses" ] && break
  sleep 5
done
[ -n "${addresses:-}" ] || { echo "kyverno-svc has no ready address after 2 minutes" >&2; exit 1; }
# The webhook that validates policies is served by the admission controller. Helm --wait returns when
# the deployment is ready, but on a cold start the webhook can still refuse connections for a while
# (seen once in CI). So the apply is retried, with a limit.
applied=0
for attempt in $(seq 1 24); do
  if out="$(kubectl --context "$CONTEXT" apply -f platform/policies/*.yaml 2>&1)"; then
    echo "$out"
    applied=1
    break
  fi
  echo "policy apply failed (attempt $attempt of 24), retrying in 5 s: $(head -c 160 <<< "$out")"
  sleep 5
done
[ "$applied" -eq 1 ] || { echo "the policies were not applied after 24 attempts" >&2; echo "$out" >&2; exit 1; }
for p in $(kubectl --context "$CONTEXT" get validatingpolicies.policies.kyverno.io -o name); do
  kubectl --context "$CONTEXT" wait --for=jsonpath='{.status.conditionStatus.ready}'=true "$p" --timeout=120s
done

echo "kyverno ready: $((SECONDS - start)) s"
kubectl --context "$CONTEXT" -n kyverno get pods
