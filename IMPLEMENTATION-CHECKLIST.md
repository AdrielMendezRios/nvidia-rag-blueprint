# NVIDIA RAG Blueprint: Implementation Checklist

**Quick Reference**: Step-by-step execution guide for phased deployment  
**Related**: See `DEPLOYMENT-STRATEGY-V2.md` for comprehensive strategy  
**Status**: ✅ **PHASE 1 & 2 COMPLETE** - Updated with Real-World Learnings  

---

## ⚡ Quick Start Commands

### **Working Directory**:
```bash
cd /home/admendez/projects/nvidia-rag-bp/rag/deploy/helm/rag-server
```

### **Environment Verification**:
```bash
# Verify NGC credentials
echo $NGC_API_KEY
# Expected: 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

# Verify helm dependencies
helm dependency list
# Expected: 9 dependencies with "ok" status

# Check cluster access
oc whoami
oc get nodes
```

---

## 📋 Phase 1: Foundation & External Infrastructure

### **Pre-Phase Validation**:
- [x] NGC API key configured and working
- [x] Helm dependencies downloaded (9/9 charts)
- [x] OpenShift cluster access verified
- [x] Working directory confirmed

### **Execution Steps**:

#### **1. Add Required Repositories**:
```bash
helm repo add minio https://charts.min.io/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

#### **2. Deploy External MinIO**:
```bash
helm install rag-minio minio/minio -n nv-nvidia-blueprint-rag \
  --create-namespace \
  --set fullnameOverride=rag-minio \
  --set auth.enabled=false \
  --set persistence.enabled=false \
  --set resources.requests.memory=256Mi \
  --set resources.requests.cpu=100m
```

#### **3. Deploy External Redis**:
```bash
helm install rag-redis bitnami/redis -n nv-nvidia-blueprint-rag \
  --set fullnameOverride=rag-redis \
  --set auth.enabled=false \
  --set replica.replicaCount=0 \
  --set master.resources.requests.memory=256Mi \
  --set master.resources.requests.cpu=100m
```

#### **4. Deploy Core RAG Blueprint**:
```bash
helm upgrade --install rag-learning . \
  -n nv-nvidia-blueprint-rag \
  --create-namespace \
  -f values-openshift.yaml
```

#### **5. Monitor Deployment**:
```bash
# Watch pod status (expect 5/5 Running)
watch 'oc get pods -n nv-nvidia-blueprint-rag'

# Check services
oc get svc -n nv-nvidia-blueprint-rag
```

### **Validation Commands**:
```bash
# Test external infrastructure connectivity
oc run debug-pod --image=curlimages/curl -n nv-nvidia-blueprint-rag --rm -i --restart=Never -- \
  sh -c "nslookup rag-minio && nslookup rag-redis-master"

# Test RAG server health
oc port-forward service/rag-learning-rag-server 8081:8081 -n nv-nvidia-blueprint-rag &
curl http://localhost:8081/v1/health

# REAL-WORLD: Check for SCC violations early
oc get events -n nv-nvidia-blueprint-rag --field-selector reason=FailedCreate
oc describe pods -n nv-nvidia-blueprint-rag | grep -A 10 "unable to validate against any security context constraint"
```

### **Success Criteria**:
- [x] 5/5 pods Running (rag-server, ingestor-server, frontend, minio, redis)
- [x] MinIO accessible at `rag-minio:9000`
- [x] Redis accessible at `rag-redis-master:6379`
- [x] RAG server health endpoint responding
- [x] No CrashLoopBackOff pods

### **Troubleshooting**:
```bash
# Check failing pods
oc describe pod POD_NAME -n nv-nvidia-blueprint-rag
oc logs POD_NAME -n nv-nvidia-blueprint-rag

# Check resource constraints
oc describe nodes | grep -A 5 "Allocated resources"
```

#### **Real-World Issues Encountered**:

**Issue 1: Zipkin SCC Violations**
```bash
# Problem: Zipkin pod failed with SCC violation
# Solution: Grant anyuid SCC
oc adm policy add-scc-to-user anyuid system:serviceaccount:nv-nvidia-blueprint-rag:default

