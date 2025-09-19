#!/bin/bash

# Usage: cleanup.sh [namespace]
# Default namespace: scc-test

NAMESPACE="${1:-scc-test}"

echo "Starting cleanup for namespace: $NAMESPACE"

# Check if namespace exists
if ! oc get project "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace $NAMESPACE does not exist. Nothing to clean up."
  exit 0
fi

# # Uninstall Helm releases first
# echo "Uninstalling Helm releases..."
# helm uninstall rag-server-scc -n "$NAMESPACE" --ignore-not-found || true
# helm uninstall rag-redis -n "$NAMESPACE" --ignore-not-found || true
# #helm uninstall rag-minio -n "$NAMESPACE" --ignore-not-found || true

# Clean up any remaining resources
echo "Cleaning up remaining resources..."
# oc delete pvc --all -n "$NAMESPACE" --ignore-not-found=true
# oc delete secrets --all -n "$NAMESPACE" --ignore-not-found=true

# Delete the namespace
echo "Deleting namespace: $NAMESPACE"
oc delete project "$NAMESPACE"

echo "Cleanup completed for namespace: $NAMESPACE"
