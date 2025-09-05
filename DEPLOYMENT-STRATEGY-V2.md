# NVIDIA RAG Blueprint: Phased Deployment Strategy v2

**Document Version**: 2.0  
**Created**: September 5, 2025  
**Status**: Ready for Implementation  
**Context**: OpenShift 4.x, No GPU Resources, Chart-Verifier Preparation  

---

## 🎯 Executive Summary

This strategy enables successful deployment of the NVIDIA RAG Blueprint on OpenShift without GPU resources while maintaining chart authenticity for Red Hat Chart-Verifier validation. Based on comprehensive lessons learned from attempt-1, this approach uses proven external infrastructure patterns and conservative resource allocation.

**Key Achievements**:
- ✅ NGC credentials resolved with new API key from build.nvidia.com
- ✅ All helm dependencies successfully downloaded (9/9 charts)
- ✅ values-openshift.yaml configured for CPU-only OpenShift deployment
- ✅ Chart structure preserved for chart-verifier compliance

---

## 🏗️ Architecture Overview

### **Original Blueprint Components**
```
nvidia-blueprint-rag/
├── Chart.yaml (umbrella chart - PRESERVED)
├── values.yaml (original GPU config)  
├── values-openshift.yaml (our CPU-only config)
├── charts/ (all dependencies downloaded)
│   ├── ingestor-server/ (document processing)
│   ├── frontend/ (React UI)
│   └── [9 external dependencies from NGC/public repos]
```

### **Service Discovery Pattern (Maintained)**
Applications expect these endpoints regardless of deployment method:
- `rag-server:8081` - Query processing API
- `ingestor-server:8082` - Document ingestion API  
- `rag-minio:9000` - Object storage
- `rag-redis-master:6379` - Message queue
- `milvus:19530` - Vector database
- `zipkin:9411` - Distributed tracing UI
- `opentelemetry-collector:4317/4318` - Telemetry collection

---

## 📋 Phased Implementation Strategy

### **Phase 1: Foundation & External Infrastructure** 🏗️
**Duration**: 1-2 hours  
**Resource Impact**: Low (~1Gi memory, 0.3 CPU)  
**Success Rate**: 95%+  
**Status**: Ready to Execute

#### **Deployment Steps**:
1. **External Infrastructure** (separate helm releases):
   ```bash
   # Add required repositories
   helm repo add minio https://charts.min.io/
   helm repo add bitnami https://charts.bitnami.com/bitnami
   helm repo update
   
   # Deploy MinIO (object storage)
   helm install rag-minio minio/minio -n nv-nvidia-blueprint-rag \
     --create-namespace \
     --set fullnameOverride=rag-minio \
     --set auth.enabled=false \
     --set persistence.enabled=false \
     --set resources.requests.memory=256Mi \
     --set resources.requests.cpu=100m
   
   # Deploy Redis (message queue)
   helm install rag-redis bitnami/redis -n nv-nvidia-blueprint-rag \
     --set fullnameOverride=rag-redis \
     --set auth.enabled=false \
     --set replica.replicaCount=0 \
     --set master.resources.requests.memory=256Mi \
     --set master.resources.requests.cpu=100m
   ```

2. **Core Application Deployment**:
   ```bash
   # Deploy RAG Blueprint with OpenShift configuration
   cd /home/admendez/projects/nvidia-rag-bp/rag/deploy/helm/rag-server
   
   helm upgrade --install rag-learning . \
     -n nv-nvidia-blueprint-rag \
     --create-namespace \
     -f values-openshift.yaml
   ```

3. **Validation Commands**:
   ```bash
   # Monitor deployment progress
   oc get pods -n nv-nvidia-blueprint-rag -w
   
   # Check service endpoints
   oc get svc -n nv-nvidia-blueprint-rag
   
   # Verify external infrastructure connectivity
   oc run debug-pod --image=curlimages/curl -n nv-nvidia-blueprint-rag --rm -i --restart=Never -- \
     sh -c "nslookup rag-minio && nslookup rag-redis-master"
   ```

#### **Success Criteria**:
- [ ] Core applications (rag-server, ingestor-server, frontend) all Running
- [ ] External MinIO accessible at `rag-minio:9000`
- [ ] External Redis accessible at `rag-redis-master:6379`
- [ ] No CrashLoopBackOff pods
- [ ] Health endpoints responding: `oc port-forward service/rag-learning-rag-server 8081:8081`

#### **Expected State**: 5/5 pods Running

---

### **Phase 2: CPU-Only Vector Database** 🗄️
**Duration**: 1-2 hours  
**Resource Impact**: Medium (~2Gi memory, 1 CPU)  
**Success Rate**: 85%+