# Restart to apply SCC changes
oc rollout restart deployment/rag-learning-zipkin -n nv-nvidia-blueprint-rag
```

**Issue 2: Routes Creation**
```bash
# Create OpenShift routes for external access
oc expose service/rag-learning-frontend -n nv-nvidia-blueprint-rag
oc expose service/rag-learning-zipkin -n nv-nvidia-blueprint-rag

# Get route URLs
oc get routes -n nv-nvidia-blueprint-rag
```

---

## 📋 Phase 2: Authentic CPU-Only Vector Database via NV-Ingest

### **Pre-Phase Validation**:
- [x] Phase 1 completed successfully (5/5 pods Running)
- [x] Cluster resources available for additional ~2Gi memory, 1 CPU

### **🔍 DISCOVERY: Authentic Chart Structure**
**CRITICAL FINDING**: Milvus deployment is achieved via the authentic nv-ingest subchart, NOT external installation. This preserves chart authenticity for enterprise validation.

### **Required Steps for Authentic Deployment**:

#### **1. Fix Missing NV-Ingest Dependency**:
```bash
# Check dependency status (you may see "missing" status)
helm dependency list charts/ingestor-server/

# Navigate to ingestor-server subchart directory
cd charts/ingestor-server/

# Download the authentic NGC nv-ingest subchart
helm dependency update

# Verify download (should show v25.6.2 from NGC)
ls charts/

# Return to main chart directory
cd ../../
```

#### **2. Configure CPU-Only Milvus via NV-Ingest**:
```bash
# Milvus configuration is in values-openshift.yaml under:
# ingestor-server.nv-ingest.milvus
# This enables authentic Milvus deployment with CPU-only settings

# Deploy/update with authentic configuration
helm upgrade rag-learning . -n nv-nvidia-blueprint-rag -f values-openshift.yaml
```

#### **3. Fix GPU Component Naming Issues**:
```bash
# ISSUE: GPU components may still deploy due to incorrect field names
# SOLUTION: Ensure values-openshift.yaml has correct component names:
# - nemoretriever-page-elements-v2 (not nemoretriever-page-elements)
# - nemoretriever-graphic-elements-v1
# - nemoretriever-table-structure-v1
# All should have "deployed: false" in values-openshift.yaml
```

### **Validation Commands**:
```bash
# Test Milvus connectivity (authentic deployment)
oc run milvus-test --image=curlimages/curl -n nv-nvidia-blueprint-rag --rm -i --restart=Never -- \
  curl -X GET "http://milvus:19530/health"

# Check ingestor-server Milvus integration
oc logs deployment/rag-learning-ingestor-server -n nv-nvidia-blueprint-rag | grep -i milvus

# REAL-WORLD: Verify authentic subchart deployment
oc get pods -n nv-nvidia-blueprint-rag | grep milvus
oc get pods -n nv-nvidia-blueprint-rag | grep etcd

# Monitor resource pressure (critical for stability)
oc describe nodes | grep -A 5 "Allocated resources"
oc get pods -n nv-nvidia-blueprint-rag --field-selector=status.phase!=Running

# Verify no GPU components are pending
oc get pods -n nv-nvidia-blueprint-rag | grep Pending
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(nemoretriever|paddleocr)"
```

### **Success Criteria**:
- [x] 29/29 pods Running (including authentic milvus-standalone + etcd)
- [x] Milvus accessible at `milvus:19530`
- [x] Ingestor-server connects to Milvus without errors  
- [x] No GPU components pending (all disabled successfully)
- [x] Authentic nv-ingest subchart structure preserved

### **Real-World Troubleshooting**:

#### **Issue 1: Missing NV-Ingest Subchart**
```bash
# Problem: helm dependency list shows "missing" for nv-ingest
# Root Cause: Subchart not downloaded from NGC repository
# Solution: Update dependencies from correct directory
cd charts/ingestor-server/
helm dependency update  # Downloads nv-ingest v25.6.2 from NGC
cd ../../
```

#### **Issue 2: ETCD SCC Violations**
```bash
# Problem: rag-server-etcd pod fails with SCC violation
# Symptom: "unable to validate against any security context constraint"
# Solution: Grant anyuid SCC and restart
oc adm policy add-scc-to-user anyuid system:serviceaccount:nv-nvidia-blueprint-rag:default
oc rollout restart deployment/rag-server-etcd -n nv-nvidia-blueprint-rag
```

#### **Issue 3: Milvus Resource Pressure Crashes**
```bash
# Problem: milvus-standalone exits with code 134 (SIGABRT)
# Root Cause: High cluster resource utilization (96%+ CPU)
# Solution: Wait for cluster stabilization, restart if needed
oc get nodes  # Check cluster resource pressure
oc rollout restart deployment/milvus-standalone -n nv-nvidia-blueprint-rag
```

#### **Issue 4: GPU Components Still Deploying**
```bash
# Problem: GPU NIMs still show "Pending" status
# Root Cause: Incorrect field names in values-openshift.yaml
# Solution: Use version-specific component names
# Fix: nemoretriever-page-elements -> nemoretriever-page-elements-v2
# Fix: nemoretriever-graphic-elements -> nemoretriever-graphic-elements-v1
# Fix: nemoretriever-table-structure -> nemoretriever-table-structure-v1

