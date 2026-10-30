#!/usr/bin/env bash
# Tests for the Kyverno policies in platform/policies.
#
# 1. kyverno test passes. --warnings-as-errors makes a deprecated policy type fail the run.
# 2. The table has the expected number of rows, and the only Excluded rows are the
#    outside- resources. The CLI reports an excluded resource as a pass for ANY expectation,
#    so without this check a broken scope would give a false green.
# 3. Every fail- row carries the fix and the runbook link in its message.
# 4. Every runbook that a policy links to exists in the repository.
# 5. Self-check: with the latest check removed from a copy of the policies, the same tests
#    must fail for exactly the two pods that carry the tag latest. This proves that the suite
#    can fail.
#
# Update the three numbers below when test resources are added or removed.
# Usage: scripts/policy-test.sh (or: make policy-test)
# POLICIES_DIR can point at another copy of the policies, to try that a check can fail.
set -euo pipefail

cd "$(dirname "$0")/.."

POLICIES_DIR="${POLICIES_DIR:-platform/policies}"
EXPECTED_ROWS=8
EXPECTED_FAIL_ROWS=4
EXPECTED_OUTSIDE_ROWS=1
HELPERS="${CHART_HELPERS:-platform/charts/tenant/templates/_helpers.tpl}"

command -v kyverno > /dev/null || { echo "missing tool: kyverno" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "pass  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# Runs the tests of a directory and prints the exit code. The table goes to the file.
run_tests() {
  local status=0
  kyverno test "$1" --detailed-results --warnings-as-errors > "$2" 2>&1 || status=$?
  echo "$status"
}

echo "== the real tests"
status="$(run_tests "$POLICIES_DIR/tests" "$work/real.out")"
if [ "$status" -eq 0 ]; then
  pass "kyverno test passed with --warnings-as-errors"
else
  fail "kyverno test exited with code $status"
  head -c 3000 "$work/real.out"
fi

rows="$(awk -F'│' 'NF > 6 && $5 ~ /v1\/Pod\// { n++ } END { print n + 0 }' "$work/real.out")"
if [ "$rows" -eq "$EXPECTED_ROWS" ]; then
  pass "the table has $rows rows"
else
  fail "the table has $rows rows, expected $EXPECTED_ROWS"
fi

read -r outside_excluded other_excluded < <(awk -F'│' 'NF > 6 && $7 ~ /Excluded/ { if ($5 ~ /\/outside-/) o++; else b++ } END { print o + 0, b + 0 }' "$work/real.out")
if [ "$other_excluded" -eq 0 ] && [ "$outside_excluded" -eq "$EXPECTED_OUTSIDE_ROWS" ]; then
  pass "only the $outside_excluded outside- resource is excluded"
else
  fail "excluded rows: $outside_excluded outside- (expected $EXPECTED_OUTSIDE_ROWS) and $other_excluded others (expected 0)"
fi

read -r fail_rows fail_without_link < <(awk -F'│' 'NF > 6 && $5 ~ /\/fail-/ { n++; if ($8 ~ /Fix:/ && $8 ~ /Runbook:/) ok++ } END { print n + 0, n - ok }' "$work/real.out")
if [ "$fail_rows" -eq "$EXPECTED_FAIL_ROWS" ] && [ "$fail_without_link" -eq 0 ]; then
  pass "$fail_rows failing pods, each with the fix and the runbook link"
else
  fail "failing pods: $fail_rows (expected $EXPECTED_FAIL_ROWS), $fail_without_link without the fix and the runbook link"
fi

links="$(grep -ho 'docs/runbooks/[A-Za-z0-9._-]*\.md' "$POLICIES_DIR"/*.yaml | sort -u || true)"
if [ -z "$links" ]; then
  fail "no runbook link found in the policies"
else
  for f in $links; do
    if [ -f "$f" ]; then
      pass "runbook exists: $f"
    else
      fail "runbook is missing: $f"
    fi
  done
fi

echo "== the label that the policy selects on must be the one that the chart sets"
selector_label="$(awk '/namespaceSelector:/ {f=1} f && /matchLabels:/ {g=1; next} g && NF {gsub(/^ +/, ""); print; exit}' "$POLICIES_DIR/disallow-latest-image-tag.yaml")"
if [ -n "$selector_label" ] && grep -qF -- "$selector_label" "$HELPERS"; then
  pass "the chart sets the label that the policy selects on: $selector_label"
else
  fail "the policy selects on '$selector_label', which is not in $HELPERS"
fi

echo "== self-check: the suite must fail when the latest check is removed"
cp -r "$POLICIES_DIR" "$work/policies"
python3 - "$work/policies/disallow-latest-image-tag.yaml" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()
weak = " && " + chr(33) + "i.endsWith(':latest')"
assert s.count(weak) == 1, "the latest check was not found exactly once"
p.write_text(s.replace(weak, ""))
PY
status="$(run_tests "$work/policies/tests" "$work/weak.out")"
failing="$(awk -F'│' 'NF > 6 && $6 ~ /Fail/ { gsub(/ +/, "", $5); n = split($5, p, "/"); print p[n] }' "$work/weak.out" | sort | paste -sd' ' -)"
if [ "$status" -ne 0 ] && [ "$failing" = "fail-init-container-latest fail-latest-tag" ]; then
  pass "without the latest check, exactly fail-latest-tag and fail-init-container-latest fail"
else
  fail "weakened copy: exit code $status, failing rows: '$failing'"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures policy check(s) failed"
  exit 1
fi
echo "all policy checks passed"
