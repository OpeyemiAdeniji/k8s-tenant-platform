# Runbook: a pod was rejected because of its image tag

## What you see

    Error from server: error when creating "pod.yaml": admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy disallow-latest-image-tag failed: Image busybox:latest uses the tag latest or has no tag. Fix: pin the image to a version, for example busybox:1.36, or to a digest. Runbook: <this page>

The first part of the text comes from Kubernetes and Kyverno. The part after `failed:` is the message of the policy.

## Why

The policy `disallow-latest-image-tag` applies to pods in tenant namespaces. It rejects an image that has the tag `latest`, or no tag, because both mean "whatever is current". Such an image can change under a running workload, and the same manifest then runs different code on different days. It also checks init containers.

## How to fix it

Pin every image to a version or to a digest:

| Not accepted | Accepted |
|---|---|
| `busybox` | `busybox:1.36` |
| `busybox:latest` | `busybox@sha256:<digest>` |
| `registry.example.com:5000/team/app` (the `:5000` is a port, not a tag) | `registry.example.com:5000/team/app:1.2.3` |

A Deployment or CronJob that uses `latest` is rejected when it is created or updated, with the same message. A Deployment that already ran `latest` before the policy is accepted, and its new pods are rejected when the controller creates them. Look at the events of the ReplicaSet (`kubectl describe replicaset`) to see this message.

## If you need an exception

An exception is a `PolicyException` in the namespace `platform-exceptions`, created by the platform team. It must carry the label `cleanup.kyverno.io/ttl` with an absolute date, for example `2026-12-01T000000Z`, and it is deleted by itself at that date. The reasoning and the limits are in `docs/adr/0008-kyverno-cel-policies-and-expiring-exceptions.md`. A way for tenants to request an exception through a pull request does not exist yet.

## Not covered

- The policy is written for pods. Kyverno generates the same rule for Deployments, ReplicaSets, StatefulSets, DaemonSets, Jobs and CronJobs. The live tests cover pods, Deployments and CronJobs.
- If Kyverno is down, the webhook fails closed: new pods in tenant namespaces are rejected until Kyverno is back. Other namespaces are not affected, and the `kyverno` and `kube-system` namespaces are excluded, so Kyverno can always be repaired. This is not tested live.
- Ephemeral containers are not checked.

## Workloads that already run latest

The policy applies to updates as well as creations, but it only blocks an image that was not in the
object before the update. A workload that already runs `latest` keeps running and accepts unrelated
edits, such as a label or an annotation.

A new pod is a creation, so it is still denied. Scaling up, a node drain, or a restart that recreates
a pod fails until the image is pinned. A Deployment shows this as a ReplicaFailure on its ReplicaSet.
Fix: pin the image to a version or a digest.
