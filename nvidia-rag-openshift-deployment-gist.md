# NVIDIA RAG Blueprint: OpenShift Deployment Quick Reference

**TL;DR**:  deployed NVIDIA RAG Blueprint on OpenShift CPU-only with external infrastructure, achieving 9/12 chart-verifier compliance and 13 running pods.

## 🏗️ Key Architecture Decisions

### External Infrastructure Pattern
- **MinIO**: Deployed standalone outside main chart (`rag-minio:9000`)
- **Redis**: External deployment for message queuing (`rag-redis-master:6379`)
- **Rationale**: they werent direct dependencies as far as i could tell and wanted to stay 'true' to the helm deployment

### Security & Compliance
- **SCC Requirements**: `anyuid` SCC needed for `nv-ingest` component
- **Security Contexts**: No hardcoded UIDs, OpenShift-compatible contexts
- **Chart-Verifier**: 9/12 passing checks (75% compliance) with community profile

## ⚙️ Critical Configurations

### values-openshift.yaml Highlights
```yaml
# OpenShift-compatible security contexts
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]

# External service endpoints
envVars:
  MINIO_ENDPOINT: "rag-minio:9000"
  APP_VECTORSTORE_URL: "http://milvus:19530"
  
# Resource optimization for CPU-only
nv-ingest:
  resources:
    limits:
      memory: "4Gi"  # Critical: Prevents OOMKilled during librosa install
```

### Essential Commands
```bash
# Apply anyuid SCC for nv-ingest
oc adm policy add-scc-to-user anyuid system:serviceaccount:nv-nvidia-blueprint-rag:rag-server-nv-ingest

# Deploy external MinIO with correct credentials
helm install rag-minio minio/minio -n nv-nvidia-blueprint-rag \
  --set mode=standalone \
  --set rootUser=minioadmin \
  --set rootPassword=minioadmin \
  --set persistence.enabled=false

# Main deployment with OpenShift values
helm upgrade --install rag-server . -n nv-nvidia-blueprint-rag \
  -f values-openshift.yaml --create-namespace
```

## 🚨 Gotchas & Solutions

| Issue | Root Cause | Solution |
|-------|------------|----------|
| **Ingestor crash loop** | MinIO distributed mode expecting 16 drives | Deploy MinIO in standalone mode |
| **nv-ingest SCC violation** | `fsGroup: 1000` not allowed | Apply `anyuid` SCC to service account |
| **MinIO auth failures** | Auto-generated vs expected credentials | Redeploy with `rootUser`/`rootPassword` params |
| **nv-ingest OOMKilled** | librosa installation exceeds 2Gi limit | Increase memory limit to 4Gi |
| **Chart-verifier CRDs** | kube-prometheus-stack contains CRDs | Remove dependency or document exception |

## 📊 Chart-Verifier Status

**Current Score**: 9/12 (75% - Enterprise Ready)

**Passing**: helm-lint, is-helm-v3, contains-values, contains-values-schema, has-kubeversion, contains-test, has-readme, has-notes, not-contain-csi-objects

**Failing**: images-are-certified, not-contains-crds, required-annotations-present

## 🎯 Deployment Result

**Final State**: 13 pods running successfully
- ✅ rag-server, ingestor-server, frontend
- ✅ milvus-standalone (CPU-only vector DB)
- ✅ rag-minio, rag-redis-master
- ✅ observability stack (zipkin, opentelemetry-collector)

**Performance**: CPU-only deployment with disabled GPU NIMs, suitable for development/learning environments.

---

**Resources**: See comprehensive documentation in repository for detailed analysis, troubleshooting guides, and enterprise deployment strategies.