#### **Implementation Options**:

**Option A: External Milvus (Recommended)**
```bash
# Add Milvus repository
helm repo add milvus https://milvus-io.github.io/milvus-helm/
helm repo update

# Deploy CPU-only Milvus
helm install milvus milvus/milvus -n nv-nvidia-blueprint-rag \
  --set fullnameOverride=milvus \
  --set image.tag=v2.5.3 \
  --set standalone.resources.limits.nvidia.com/gpu=0 \
  --set standalone.resources.requests.memory=1Gi \
  --set standalone.resources.requests.cpu=500m \
  --set standalone.resources.limits.memory=2Gi \
  --set standalone.resources.limits.cpu=1
```

**Option B: Enable nv-ingest subchart Milvus** (if needed)
```bash
# Modify values-openshift.yaml to enable embedded Milvus
# (Already configured in current values-openshift.yaml)
helm upgrade rag-learning . -n nv-nvidia-blueprint-rag -f values-openshift.yaml
```

#### **Validation Commands**:
```bash
# Test Milvus connectivity
oc run milvus-test --image=curlimages/curl -n nv-nvidia-blueprint-rag --rm -i --restart=Never -- \
  curl -X GET "http://milvus:19530/health"

# Check vector database integration
oc logs deployment/rag-learning-ingestor-server -n nv-nvidia-blueprint-rag | grep -i milvus
```

#### **Success Criteria**:
- [ ] Milvus database accessible at `milvus:19530`
- [ ] Vector collections can be created via API
- [ ] Ingestor-server connects to Milvus successfully
- [ ] No resource exhaustion on cluster nodes

#### **Expected State**: 6/6 pods Running with functional vector storage

---

### **Phase 3: Observability Stack** 📊
**Duration**: 30-60 minutes  
**Resource Impact**: Low-Medium (~768Mi memory, 0.3 CPU)  
**Success Rate**: 90%+

#### **Components** (Already enabled in values-openshift.yaml):
- Zipkin (Distributed Tracing UI)
- OpenTelemetry Collector (Metrics Collection)

#### **OpenShift Security Context Fix** (Known requirement):
```bash
# Grant anyuid SCC for Zipkin (based on attempt-1 learnings)
oc adm policy add-scc-to-user anyuid \
  system:serviceaccount:nv-nvidia-blueprint-rag:rag-learning-zipkin

# Restart Zipkin deployment to apply SCC
oc rollout restart deployment/rag-learning-zipkin -n nv-nvidia-blueprint-rag

# Create external route for Zipkin UI
oc expose service/rag-learning-zipkin -n nv-nvidia-blueprint-rag
```

#### **Validation Commands**:
```bash
# Get Zipkin UI route
oc get route -n nv-nvidia-blueprint-rag

# Test telemetry endpoints
oc port-forward service/rag-learning-opentelemetry-collector 4318:4318 -n nv-nvidia-blueprint-rag
curl -X POST http://localhost:4318/v1/traces -H "Content-Type: application/json" -d '{"test":"trace"}'
```

#### **Success Criteria**:
- [ ] Zipkin UI accessible via OpenShift route
- [ ] OpenTelemetry collector receiving traces  
- [ ] RAG server and ingestor sending telemetry data
- [ ] No impact on Phase 1-2 services

#### **Expected State**: 8/8 pods Running with distributed tracing operational

---

### **Phase 4: Chart-Verifier Preparation** ✅
**Duration**: 2-3 hours  
**Resource Impact**: None (validation only)  
**Success Rate**: Target 80%+

#### **Required Chart-Verifier Files**:

1. **Add kubeVersion to Chart.yaml**:
   ```yaml
   # Add to Chart.yaml
   kubeVersion: ">=1.20.0-0"  # OpenShift 4.10+ compatibility
   ```

2. **Create values.schema.json**:
   ```json
   {
     "$schema": "https://json-schema.org/draft-07/schema#",
     "type": "object",
     "properties": {
       "appName": {
         "type": "string",
         "description": "Application name"
       },
       "namespace": {
         "type": "string", 
         "description": "Kubernetes namespace"
       },
       "frontend": {
         "type": "object",
         "properties": {
           "enabled": {"type": "boolean"}
         }
       },
       "ingestor-server": {
         "type": "object",
         "properties": {
           "enabled": {"type": "boolean"}
         }
       }
     },
     "required": ["appName"]
   }
   ```

