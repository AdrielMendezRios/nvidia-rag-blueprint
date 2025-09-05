# NVIDIA RAG Blueprint Helm Chart

[![Chart Version](https://img.shields.io/badge/Chart%20Version-v2.2.0-blue.svg)](./Chart.yaml)
[![App Version](https://img.shields.io/badge/App%20Version-v2.2.0-green.svg)](./Chart.yaml)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20%2B-brightgreen.svg)](./Chart.yaml)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.10%2B-red.svg)](./Chart.yaml)

A comprehensive Helm chart for deploying the NVIDIA RAG (Retrieval Augmented Generation) Blueprint on Kubernetes and OpenShift platforms. This chart enables enterprise-grade deployment of a complete RAG pipeline with document ingestion, vector database, and AI-powered question answering capabilities.

## 🎯 Overview

The NVIDIA RAG Blueprint provides a production-ready reference architecture for implementing RAG systems using NVIDIA's AI technologies. This Helm chart packages all components for easy deployment and management in Kubernetes environments.

### Key Features

- **Complete RAG Pipeline**: End-to-end document processing and question answering
- **Scalable Architecture**: Microservices-based design with independent scaling
- **Enterprise Security**: OpenShift SCC compliance and enterprise security standards
- **CPU-Only Support**: Deployment options for environments without GPU resources
- **Observability**: Built-in tracing and monitoring with OpenTelemetry and Zipkin
- **Flexible Deployment**: Support for both cloud-hosted and on-premises AI models

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NVIDIA RAG Blueprint                         │
├─────────────────────────────────────────────────────────────────┤
│  Frontend UI  │  RAG Server  │  Ingestor Server  │  Vector DB   │
│  (React)      │  (LangChain) │  (NV-Ingest)      │  (Milvus)    │
├─────────────────────────────────────────────────────────────────┤
│            Optional NVIDIA NIM Microservices                   │
│   LLM NIM   │  Embedding   │  Reranking  │  VLM NIM           │
├─────────────────────────────────────────────────────────────────┤
│              External Infrastructure                           │
│    MinIO     │    Redis     │  Zipkin  │  OpenTelemetry       │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes 1.20+ or OpenShift 4.10+
- Helm 3.8+
- NGC API Key (for NVIDIA container registry access)
- Sufficient cluster resources (see [Resource Requirements](#resource-requirements))

### Basic Installation

```bash
# Add required repositories
helm repo add minio https://charts.min.io/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install external infrastructure
helm install rag-minio minio/minio -n nvidia-rag --create-namespace \
  --set auth.enabled=false \
  --set persistence.enabled=false

helm install rag-redis bitnami/redis -n nvidia-rag \
  --set auth.enabled=false \
  --set replica.replicaCount=0

# Install NVIDIA RAG Blueprint
helm install rag-blueprint . -n nvidia-rag \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY
```

### OpenShift Installation

```bash
# Use OpenShift-specific values
helm install rag-blueprint . -n nvidia-rag \
  --create-namespace \
  -f values-openshift.yaml \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY
```

## ⚙️ Configuration

### Primary Configuration Files

- `values.yaml` - Default configuration for Kubernetes
- `values-openshift.yaml` - OpenShift-specific overrides with CPU-only settings
- `values.schema.json` - JSON schema for values validation

### Key Configuration Sections

#### Core Application Settings

```yaml
appName: rag-server
namespace: nv-nvidia-blueprint-rag
replicaCount: 1

# Platform-specific settings
platform:
  type: "openshift"  # or "kubernetes"
```

#### NGC Authentication

```yaml
imagePullSecret:
  name: "ngc-secret"
  registry: "nvcr.io"
  username: "$oauthtoken"
  password: ""  # Set via --set or environment variable
  create: true

ngcApiSecret:
  name: "ngc-api"
  password: ""  # NGC API Key
  create: true
```

#### Resource Configuration

```yaml
resources:
  limits:
    memory: "8Gi"
    cpu: "2"
  requests:
    memory: "2Gi"
    cpu: "500m"
```

#### Security Context (OpenShift)

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### Component Configuration

#### Vector Database Settings

```yaml
envVars:
  APP_VECTORSTORE_URL: "http://milvus:19530"
  APP_VECTORSTORE_NAME: "milvus"
  APP_VECTORSTORE_ENABLEGPUINDEX: "False"  # CPU-only
  APP_VECTORSTORE_ENABLEGPUSEARCH: "False" # CPU-only
```

#### LLM Configuration

```yaml
envVars:
  APP_LLM_MODELNAME: "nvidia/llama-3.3-nemotron-super-49b-v1"
  APP_LLM_SERVERURL: "nim-llm:8000"  # Local NIM or external API
```

#### Frontend Configuration

```yaml
frontend:
  enabled: true
  route:
    enabled: true    # OpenShift Routes
    host: ""         # Auto-generated
  ingress:
    enabled: false   # Kubernetes Ingress
```

## 🔧 Deployment Modes

### 1. CPU-Only Deployment (Recommended for Development)

Suitable for environments without GPU resources:

```yaml
# Disable GPU-dependent components
nim-llm:
  enabled: false
nvidia-nim-llama-32-nv-embedqa-1b-v2:
  enabled: false
text-reranking-nim:
  enabled: false

# CPU-only vector database
envVars:
  APP_VECTORSTORE_ENABLEGPUINDEX: "False"
  APP_VECTORSTORE_ENABLEGPUSEARCH: "False"
  ENABLE_RERANKER: "False"
  ENABLE_GUARDRAILS: "False"
```

### 2. GPU-Enabled Deployment (Production)

For environments with NVIDIA GPU resources:

```yaml
# Enable NVIDIA NIMs
nim-llm:
  enabled: true
  resources:
    limits:
      nvidia.com/gpu: 1

nvidia-nim-llama-32-nv-embedqa-1b-v2:
  enabled: true
  resources:
    limits:
      nvidia.com/gpu: 1
```

### 3. Hybrid Deployment

Mix of local and cloud-hosted models:

```yaml
# Use cloud-hosted LLM
envVars:
  APP_LLM_SERVERURL: ""  # Empty for NVIDIA API

# Local embedding model
nvidia-nim-llama-32-nv-embedqa-1b-v2:
  enabled: true
```

## 📊 Resource Requirements

### Minimum Requirements (CPU-Only)

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| RAG Server | 500m | 2Gi | - |
| Ingestor Server | 250m | 1Gi | - |
| Frontend | 100m | 256Mi | - |
| Milvus (CPU) | 500m | 1Gi | 10Gi |
| MinIO | 100m | 256Mi | 20Gi |
| Redis | 100m | 256Mi | 1Gi |
| **Total** | **~1.5 CPU** | **~5Gi** | **~31Gi** |

### Recommended Requirements (GPU-Enabled)

| Component | CPU | Memory | GPU | Storage |
|-----------|-----|--------|-----|---------|
| RAG Server | 2 | 8Gi | - | - |
| Ingestor Server | 1 | 4Gi | - | - |
| NIM LLM | 4 | 16Gi | 1 | - |
| NIM Embedding | 2 | 8Gi | 1 | - |
| Milvus (GPU) | 2 | 4Gi | 1 | 50Gi |
| **Total** | **~11 CPU** | **~40Gi** | **3 GPU** | **~50Gi** |

## 🛡️ Security

### OpenShift Security Context Constraints

The chart is designed to work with OpenShift's default `restricted-v2` SCC. For components that require additional permissions:

```bash
# Grant anyuid SCC if needed
oc adm policy add-scc-to-user anyuid system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT
```

### Image Security

- Uses Red Hat UBI base images where possible
- NVIDIA NGC images for specialized AI workloads
- No privileged containers or root access required
- Comprehensive security context configurations

### Network Security

- All inter-service communication over cluster network
- No external network requirements for core functionality
- Optional ingress/routes for external access
- Support for network policies

## 🔍 Monitoring and Observability

### Built-in Observability Stack

```yaml
# Enable tracing
zipkin:
  enabled: true

opentelemetry-collector:
  enabled: true
  config:
    exporters:
      zipkin:
        endpoint: "http://zipkin:9411/api/v2/spans"
```

### Metrics and Logging

```yaml
envVars:
  LOGLEVEL: "INFO"
  APP_TRACING_ENABLED: "True"
  APP_TRACING_OTLPHTTPENDPOINT: "http://opentelemetry-collector:4318/v1/traces"
```

### Health Checks

All services expose health endpoints:
- RAG Server: `http://rag-server:8081/v1/health`
- Ingestor Server: `http://ingestor-server:8082/v1/health`
- Milvus: `http://milvus:19530/health`

## 🧪 Testing

### Running Chart Tests

```bash
# Execute deployment tests
helm test rag-blueprint -n nvidia-rag

# View test results
kubectl logs -l "app.kubernetes.io/name=nvidia-blueprint-rag,component=test" -n nvidia-rag
```

### Manual Testing

```bash
# Test API endpoints
curl http://localhost:8081/v1/health
curl http://localhost:8082/v1/health

# Upload a document
curl -X POST "http://localhost:8082/v1/documents" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@sample.pdf"

# Query the RAG system
curl -X POST "http://localhost:8081/v1/generate" \
  -H "Content-Type: application/json" \
  -d '{"query": "Summarize the document content"}'
```

## 🔧 Troubleshooting

### Common Issues

#### Image Pull Errors
```bash
# Verify NGC credentials
kubectl get secret ngc-secret -o yaml

# Check image pull secret
kubectl describe pod POD_NAME
```

#### Security Context Violations (OpenShift)
```bash
# Check SCC violations
oc get events --field-selector reason=FailedCreate

# Grant required SCC
oc adm policy add-scc-to-user anyuid system:serviceaccount:NAMESPACE:default
```

#### Resource Constraints
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n nvidia-rag

# Describe resource issues
kubectl describe nodes
```

#### Service Connectivity
```bash
# Test internal connectivity
kubectl run debug --image=busybox -it --rm --restart=Never -- sh
# Inside pod: nslookup milvus
```

### Debugging Commands

```bash
# Check all pods
kubectl get pods -n nvidia-rag

# Examine specific pod
kubectl describe pod POD_NAME -n nvidia-rag
kubectl logs POD_NAME -n nvidia-rag

# Check services
kubectl get svc -n nvidia-rag

# View events
kubectl get events -n nvidia-rag --sort-by='.firstTimestamp'
```

## 📚 API Documentation

### RAG Server API

- **Base URL**: `http://rag-server:8081/v1`
- **Interactive Docs**: `http://localhost:8081/docs` (when port-forwarded)
- **Health**: `GET /v1/health`
- **Generate**: `POST /v1/generate`

### Ingestor Server API

- **Base URL**: `http://ingestor-server:8082/v1`
- **Health**: `GET /v1/health`
- **Upload**: `POST /v1/documents`
- **Status**: `GET /v1/documents/{id}`

## 🔄 Upgrade and Migration

### Upgrading the Chart

```bash
# Update repositories
helm repo update

# Upgrade deployment
helm upgrade rag-blueprint . -n nvidia-rag \
  -f values-openshift.yaml

# Check upgrade status
helm history rag-blueprint -n nvidia-rag
```

### Rollback

```bash
# Rollback to previous version
helm rollback rag-blueprint -n nvidia-rag

# Rollback to specific revision
helm rollback rag-blueprint 2 -n nvidia-rag
```

## 🏢 Enterprise Considerations

### High Availability

- Deploy multiple replicas of stateless components
- Use external, highly available databases
- Implement proper resource quotas and limits
- Configure pod disruption budgets

### Backup and Recovery

```bash
# Backup persistent data
kubectl exec -it milvus-pod -- milvus-backup create

# Backup MinIO data
kubectl exec -it minio-pod -- mc mirror /data /backup
```

### Compliance

- Chart follows Kubernetes best practices
- OpenShift security compliance
- Enterprise-grade documentation
- Comprehensive testing coverage

## 🤝 Contributing

This chart is part of the NVIDIA RAG Blueprint project. For contributions:

1. Follow Helm chart best practices
2. Test with both Kubernetes and OpenShift
3. Update documentation for changes
4. Validate with chart-verifier

## 📄 License

This chart is licensed under the same terms as the NVIDIA RAG Blueprint project. See [LICENSE](./LICENSE) for details.

## 🆘 Support

- **Documentation**: NVIDIA RAG Blueprint docs
- **Issues**: Report via GitHub issues
- **Community**: NVIDIA Developer Forums
- **Enterprise**: NVIDIA Enterprise Support

---

**Chart Maintainers**: NVIDIA RAG Blueprint Team  
**Last Updated**: September 2025  
**Chart Version**: v2.2.0