# Verify no pending GPU pods
oc get pods -n nv-nvidia-blueprint-rag | grep Pending
```

---

## 📋 Phase 3: Observability Stack

### **Pre-Phase Validation**:
- [x] Phase 2 completed successfully (29/29 pods Running)
- [x] Additional ~768Mi memory available

### **Execution Steps**:

#### **1. Grant SCC for Zipkin** (Known requirement):
```bash
oc adm policy add-scc-to-user anyuid \
  system:serviceaccount:nv-nvidia-blueprint-rag:rag-learning-zipkin
```

#### **2. Check if observability components are already running**:
```bash
# Should already be enabled from values-openshift.yaml
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(zipkin|opentelemetry)"
```

#### **3. If not running, restart deployment**:
```bash
oc rollout restart deployment/rag-learning-zipkin -n nv-nvidia-blueprint-rag
oc rollout restart deployment/rag-learning-opentelemetry-collector -n nv-nvidia-blueprint-rag
```

#### **4. Create external route for Zipkin UI**:
```bash
oc expose service/rag-learning-zipkin -n nv-nvidia-blueprint-rag
oc get route -n nv-nvidia-blueprint-rag
```

### **Validation Commands**:
```bash
# Test telemetry endpoints
oc port-forward service/rag-learning-opentelemetry-collector 4318:4318 -n nv-nvidia-blueprint-rag &
curl -X POST http://localhost:4318/v1/traces -H "Content-Type: application/json" -d '{"test":"trace"}'

# Access Zipkin UI via route
ZIPKIN_URL=$(oc get route rag-learning-zipkin -n nv-nvidia-blueprint-rag -o jsonpath='{.spec.host}')
echo "Zipkin UI: https://$ZIPKIN_URL"
```

### **Success Criteria**:
- [x] All pods Running (zipkin + opentelemetry already deployed in Phase 1)
- [x] Zipkin UI accessible via OpenShift route  
- [x] OpenTelemetry collector receiving requests
- [x] No SCC violations in logs

---

## 📋 Phase 4: Chart-Verifier Preparation

### **Pre-Phase Validation**:
- [x] Phase 3 completed successfully (29/29 pods Running)
- [x] Deployment stable and all services functional

### **Required Files Creation**:

#### **1. Add kubeVersion to Chart.yaml**:
```bash
# Edit Chart.yaml to add kubeVersion constraint
# Add line: kubeVersion: ">=1.20.0-0"
```

#### **2. Create values.schema.json**:
```bash
cat > values.schema.json << 'EOF'
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
EOF
```

#### **3. Create test file**:
```bash
mkdir -p templates/tests

cat > templates/tests/test-connection.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: "{{ .Values.appName }}-test"
  labels:
    app: {{ .Values.appName }}
    chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
    release: {{ .Release.Name }}
    heritage: {{ .Release.Service }}
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
EOF
```

### **Chart-Verifier Execution**:
```bash
# Pre-validation
helm lint .
helm template test-release . -f values-openshift.yaml --dry-run