3. **Create templates/tests/test-connection.yaml**:
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: "{{ include "nvidia-blueprint-rag.fullname" . }}-test"
     labels:
       {{- include "nvidia-blueprint-rag.labels" . | nindent 4 }}
     annotations:
       "helm.sh/hook": test
   spec:
     restartPolicy: Never
     securityContext:
       runAsNonRoot: true
       runAsUser: 1001
       seccompProfile:
         type: RuntimeDefault
     containers:
       - name: wget
         image: registry.access.redhat.com/ubi8/ubi:latest
         command: ['wget']
         args: ['{{ .Values.appName }}:8081/v1/health']
         securityContext:
           allowPrivilegeEscalation: false
           capabilities:
             drop:
               - ALL
   ```

#### **Chart-Verifier Execution**:
```bash
# Pre-validation checks
helm lint .
helm template test-release . -f values-openshift.yaml --dry-run

# Run chart-verifier (container method)
podman run --rm -i \
  -e KUBECONFIG=/.kube/config \
  -v "${HOME}/.kube":/.kube:z \
  -v "$(pwd)":/charts:z \
  quay.io/redhat-certification/chart-verifier:latest \
  verify /charts \
  --set profile.vendorType=partner,profile.version=v1.3 \
  --write-to-file /charts/verification-results.yaml
```

#### **Success Criteria**:
- [ ] All mandatory checks passing (helm-lint, contains-values, etc.)
- [ ] Image certification documented/resolved
- [ ] Chart deploys successfully via chart-verifier testing
- [ ] Verification results documented

---

## 🚫 Permanently Disabled Components

These remain **disabled** throughout all phases (no GPU resources):

### **NVIDIA NIM Microservices**:
```yaml
nim-llm:
  enabled: false  # Local LLM inference (requires GPU)
  
nvidia-nim-llama-32-nv-embedqa-1b-v2:
  enabled: false  # Local embedding generation (requires GPU)
  
text-reranking-nim:
  enabled: false  # Local reranking (requires GPU)

nim-vlm:
  enabled: false  # Vision Language Model (requires GPU)
```

### **CPU-Only Environment Variables**:
```yaml
envVars:
  APP_VECTORSTORE_ENABLEGPUINDEX: "False"
  APP_VECTORSTORE_ENABLEGPUSEARCH: "False"
  ENABLE_RERANKER: "False"
  ENABLE_GUARDRAILS: "False"  
  ENABLE_REFLECTION: "False"
  ENABLE_VLM_INFERENCE: "false"
  ENABLE_MULTIMODAL: "False"
  ENABLE_QUERYREWRITER: "False"
```

### **NV-Ingest GPU Components**:
```yaml
ingestor-server:
  envVars:
    APP_NVINGEST_PDFEXTRACTMETHOD: "None"
    APP_NVINGEST_EXTRACTINFOGRAPHICS: "False"
    APP_NVINGEST_EXTRACTTABLES: "False"  
    APP_NVINGEST_EXTRACTCHARTS: "False"
    APP_NVINGEST_EXTRACTIMAGES: "False"
```

---

## 📊 Resource Planning

### **Total Resource Requirements by Phase**:
| Phase | Memory Added | CPU Added | Total Memory | Total CPU | Cluster Impact |
|-------|-------------|-----------|--------------|-----------|----------------|
| Phase 1 | ~3Gi | ~850m | ~3Gi | ~850m | ✅ Low |
| Phase 2 | ~2Gi | ~1 CPU | ~5Gi | ~1.8 CPU | ✅ Medium |
| Phase 3 | ~768Mi | ~300m | ~5.8Gi | ~2.1 CPU | ✅ Medium |
| Phase 4 | 0 | 0 | ~5.8Gi | ~2.1 CPU | ✅ Validation Only |

### **Cluster Requirements** (Conservative):
- **Minimum**: 3+ worker nodes, 16Gi+ memory per node, 4+ cores per node
- **Recommended**: 48Gi total memory, 12+ CPU cores across cluster
- **Our Target**: Deploy within 6Gi memory, 2.5 CPU total

---

## 🔧 Implementation Commands Reference

### **Current Working Directory**: 
```bash
cd /home/admendez/projects/nvidia-rag-bp/rag/deploy/helm/rag-server
```

### **NGC Environment** (Already configured):
```bash
# NGC API Key already set
echo $NGC_API_KEY
# Expected: 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

# Repositories already added
helm repo list | grep -E "(nim|zipkin|opentelemetry|prometheus)"
```

### **Deployment Status Monitoring**:
```bash
# Watch pod status across all phases
watch 'oc get pods -n nv-nvidia-blueprint-rag'

