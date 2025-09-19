set -e # exit on any error
set -u # exit on undefined vars
set -o pipefail # exit on pipe failures

#Create results directory and timestamp
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M")
RESULTS_DIR="cv-results"
RESULT_FILE="${RESULTS_DIR}/cv-results-${TIMESTAMP}.txt"
mkdir -p "$RESULTS_DIR"

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

# Check if the namespaces exists and handle it
echo "Setting up namespace..."
if oc get project cv-test >/dev/null 2>&1; then
  echo "Warning: cv-test namespace already exists. Deleting and recreating..."
  oc delete project cv-test
  # wait for namespace to be fully deleted
  while oc get project cv-test >/dev/null 2>&1; do
    echo "Waiting for namespace deletion"
    sleep 5
  done
fi

# Check if NGC secret is set
echo "Looking for NGC secret"
if [ -z "${NGC_API_KEY:-}" ]; then
  echo "Error: NGC_API_KEY environment variable is not set"
  exit 1
fi

echo "Creating cv-test namespace"
oc new-project cv-test
echo "Namespace cv-test created!"

# looks like subcharts (zipkin,nv-ingest,minio,etcd) are getting SCC errors. grant to all for now. must uptade subcharts eventually.
echo "Applying anyuid SCC for all service accounts in namespace..."
oc adm policy add-scc-to-group anyuid system:serviceaccounts:cv-test
echo "SCC applied"
echo "Sleeping for scc to propagate"
sleep 10
echo "SCC should have applied"

echo "Waiting for dependencies to be ready"
helm install rag-minio minio/minio -n cv-test \
  --set mode=standalone \
  --set fullnameOverride=rag-minio \
  --set rootUser=minioadmin \
  --set rootPassword=minioadmin \
  --set persistence.enabled=false \
  --set resources.requests.memory=512Mi \
  --set resources.limits.memory=1Gi

helm install rag-redis bitnami/redis -n cv-test \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.persistence.enabled=false

sleep 45
echo "Dependencies should be ready"

echo "Running chart-verifier..."
echo "Results will be saved to: $RESULT_FILE"
chart-verifier verify ./rag-server \
  --chart-values rag-server/values-openshift.yaml \
  --chart-values rag-server/values-cv-test.yaml \
  --helm-install-timeout 20m \
  --timeout 30m \
  --namespace cv-test 2>&1 | tee "$RESULT_FILE"
echo "Chart-verifier completed!" 

  
echo "Starting cleanup..."

# clean up any remaining resources chart-verifier missed
oc delete pvc --all -n cv-test --ignore-not-found=true
oc delete secrets --all -n cv-test --ignore-not-found=true

# Uninstall our external dependencies
helm uninstall rag-redis -n cv-test --ignore-not-found || true
helm uninstall rag-minio -n cv-test --ignore-not-found || true

# Delete the namespace
echo "Deleting cv-test namespace"
oc delete project cv-test

echo "Clean up completed!"
echo "Results saved to: $RESULT_FILE"
