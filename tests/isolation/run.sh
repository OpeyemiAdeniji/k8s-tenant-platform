#!/usr/bin/env bash
# Isolation tests for the tenant platform.
#
# They run against the local cluster (make cluster-up, then make tenants-apply) and
# perform real actions. Every block test has a matching "must work" test, and every
# block test checks the text of the refusal, so a broken network, a missing pod or an
# unrelated error cannot make it pass by accident.
#
# Usage: tests/isolation/run.sh (or: make test-isolation)
set -uo pipefail

cd "$(dirname "$0")/../.."

CONTEXT="${KUBE_CONTEXT:-kind-tenant-platform}"
A="tenant-alpha"
B="tenant-bravo"
IMAGE="busybox:1.36"
SMALL='resources: {requests: {cpu: 50m, memory: 32Mi}, limits: {cpu: 100m, memory: 64Mi}}'
SERVER_CMD='["sh","-c","echo ok > /tmp/index.html && exec httpd -f -p 8080 -h /tmp"]'
SLEEP_CMD='["sleep","3600"]'
failures=0
ip_b1=""
n1=""
n2=""

k() { kubectl --context "$CONTEXT" "$@"; }
as_alpha() { k --as=tester --as-group=alpha-admins "$@"; }
as_bravo() { k --as=tester --as-group=bravo-admins "$@"; }
as_alpha_viewer() { k --as=tester --as-group=alpha-viewers "$@"; }