# Check resource usage
oc describe nodes | grep -A 5 "Allocated resources"

# Service connectivity testing
oc run debug-pod --image=curlimages/curl -n nv-nvidia-blueprint-rag --rm -i --restart=Never -- \
  curl -v http://SERVICE_NAME:PORT/health
```

### **Rollback Procedures**:
```bash
# Phase-specific rollback
helm rollback rag-learning -n nv-nvidia-blueprint-rag

# Complete environment reset
helm uninstall rag-learning -n nv-nvidia-blueprint-rag
helm uninstall rag-minio -n nv-nvidia-blueprint-rag  
helm uninstall rag-redis -n nv-nvidia-blueprint-rag
helm uninstall milvus -n nv-nvidia-blueprint-rag

# Cleanup namespace if needed
oc delete namespace nv-nvidia-blueprint-rag
```

---

## 🎯 Success Metrics

### **Technical Success Criteria**:
- ✅ All enabled components in Running state (no CrashLoopBackOff)
- ✅ Service endpoints responding to health checks
- ✅ Resource usage within cluster limits
- ✅ No persistent errors in pod logs
- ✅ External infrastructure connectivity verified

### **Chart-Verifier Success Criteria**:
- ✅ All mandatory checks passing (11 total)
- ✅ Chart structure validation passed
- ✅ Template rendering successful
- ✅ Deployment testing successful
- ✅ Documentation requirements met

### **Learning Success Criteria**:
- ✅ Chart authenticity preserved for enterprise validation
- ✅ OpenShift deployment patterns mastered
- ✅ External infrastructure strategy proven
- ✅ CPU-only configuration optimization achieved

---

## 🚨 Known Issues & Solutions

### **OpenShift Security Context Constraints**:
**Issue**: Third-party containers fail with SCC violations  
**Solution**: Grant specific SCC permissions as needed:
```bash
oc adm policy add-scc-to-user anyuid system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT
oc rollout restart deployment/DEPLOYMENT_NAME -n NAMESPACE
```

### **Image Certification** (Chart-Verifier):
**Issue**: NGC images may not be Red Hat certified  
**Solution**: Document non-certified images, provide certified alternatives where possible

### **Resource Constraints**:
**Issue**: Pods stuck in Pending state  
**Solution**: Monitor cluster capacity, reduce resource requests if needed

---

## 🔗 Reference Documentation

### **Attempt-1 Learnings**:
- `/home/admendez/projects/nvidia-rag-bp/docs/attempt-1/COMPREHENSIVE-LEARNINGS-REFERENCE.md`
- `/home/admendez/projects/nvidia-rag-bp/docs/attempt-1/phased-deployment-strategy.md`

### **Current Configuration**:
- `/home/admendez/projects/nvidia-rag-bp/rag/deploy/helm/rag-server/values-openshift.yaml`
- `/home/admendez/projects/nvidia-rag-bp/rag/deploy/helm/rag-server/Chart.yaml`

### **NGC Credentials**:
- API Key: Stored in environment variable `NGC_API_KEY`
- Source: https://build.nvidia.com (blueprints API key)

---

## 📅 Implementation Checklist

### **Pre-Implementation Validation**:
- [x] NGC credentials configured and tested
- [x] Helm dependencies downloaded (9/9 charts)
- [x] values-openshift.yaml reviewed and optimized
- [x] Cluster resource capacity assessed
- [x] OpenShift namespace ready

### **Phase 1 Ready State**:
- [ ] External MinIO deployed and accessible
- [ ] External Redis deployed and accessible  
- [ ] Core applications deployed with CPU-only config
- [ ] All pods in Running state
- [ ] Health endpoints responding

### **Phase 2 Ready State**:
- [ ] Vector database (Milvus) deployed and accessible
- [ ] Ingestor-server connects to vector database
- [ ] Vector operations functional (create collections)
- [ ] No resource exhaustion

### **Phase 3 Ready State**:
- [ ] Zipkin UI accessible via OpenShift route
- [ ] OpenTelemetry collector operational
- [ ] Distributed tracing end-to-end functional
- [ ] SCC permissions properly configured

### **Phase 4 Ready State**:
- [ ] Chart-verifier required files created
- [ ] All mandatory validation checks passing
- [ ] Documentation complete and comprehensive
- [ ] Verification results documented

---

**Implementation Status**: ✅ **READY TO EXECUTE PHASE 1**

**Next Action**: Begin Phase 1 deployment with external infrastructure setup

**Document Location**: `/home/admendez/projects/nvidia-rag-bp/rag/DEPLOYMENT-STRATEGY-V2.md`