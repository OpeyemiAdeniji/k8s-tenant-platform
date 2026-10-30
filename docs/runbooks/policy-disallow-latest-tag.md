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

If the pod is created by a Deployment, the Deployment itself is accepted, and its pods are rejected when the controller creates them. Look at the events of the ReplicaSet (`kubectl describe replicaset`) to see this message.

## If you need an exception

An exception is a `PolicyException` in the namespace `platform-exceptions`, created by the platform team. It must carry the label `cleanup.kyverno.io/ttl` with an absolute date, for example `2026-12-01T000000Z`, and it is deleted by itself at that date. The reasoning and the limits are in `docs/adr/0008-kyverno-cel-policies-and-expiring-exceptions.md`. A way for tenants to request an exception through a pull request does not exist yet.

## Not covered

- The policy checks pods only. Other kinds that start containers directly, such as jobs, are caught when their pods are created.
- Ephemeral containers are not checked.
