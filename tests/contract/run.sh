#!/usr/bin/env bash
# Contract tests.
# - Every file in tests/contract/valid must pass validation.
# - Every file in tests/contract/invalid must fail, and its output must contain
#   the text given on its first line as "# expect: <text>".
set -euo pipefail

cd "$(dirname "$0")/../.."

failures=0

for file in tests/contract/valid/*.yaml; do
  if python3 scripts/validate_tenants.py "$file" > /dev/null; then
    echo "pass  valid    $file"
  else
    echo "FAIL  valid    $file (expected it to pass)"
    failures=$((failures + 1))
  fi
done

for file in tests/contract/invalid/*.yaml; do
  expected="$(sed -n '1s/^# expect: //p' "$file")"
  if [ -z "$expected" ]; then
    echo "FAIL  invalid  $file (line 1 must be '# expect: <text>')"
    failures=$((failures + 1))
    continue
  fi
  if output="$(python3 scripts/validate_tenants.py "$file")"; then
    echo "FAIL  invalid  $file (expected it to fail, but it passed)"
    failures=$((failures + 1))
  elif grep -qF -- "$expected" <<< "$output"; then
    echo "pass  invalid  $file"
  else
    echo "FAIL  invalid  $file (it failed, but not with: $expected)"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures contract test(s) failed"
  exit 1
fi
echo "all contract tests passed"
