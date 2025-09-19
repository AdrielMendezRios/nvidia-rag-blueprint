set -e # exit on any error
set -u # exit on undefined vars
set -o pipefail # exit on pipe failures

# Check required helm repositories
echo "Checking required helm repositories..."
if ! helm repo list | grep -q "minio"; then 
  echo "Error: minio helm repo not found. Run: helm repo add minio https://charts.min.io/"
  exit 1
fi

if ! helm repo list | grep -q "bitnami"; then
  echo "Error: bitnami helm repo not found. Run: helm repo add bitnami https://charts.bitnami.com/bitnami"
  exit 1
fi
echo "Required helm repos found!"

# # Check if the namespaces exists and handle it
# echo "Setting up namespace..."
# if oc get project scc-test >/dev/null 2>&1; then
#   echo "Warning: scc-test namespace already exists. Deleting and recreating..."
#   oc delete project scc-test
#   # wait for namespace to be fully deleted
#   while oc get project scc-test >/dev/null 2>&1; do
#     echo "Waiting for namespace deletion"
#     sleep 5
#   done
# fi

# Check if NGC secret is set
echo "Looking for NGC secret"
if [ -z "${NGC_API_KEY:-}" ]; then
  echo "Error: NGC_API_KEY environment variable is not set"
  exit 1
fi

# echo "Creating scc-test namespace"
# oc new-project scc-test
# echo "Namespace scc-test created!"

# echo "Waiting for dependencies to be ready"
# helm install rag-minio minio/minio -n scc-test \
#   --set mode=standalone \
#   --set fullnameOverride=rag-minio \
#   --set rootUser=minioadmin \
#   --set rootPassword=minioadmin \
#   --set persistence.enabled=false \
#   --set resources.requests.memory=512Mi \
#   --set resources.limits.memory=1Gi

# helm upgrade -i rag-redis bitnami/redis -n scc-test \
#   --set auth.enabled=false \
#   --set master.persistence.enabled=false \
#   --set replica.persistence.enabled=false

# sleep 45
# echo "Dependencies should be ready"

echo "Installing RAG server with SCC Configurations"
helm upgrade -i rag ./rag-server -n scc-test \
  --values rag-server/values-openshift.yaml \
  --set imagePullSecret.password="${NGC_API_KEY}" \
  --set ngcApiSecret.password="${NGC_API_KEY}" \
  --set frontend.route.host="" \
  --set appName="rag-server" \
  --set namespace="scc-test" \
  --timeout=10m