# Run chart-verifier
podman run --rm -i \
  -e KUBECONFIG=/.kube/config \
  -v "${HOME}/.kube":/.kube:z \
  -v "$(pwd)":/charts:z \
  quay.io/redhat-certification/chart-verifier:latest \
  verify /charts \
  --set profile.vendorType=partner,profile.version=v1.3 \
  --write-to-file /charts/verification-results.yaml
```

### **Success Criteria**:
- [ ] helm lint passes without errors
- [ ] helm template renders successfully
- [ ] Chart-verifier mandatory checks pass
- [ ] Test pod executes successfully
- [ ] Verification results documented

---

## 🔧 Emergency Procedures

### **Common Issues Resolution Playbook**:

#### **SCC Violation Pattern**:
```bash
# Symptom: Pod fails with "unable to validate against any security context constraint"
# Root Cause: OpenShift security policies
# Standard Resolution:
oc adm policy add-scc-to-user anyuid system:serviceaccount:nv-nvidia-blueprint-rag:default
oc rollout restart deployment/FAILING_DEPLOYMENT -n nv-nvidia-blueprint-rag

# Verify resolution:
oc get pods -n nv-nvidia-blueprint-rag | grep DEPLOYMENT_NAME
```

#### **Resource Pressure Management**:
```bash
# Symptom: Pods crashing with exit codes 134, 137, or OOMKilled
# Diagnosis:
oc describe nodes | grep -A 10 "Allocated resources"
oc get events -n nv-nvidia-blueprint-rag | grep -i "insufficient"

# Mitigation:
# 1. Wait for cluster stabilization
# 2. Restart affected pods
oc delete pod POD_NAME -n nv-nvidia-blueprint-rag
# 3. Scale down non-essential workloads if needed
```

#### **Dependency Download Issues**:
```bash
# Symptom: "dependency missing" or subchart not found
# Solution: Update dependencies from correct directory
cd charts/ingestor-server/
helm dependency update
cd ../../

# Verify:
helm dependency list charts/ingestor-server/
```

#### **GPU Component Leakage**:
```bash
# Symptom: GPU NIMs still deploying despite CPU-only configuration
# Diagnosis:
oc get pods -n nv-nvidia-blueprint-rag | grep Pending
oc describe pods -n nv-nvidia-blueprint-rag | grep -A 5 "nvidia.com/gpu"

# Solution: Check values-openshift.yaml for correct component names
# Must include version suffixes: -v1, -v2 etc.
```

### **Complete Environment Reset**:
```bash
# Uninstall all components
helm uninstall rag-learning -n nv-nvidia-blueprint-rag
helm uninstall rag-minio -n nv-nvidia-blueprint-rag  
helm uninstall rag-redis -n nv-nvidia-blueprint-rag
helm uninstall milvus -n nv-nvidia-blueprint-rag

# Remove namespace
oc delete namespace nv-nvidia-blueprint-rag

# Remove SCC policies
oc adm policy remove-scc-from-user anyuid \
  system:serviceaccount:nv-nvidia-blueprint-rag:rag-learning-zipkin
```

### **Phase-Specific Rollback**:
```bash
# Rollback to previous helm revision
helm history rag-learning -n nv-nvidia-blueprint-rag
helm rollback rag-learning REVISION_NUMBER -n nv-nvidia-blueprint-rag
```

### **Resource Monitoring**:
```bash
# Check cluster resource pressure
oc describe nodes | grep -A 5 "Allocated resources"
oc top nodes 2>/dev/null || echo "Metrics server not available"

# Monitor pod resource usage
oc top pods -n nv-nvidia-blueprint-rag 2>/dev/null || echo "Metrics server not available"

# REAL-WORLD: Watch for resource pressure symptoms
oc get events -n nv-nvidia-blueprint-rag --field-selector reason=Failed
oc get events -n nv-nvidia-blueprint-rag --field-selector reason=FailedScheduling
oc get pods -n nv-nvidia-blueprint-rag --field-selector=status.phase=Failed

