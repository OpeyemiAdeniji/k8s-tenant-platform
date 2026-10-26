#!/usr/bin/env bash
# Tests for the tenant chart.
# - Every tenant file must lint and render.
# - Every rendered object must carry the cost label, so showback never has gaps.
# - An unknown size must make the chart fail with a clear message.
# Usage: scripts/chart-test.sh (or: make chart-test)
set -euo pipefail

cd "$(dirname "$0")/.."

command -v helm > /dev/null || { echo "missing tool: helm" >&2; exit 1; }

chart="platform/charts/tenant"
failures=0

for file in tenants/*.yaml; do
  name="$(basename "$file" .yaml)"

  if ! helm lint "$chart" -f "$file" > /dev/null; then
    echo "FAIL  lint     $file"
    failures=$((failures + 1))
    continue
  fi
  if ! rendered="$(helm template "tenant-$name" "$chart" -f "$file")"; then
    echo "FAIL  render   $file"
    failures=$((failures + 1))
    continue
  fi

  objects="$(grep -c '^kind:' <<< "$rendered" || true)"
  labelled="$(grep -c '^    cost-centre:' <<< "$rendered" || true)"
  if [ "$objects" -gt 0 ] && [ "$objects" -eq "$labelled" ]; then
    echo "pass  render   $file ($objects objects, all with the cost label)"
  else
    echo "FAIL  labels   $file ($labelled of $objects objects have the cost label)"
    failures=$((failures + 1))
  fi
done

if output="$(helm template tenant-alpha "$chart" -f tenants/alpha.yaml --set size=huge 2>&1)"; then
  echo "FAIL  unknown size (expected the chart to fail, but it rendered)"
  failures=$((failures + 1))
elif grep -qF "unknown size" <<< "$output"; then
  echo "pass  unknown size is rejected with a clear message"
else
  echo "FAIL  unknown size (it failed, but not with: unknown size)"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures chart test(s) failed"
  exit 1
fi
echo "all chart tests passed"
