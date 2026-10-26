#!/usr/bin/env bash
# Delete the local kind cluster.
# Usage: scripts/cluster-down.sh (or: make cluster-down)
set -euo pipefail

CLUSTER_NAME="tenant-platform"

kind delete cluster --name "$CLUSTER_NAME"