# Monitor container restarts (indicator of resource pressure)
oc get pods -n nv-nvidia-blueprint-rag -o wide | grep -v "0/0"
```

---

## 📊 Expected Resource Usage by Phase

| Phase | Pods | Memory | CPU | Cumulative |
|-------|------|--------|-----|------------|
| Phase 1 | 5 | ~3Gi | ~850m | 5 pods, 3Gi, 850m |
| Phase 2 | +24 | +2Gi | +1 CPU | 29 pods, 5Gi, 1.8 CPU |
| Phase 3 | 0 | +768Mi | +300m | 29 pods, 5.8Gi, 2.1 CPU |
| Phase 4 | 0 | 0 | 0 | 29 pods, 5.8Gi, 2.1 CPU |

**REAL-WORLD RESULTS**: 29 total pods (vs predicted 8)  
**DISCOVERY**: Authentic nv-ingest subchart deploys many additional pods

**Target Cluster**: 48Gi total memory, 12+ CPU cores  
**Our Usage**: ~5.8Gi memory, ~2.1 CPU (well within limits)

---

## ✅ Final Validation

### **Pre-Validation Health Checks**:
```bash
# Comprehensive deployment status
oc get pods -n nv-nvidia-blueprint-rag
oc get svc -n nv-nvidia-blueprint-rag
oc get routes -n nv-nvidia-blueprint-rag

# Verify authentic components are running
echo "Core RAG Components:"
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(rag-server|ingestor|frontend)"
echo "Authentic Vector Database:"
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(milvus|etcd)"
echo "External Infrastructure:"
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(minio|redis)"
echo "Observability:"
oc get pods -n nv-nvidia-blueprint-rag | grep -E "(zipkin|opentelemetry)"

# Verify no problematic pods
echo "Problem Check (should be empty):"
oc get pods -n nv-nvidia-blueprint-rag --field-selector=status.phase!=Running
oc get pods -n nv-nvidia-blueprint-rag | grep Pending
```

### **End-to-End Testing**:
```bash
# 1. Document ingestion test
oc port-forward service/rag-learning-ingestor-server 8082:8082 -n nv-nvidia-blueprint-rag &
curl -X POST "http://localhost:8082/v1/documents" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@./sample.pdf"

# 2. RAG query test
oc port-forward service/rag-learning-rag-server 8081:8081 -n nv-nvidia-blueprint-rag &
curl -X POST "http://localhost:8081/v1/generate" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is this document about?"}'

# 3. Frontend access
oc port-forward service/rag-learning-frontend 3000:3000 -n nv-nvidia-blueprint-rag &
echo "Frontend: http://localhost:3000"

# 4. Observability access
ZIPKIN_URL=$(oc get route rag-learning-zipkin -n nv-nvidia-blueprint-rag -o jsonpath='{.spec.host}')
echo "Zipkin UI: https://$ZIPKIN_URL"
```

---

**Implementation Status**: ✅ **PHASES 1 & 2 COMPLETE**  
**Current Status**: 29/29 pods Running, authentic CPU-only vector database operational  
**Next Step**: Phase 4 (Chart-Verifier Preparation)  
**Document**: `/home/admendez/projects/nvidia-rag-bp/rag/IMPLEMENTATION-CHECKLIST.md`

---

## 🎯 Key Learnings Summary

### **Authentic Chart Structure Discovery**:
- **Milvus deployment** achieved via `ingestor-server -> nv-ingest -> milvus` subchart chain
- **Chart authenticity** preserved by using original NGC nv-ingest v25.6.2 subchart
- **External Milvus** approach would break chart-verifier validation

### **OpenShift Security Context Resolution Pattern**:
```bash
# Standard resolution for SCC violations
oc adm policy add-scc-to-user anyuid system:serviceaccount:NAMESPACE:default
oc rollout restart deployment/DEPLOYMENT_NAME -n NAMESPACE
```

### **GPU Component Naming Convention**:
- **All NGC NIMs** require version suffixes for proper disabling
- **Field names** must match exact subchart structure (check original values.yaml)
- **Verification**: `oc get pods | grep Pending` should return no results

### **Resource Management in Constrained Environments**:
- **Monitor cluster pressure**: High CPU utilization can cause container crashes
- **Staged deployment**: Allow stabilization between resource-intensive operations
- **Conservative resource limits**: Use reduced memory/CPU requests for learning environments