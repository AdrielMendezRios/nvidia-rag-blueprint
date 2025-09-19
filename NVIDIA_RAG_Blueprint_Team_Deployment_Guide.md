# How to Deploy Our NVIDIA RAG Blueprint Fork on OpenShift

**What this is**: A practical guide to get our modified NVIDIA RAG Blueprint running on OpenShift  
**Target**: mostly for me. which is why its so verbose.
**Result**: Working RAG system with 13 pods, frontend UI, and basic document upload

---

## What We Built

We took NVIDIA's RAG Blueprint and made it work on OpenShift without GPUs. Here's what you get:

- ✅ **Frontend UI** - Nice React interface for RAG queries
- ✅ **Document Upload** - Can upload docs (they get queued for processing)
- ✅ **API Endpoints** - RAG server + ingestor server with Swagger docs
- ✅ **Vector Database** - Milvus running in CPU-only mode
- ✅ **Storage & Caching** - MinIO + Redis for the backend
- ✅ **Observability** - Zipkin tracing and OpenTelemetry

**What doesn't work**: Actual AI inference (needs GPU NIMs or external LLM services)

---

## Prerequisites

### 1. OpenShift Access
```bash
# Make sure you can connect
oc whoami
oc get nodes
```

### 2. NGC API Key
Get your API key from https://build.nvidia.com (not the org.ngc.nvidia.com one - that one doesn't work):
```bash
export NGC_API_KEY="nvapi-your-key-here"
```

### 3. Our Fork
Clone our modified version:
```bash
git clone https://github.com/AdrielMendezRios/nvidia-rag-blueprint.git
cd nvidia-rag-blueprint
```

---

## Step-by-Step Deployment

### Step 1: Setup Helm Repos
```bash
# Add the repos we need
helm repo add minio https://charts.min.io/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add nim https://helm.ngc.nvidia.com/nim
helm repo update
```

### Step 2: Create Namespace
```bash
# Create our namespace
oc new-project nv-nvidia-blueprint-rag
# or if it exists: oc project nv-nvidia-blueprint-rag
```

### Step 3: Deploy External MinIO
This is the tricky part - we deploy MinIO separately because the chart's built-in MinIO tries to do distributed mode (which fails).

```bash
# Deploy standalone MinIO with the credentials our app expects
helm install rag-minio minio/minio -n nv-nvidia-blueprint-rag \
  --set mode=standalone \
  --set fullnameOverride=rag-minio \
  --set rootUser=minioadmin \
  --set rootPassword=minioadmin \
  --set persistence.enabled=false \
  --set resources.requests.memory=256Mi \
  --set resources.limits.memory=512Mi
```

### Step 4: Deploy External Redis
```bash
# Redis for message queuing
helm install rag-redis bitnami/redis -n nv-nvidia-blueprint-rag \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.persistence.enabled=false
```

### Step 5: Setup NGC Credentials
```bash
# Create the secret for pulling NVIDIA images
oc create secret docker-registry ngc-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY \
  -n nv-nvidia-blueprint-rag
```

### Step 6: Deploy the Main Chart
Navigate to our chart directory:
```bash
cd deploy/helm/rag-server
```

Deploy with our OpenShift-specific values:
```bash
helm upgrade --install rag-server . \
  -n nv-nvidia-blueprint-rag \
  -f values-openshift.yaml \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY
```

### Step 7: Fix the SCC Issue (You'll Need This)
The nv-ingest pod will crash with a security violation. Fix it:
```bash
# Apply anyuid SCC to the nv-ingest service account
oc adm policy add-scc-to-user anyuid \
  system:serviceaccount:nv-nvidia-blueprint-rag:rag-server-nv-ingest

# Restart the deployment to pick up the SCC
oc rollout restart deployment/rag-server-nv-ingest -n nv-nvidia-blueprint-rag
```

---

## Verification Commands

### Check Everything is Running
```bash
# Should see 13 pods all Running
oc get pods -n nv-nvidia-blueprint-rag

# Check for any issues
oc get events -n nv-nvidia-blueprint-rag --sort-by='.lastTimestamp'
```

