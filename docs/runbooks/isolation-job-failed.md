# Runbook: the isolation job failed

The `isolation` job builds the local cluster on a GitHub runner and runs the isolation tests. It uses the same scripts as a local run: `make cluster-up`, `make tenants-apply` and `make test-isolation`. This runbook lists the first checks, and every failure of the job that has really happened.

## First checks

Find the run and the step that failed:

    RUN_ID=$(gh run list --branch <branch> --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {job: .name, failed_steps: [.steps[] | select(.conclusion=="failure") | .name]}'

Read the failed step:

    gh run view "$RUN_ID" --log-failed | tail -80

Read the diagnostics, which the last step of the job prints when anything failed (nodes, pods, events and the lines of the kernel log about memory kills). That step succeeds, so `--log-failed` does not show it:

    gh run view "$RUN_ID" --log | awk -F'\t' '$2 ~ /Show the cluster state/ {print $3}' | sed 's/^[^ ]* //'

Then compare with a local run of `make test-isolation`, which prints the same check lines.

## Environment differences observed between the runner and the local machine

| Item | GitHub runner | Local machine |
|---|---|---|
| Kernel | 7.0.0-1017-azure | 6.18.54.1-microsoft-standard-WSL2 |
| Kubernetes, containerd | v1.37.0, 2.3.4 | v1.37.0, 2.3.4 |
| Reason reported for a pod killed at its memory limit | `Error` (exit code 137) | `OOMKilled` (exit code 137) |

## Failure log

### 2026-10-26: the memory hog check failed on the runner

- **Symptom:** 26 of 27 checks passed. The failing line was `FAIL the memory hog ended with reason 'Error', expected OOMKilled`. First failing run: 40332877934 at commit 116f602.
- **Evidence:** a second run (40337348572, commit 792a0d1) printed the container state, which had `exitCode: 137` and `reason: "Error"`. The kernel log of the runner showed `oom-kill:constraint=CONSTRAINT_MEMCG` and `Memory cgroup out of memory: Killed process ... (tail)` with about 63 MiB of resident memory, which is the 64Mi limit of the pod. The local machine showed the same kill, with `OOMKilled` as the reason.
- **Cause of the red job:** the check required the reason `OOMKilled`. The limit was enforced on the runner, but this cluster reported the reason `Error`.
- **Why the label differs:** unknown. The kernels differ and the cgroup paths in the kernel log differ. Neither was investigated.
- **Fix:** the check accepts the reason `OOMKilled`, or exit code 137 with the pod in phase `Failed` and not evicted. It no longer separates a SIGKILL from other causes by itself. If the hog never stopped, the check would still fail, and the later checks (the bravo server must answer and must not restart) would still detect collateral damage. The kernel log is the evidence for the kill itself.
- **Result:** run 40339094821 at commit cb4bf80 passed. Its memory check line was: `pass  the memory hog was killed by SIGKILL (exit code 137) and not evicted; this cluster reports the reason 'Error' and not OOMKilled`

## Known gaps

- **Pod placement is left to the scheduler, so cross-node coverage is accidental.** The test does not choose nodes. On the local machine and in the first CI run, all four test pods ran on `tenant-platform-worker2`. In run 40339094821 the diagnostic line was: `nodes: alpha server on tenant-platform-worker2, alpha client on tenant-platform-worker2, bravo server on tenant-platform-worker2, bravo client on tenant-platform-worker`. So the network checks sometimes cross nodes and sometimes do not. The planned fix places the pods on named nodes and tests both cases.

## Not seen yet

These are expected possibilities and not observations. Do not treat them as verified.

- A pull of the `busybox:1.36` image from Docker Hub could be rate limited on a runner.
- The CPU check expects between 0.30 and 0.60 CPUs for a hog with a limit of 0.5, and a busy runner could fall below that range.