pass() { echo "pass  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# expect_ok NAME COMMAND... : the command must succeed.
expect_ok() {
  local name="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    pass "$name"
  else
    fail "$name (the command failed, but it must succeed)"
  fi
}

# expect_blocked NAME TEXT COMMAND... : the command must fail, and its output must contain TEXT.
expect_blocked() {
  local name="$1" text="$2" out
  shift 2
  if out="$("$@" 2>&1)"; then
    fail "$name (it succeeded, but it must be blocked)"
  elif grep -qiF -- "$text" <<< "$out"; then
    pass "$name"
  else
    fail "$name (it failed, but not with: $text)"
    echo "      output: $(head -c 300 <<< "$out")"
  fi
}

# apply_pod NAMESPACE NAME COMMAND_JSON [RESOURCES_YAML] [RESTART_POLICY] [NODE]
# Pods follow the restricted Pod Security level, so the namespaces accept them.
apply_pod() {
  local ns="$1" name="$2" cmd="$3" resources="${4:-}" restart="${5:-Always}" node="${6:-}" selector=""
  if [ -n "$node" ]; then
    selector="nodeSelector: {kubernetes.io/hostname: $node}"
  fi
  k -n "$ns" apply -f - <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels:
    app: $name
    suite: isolation
spec:
  restartPolicy: $restart
  $selector
  terminationGracePeriodSeconds: 0
  containers:
    - name: main
      image: $IMAGE
      command: $cmd
      $resources
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
        seccompProfile:
          type: RuntimeDefault
MANIFEST
}

# fetch NAMESPACE CLIENT_POD IP : the client pod requests the page of the server at IP.
fetch() { k -n "$1" exec "$2" -- wget -qO- -T 3 "http://$3:8080"; }

cleanup() {
  local ns
  for ns in "$A" "$B"; do
    k -n "$ns" delete pods,services,secrets -l suite=isolation --ignore-not-found > /dev/null 2>&1
  done
}

wait_quota_free() {
  local used
  for _ in $(seq 1 30); do
    used="$(k -n "$A" get resourcequota tenant-quota -o jsonpath='{.status.used.requests\.cpu}' 2> /dev/null)"
    if [ -z "$used" ] || [ "$used" = "0" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if ! k get namespace "$A" "$B" > /dev/null 2>&1; then
  echo "tenants not found on context $CONTEXT. Run: make cluster-up && make tenants-apply" >&2
  exit 2
fi

trap cleanup EXIT
cleanup

echo "== access: real requests as tenant identities"
k -n "$A" create secret generic iso-secret --from-literal=key=alpha > /dev/null
k -n "$A" label secret iso-secret suite=isolation > /dev/null
k -n "$B" create secret generic iso-secret --from-literal=key=bravo > /dev/null
k -n "$B" label secret iso-secret suite=isolation > /dev/null

expect_ok "alpha admin reads the alpha secret" as_alpha -n "$A" get secret iso-secret
expect_ok "bravo admin reads the bravo secret" as_bravo -n "$B" get secret iso-secret
expect_blocked "alpha admin cannot read the bravo secret" "forbidden" as_alpha -n "$B" get secret iso-secret
expect_blocked "alpha admin cannot list secrets in bravo" "forbidden" as_alpha -n "$B" get secrets
expect_blocked "bravo admin cannot read the alpha secret" "forbidden" as_bravo -n "$A" get secret iso-secret
expect_blocked "alpha viewer cannot read the alpha secret" "forbidden" as_alpha_viewer -n "$A" get secret iso-secret

echo "== platform controls cannot be changed by the tenant (server-side dry run, nothing is changed)"
expect_blocked "alpha admin cannot delete its default-deny policy" "forbidden" as_alpha -n "$A" delete networkpolicy default-deny-all --dry-run=server
expect_blocked "alpha admin cannot delete its quota" "forbidden" as_alpha -n "$A" delete resourcequota tenant-quota --dry-run=server
expect_blocked "alpha admin cannot delete its limit range" "forbidden" as_alpha -n "$A" delete limitrange tenant-limits --dry-run=server
expect_blocked "alpha admin cannot create role bindings" "forbidden" as_alpha -n "$A" create rolebinding probe --role=tenant-admin --group=other --dry-run=server
expect_blocked "alpha admin cannot loosen the Pod Security level" "forbidden" as_alpha label namespace "$A" pod-security.kubernetes.io/enforce=privileged --overwrite --dry-run=server

echo "== network isolation between tenants: same node and across nodes (pods are reached by IP, so DNS is not involved)"
mapfile -t workers < <(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
if [ "${#workers[@]}" -lt 2 ]; then
  fail "network: two worker nodes are needed, found ${#workers[@]}"
else
  n1="${workers[0]}"
  n2="${workers[1]}"
  echo "      node 1 is $n1, node 2 is $n2"
  for ns in "$A" "$B"; do
    for i in 1 2; do
      node="${workers[$((i - 1))]}"
      apply_pod "$ns" "iso-server-$i" "$SERVER_CMD" "$SMALL" Always "$node" > /dev/null
      apply_pod "$ns" "iso-client-$i" "$SLEEP_CMD" "$SMALL" Always "$node" > /dev/null
    done
  done
  network_ready=1
  for ns in "$A" "$B"; do
    k -n "$ns" wait --for=condition=Ready pod -l suite=isolation --timeout=180s > /dev/null 2>&1 || network_ready=0
  done
  if [ "$network_ready" -ne 1 ]; then
    fail "network: the test pods did not become ready"
  else
    placed=1
    for ns in "$A" "$B"; do
      for i in 1 2; do
        for role in server client; do
          want="${workers[$((i - 1))]}"
          got="$(k -n "$ns" get pod "iso-$role-$i" -o jsonpath='{.spec.nodeName}')"
          if [ "$got" != "$want" ]; then
            placed=0
            echo "      iso-$role-$i in $ns is on '$got', expected '$want'"
          fi
        done
      done
    done
    if [ "$placed" -eq 1 ]; then
      pass "all eight test pods run on the intended nodes"
    else
      fail "network: some test pods are not on the intended nodes"
    fi

    ip_a1="$(k -n "$A" get pod iso-server-1 -o jsonpath='{.status.podIP}')"
    ip_a2="$(k -n "$A" get pod iso-server-2 -o jsonpath='{.status.podIP}')"
    ip_b1="$(k -n "$B" get pod iso-server-1 -o jsonpath='{.status.podIP}')"
    ip_b2="$(k -n "$B" get pod iso-server-2 -o jsonpath='{.status.podIP}')"

    expect_ok "alpha, same node: client 1 reaches server 1" fetch "$A" iso-client-1 "$ip_a1"
    expect_ok "alpha, across nodes: client 2 reaches server 1" fetch "$A" iso-client-2 "$ip_a1"
    expect_ok "bravo, same node: client 2 reaches server 2" fetch "$B" iso-client-2 "$ip_b2"
    expect_ok "bravo, across nodes: client 1 reaches server 2" fetch "$B" iso-client-1 "$ip_b2"
    expect_ok "alpha pods can resolve names (DNS is allowed)" k -n "$A" exec iso-client-1 -- nslookup kubernetes.default.svc.cluster.local

    expect_blocked "alpha cannot reach bravo on node 1 (same node)" "timed out" fetch "$A" iso-client-1 "$ip_b1"
    expect_blocked "alpha cannot reach bravo on node 2 (same node)" "timed out" fetch "$A" iso-client-2 "$ip_b2"
    expect_blocked "alpha on node 1 cannot reach bravo on node 2 (across nodes)" "timed out" fetch "$A" iso-client-1 "$ip_b2"
    expect_blocked "alpha on node 2 cannot reach bravo on node 1 (across nodes)" "timed out" fetch "$A" iso-client-2 "$ip_b1"
    expect_blocked "bravo cannot reach alpha on node 1 (same node)" "timed out" fetch "$B" iso-client-1 "$ip_a1"
    expect_blocked "bravo cannot reach alpha on node 2 (same node)" "timed out" fetch "$B" iso-client-2 "$ip_a2"
    expect_blocked "bravo on node 1 cannot reach alpha on node 2 (across nodes)" "timed out" fetch "$B" iso-client-1 "$ip_a2"
    expect_blocked "bravo on node 2 cannot reach alpha on node 1 (across nodes)" "timed out" fetch "$B" iso-client-2 "$ip_a1"
  fi
fi

echo "== noisy neighbour: alpha burns resources, bravo keeps working"
apply_pod "$A" hog-cpu '["sh","-c","for i in 1 2; do (while :; do :; done) & done; wait"]' \
  'resources: {requests: {cpu: 100m, memory: 32Mi}, limits: {cpu: 500m, memory: 64Mi}}' Always "$n1" > /dev/null
apply_pod "$A" hog-mem '["sh","-c","tail /dev/zero"]' "$SMALL" Never "$n1" > /dev/null

if k -n "$A" wait --for=condition=Ready pod/hog-cpu --timeout=120s > /dev/null 2>&1; then
  sleep 5
  s0="$(k -n "$A" exec hog-cpu -- cat /sys/fs/cgroup/cpu.stat 2> /dev/null)"
  t0="$(date +%s%N)"
  sleep 10
  s1="$(k -n "$A" exec hog-cpu -- cat /sys/fs/cgroup/cpu.stat 2> /dev/null)"
  t1="$(date +%s%N)"
  u0="$(awk '/^usage_usec/ {print $2}' <<< "$s0")"
  u1="$(awk '/^usage_usec/ {print $2}' <<< "$s1")"
  if [ -z "$u0" ] || [ -z "$u1" ]; then
    fail "noisy neighbour: could not read /sys/fs/cgroup/cpu.stat in the pod (cgroup v2 is expected)"
  else
    used="$(awk -v a="$u0" -v b="$u1" -v ta="$t0" -v tb="$t1" 'BEGIN { printf "%.2f", ((b - a) / 1000000) / ((tb - ta) / 1000000000) }')"
    if awk -v u="$used" 'BEGIN { exit !(u >= 0.30 && u <= 0.60) }'; then
      pass "the CPU hog used $used CPUs over about 10 s, near its limit of 0.5"
    else
      fail "the CPU hog used $used CPUs, but the expected range is 0.30 to 0.60 (limit 0.5)"
    fi
    throttled="$(awk '/^nr_throttled/ {print $2}' <<< "$s1")"
    if [ "${throttled:-0}" -gt 0 ]; then
      pass "the kernel throttled the CPU hog ($throttled throttled periods)"
    else
      fail "the CPU hog was never throttled"
    fi
  fi
else
  fail "noisy neighbour: the CPU hog did not become ready"
fi

reason=""
for _ in $(seq 1 45); do
  reason="$(k -n "$A" get pod hog-mem -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2> /dev/null)"
  if [ -n "$reason" ]; then
    break
  fi
  sleep 2
done
exit_code="$(k -n "$A" get pod hog-mem -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2> /dev/null)"
if [ "$reason" = "OOMKilled" ]; then
  pass "the memory hog was killed at its memory limit (OOMKilled, exit code $exit_code)"
elif [ "$exit_code" = "137" ] \
  && [ "$(k -n "$A" get pod hog-mem -o jsonpath='{.status.phase}' 2> /dev/null)" = "Failed" ] \
  && [ "$(k -n "$A" get pod hog-mem -o jsonpath='{.status.reason}' 2> /dev/null)" != "Evicted" ]; then
  pass "the memory hog was killed by SIGKILL (exit code 137) and not evicted; this cluster reports the reason '$reason' and not OOMKilled"
else
  fail "the memory hog ended with reason '${reason:-still running}' and exit code '${exit_code:-none}', expected OOMKilled or exit code 137 without eviction"
  echo "      state: $(k -n "$A" get pod hog-mem -o jsonpath='{.status.containerStatuses[0].state}' 2> /dev/null | head -c 400)"
  echo "      logs: $(k -n "$A" logs hog-mem 2>&1 | tail -3 | tr '\n' ' ')"
fi

if [ -n "$ip_b1" ]; then
  restarts="$(k -n "$B" get pod iso-server-1 -o jsonpath='{.status.containerStatuses[0].restartCount}')"
  expect_ok "the bravo server on the same node as the hogs still answers" fetch "$B" iso-client-1 "$ip_b1"
  if [ "$restarts" = "0" ]; then
    pass "the bravo server did not restart"
  else
    fail "the bravo server restarted $restarts time(s)"
  fi
else
  fail "noisy neighbour: no bravo server to check"
fi

echo "== quota and limits in tenant-alpha (small tier)"
cleanup
if ! wait_quota_free; then
  fail "quota: the quota did not return to zero after cleanup"
fi
BIG='resources: {requests: {cpu: 300m, memory: 64Mi}, limits: {cpu: 300m, memory: 64Mi}}'
TOO_BIG='resources: {requests: {cpu: 100m, memory: 64Mi}, limits: {cpu: "2", memory: 64Mi}}'
expect_ok "the first pod (300m of 500m CPU requests) is accepted" apply_pod "$A" quota-a "$SLEEP_CMD" "$BIG"
expect_blocked "a second pod is rejected because it exceeds the quota" "exceeded quota" apply_pod "$A" quota-b "$SLEEP_CMD" "$BIG"
expect_blocked "a NodePort service is rejected" "exceeded quota" k -n "$A" create service nodeport iso-nodeport --tcp=80:80
expect_blocked "a LoadBalancer service is rejected" "exceeded quota" k -n "$A" create service loadbalancer iso-lb --tcp=80:80
expect_blocked "a container above the tier maximum is rejected" "maximum cpu usage per Container" apply_pod "$A" too-big "$SLEEP_CMD" "$TOO_BIG"

cleanup
wait_quota_free > /dev/null
apply_pod "$A" default-pod "$SLEEP_CMD" > /dev/null
default_limit="$(k -n "$A" get pod default-pod -o jsonpath='{.spec.containers[0].resources.limits.memory}')"
if [ "$default_limit" = "256Mi" ]; then
  pass "a pod without resources receives the default limit (256Mi)"
else
  fail "a pod without resources received limit '$default_limit', expected 256Mi"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures isolation test(s) failed"
  exit 1
fi
echo "all isolation tests passed"
echo "Limits: the nodes are containers on one machine and share its CPU and memory, so the"
echo "noisy neighbour tests show that pod limits are enforced, not how a full node behaves."
echo "The network checks show that traffic between two tenants is blocked, not whether the"
echo "ingress rules or the egress rules did it, and they do not cover every possible path."