### Test the APIs
```bash
# Port forward the services
oc port-forward service/rag-server 8081:8081 -n nv-nvidia-blueprint-rag &
oc port-forward service/ingestor-server 8082:8082 -n nv-nvidia-blueprint-rag &
oc port-forward service/rag-server-frontend 3000:3000 -n nv-nvidia-blueprint-rag &

# Test health endpoints
curl http://localhost:8081/v1/health
curl http://localhost:8082/v1/health

# Check the frontend
curl -I http://localhost:3000
```

### Access the UI
- **Frontend**: http://localhost:3000
- **RAG API Docs**: http://localhost:8081/docs  
- **Ingestor API Docs**: http://localhost:8082/docs

---

## Common Issues & Fixes

### Issue 1: nv-ingest Pod Crashes with SCC Violation
**Error**: `fsGroup: 1000 is not an allowed group`
**Fix**: Apply anyuid SCC (see Step 7 above)

### Issue 2: MinIO Authentication Errors
**Error**: `The Access Key Id you provided does not exist`
**Fix**: Make sure you used `rootUser`/`rootPassword` not `auth.rootUser` when deploying MinIO

### Issue 3: nv-ingest OOMKilled
**Error**: Pod gets killed due to memory
**Fix**: Already fixed in our values-openshift.yaml (4Gi memory limit)

### Issue 4: Ingestor Can't Connect to MinIO
**Error**: Connection refused or 503 errors
**Fix**: Check that MinIO is in standalone mode, not distributed

### Issue 5: Image Pull Errors
**Error**: `unauthorized: authentication required`
**Fix**: Double-check your NGC API key and secret creation

---

## What's Different in Our Fork

### Our Key Changes:
1. **values-openshift.yaml** - CPU-only config with proper security contexts
2. **Disabled all GPU NIMs** - No GPU dependencies
3. **External MinIO/Redis** - Deployed separately to avoid complexity
4. **Memory optimizations** - Bumped nv-ingest to 4Gi to prevent OOM
5. **SCC compatibility** - Security contexts that work with OpenShift

### Files We Added:
- `values-openshift.yaml` (main config)
- OpenShift Route template
- Test files for chart-verifier
- Comprehensive documentation

### Files We Modified (minimal):
- `Chart.yaml` - Added kubeVersion
- `templates/_helpers.tpl` - Added Route helpers  
- `templates/deployment.yaml` - Minor template improvements

---

## Testing Document Upload

Create a test file:
```bash
echo "This is a test document for NVIDIA RAG Blueprint" > /tmp/test.txt
```

Upload it:
```bash
curl -X POST "http://localhost:8082/documents" \
  -H "Content-Type: multipart/form-data" \
  -F "documents=@/tmp/test.txt" \
  -F 'data={"collection_name": "multimodal_data", "blocking": false}'
```

Should get: `{"message":"Ingestion started in background","task_id":"..."}`

---

## Cleanup Commands

If you need to start over:
```bash
# Remove everything
helm uninstall rag-server -n nv-nvidia-blueprint-rag
helm uninstall rag-minio -n nv-nvidia-blueprint-rag  
helm uninstall rag-redis -n nv-nvidia-blueprint-rag
oc delete project nv-nvidia-blueprint-rag
```

---

## Chart-Verifier Status

We're at **9/12 passing** (75% compliance):
- ✅ All structural requirements met
- ✅ Security and documentation standards  
- ❌ Images not Red Hat certified (expected)
- ❌ Contains CRDs (kube-prometheus-stack)
- ❌ Missing some OpenShift annotations

Good enough for enterprise use with documented exceptions.

---

## Next Steps / Improvements

1. **Add GPU nodes** if you want full AI functionality
2. **Connect external LLM services** for CPU-only AI inference
3. **Persistent storage** for production MinIO
4. **Remove kube-prometheus-stack** dependency for full chart-verifier compliance

---

## Questions?

- Check the detailed docs in our repo: `CHART-VERIFIER-RESULTS.md`, `CRD-ANALYSIS.md`
- All the troubleshooting info is in `CURRENT-STATE.md`
- API docs available at the `/docs` endpoints when port-forwarded

**Bottom line**: This gives you a solid foundation for RAG development and testing on OpenShift without needing GPU resources.