# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the NVIDIA RAG Blueprint - a reference solution for a foundational Retrieval Augmented Generation (RAG) pipeline using NVIDIA NIM microservices and GPU-accelerated components. The blueprint enables users to ask questions and receive answers based on enterprise data corpus with multimodal PDF data extraction, hybrid search, and production-ready deployment options.

## Key Architecture Components

The blueprint follows a microservices architecture with the following core components:

- **RAG Server** (`src/nvidia_rag/rag_server/`): LangChain-based orchestration server handling query processing, retrieval, and response generation
- **Ingestor Server** (`src/nvidia_rag/ingestor_server/`): Document ingestion service using NV-Ingest for content extraction
- **Vector Database**: Milvus with GPU acceleration (cuVS) for embeddings storage and retrieval
- **NVIDIA NIMs**: Microservices for LLM inference, embeddings, reranking, and document processing
- **Frontend** (`frontend/`): React-based RAG Playground UI for user interaction

## Development Commands

### Environment Setup
```bash
# Install Python dependencies (requires Python 3.12+)
pip install -e ".[all]"

# Install optional dependencies separately
pip install -e ".[rag]"     # For RAG server functionality
pip install -e ".[ingest]"  # For ingestion server functionality

# Source environment variables for on-prem deployment
source deploy/compose/.env

# Source environment variables for AI Workbench
source variables.env

# Set NGC API key for accessing NVIDIA resources
export NGC_API_KEY="nvapi-..."
echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
```

### Docker Compose Deployment (Single Node)
The blueprint uses multiple Docker Compose files that must be started in sequence:

```bash
# 1. Start NIMs (must be first - other services depend on these)
USERID=$(id -u) docker compose -f deploy/compose/nims.yaml up -d

# 2. Start vector database
docker compose -f deploy/compose/vectordb.yaml up -d

# 3. Start ingestion services
docker compose -f deploy/compose/docker-compose-ingestor-server.yaml up -d

# 4. Start RAG services
docker compose -f deploy/compose/docker-compose-rag-server.yaml up -d

# Build from source when making code changes
docker compose -f deploy/compose/docker-compose-rag-server.yaml up -d --build
docker compose -f deploy/compose/docker-compose-ingestor-server.yaml up -d --build

# Stop all services (reverse order)
docker compose -f deploy/compose/docker-compose-ingestor-server.yaml down
docker compose -f deploy/compose/docker-compose-rag-server.yaml down
docker compose -f deploy/compose/vectordb.yaml down
docker compose -f deploy/compose/nims.yaml down
```

### Helm Deployment (Kubernetes/OpenShift)
```bash
# Deploy complete RAG system using NGC chart
helm upgrade --install rag-learning deploy/helm/rag-server/ \
--namespace rag-learning \
--create-namespace \
--set imagePullSecret.password=$NGC_API_KEY \
--set ngcApiSecret.password=$NGC_API_KEY

# Deploy with custom values for OpenShift/CPU-only environments
helm upgrade --install rag-learning deploy/helm/rag-server/ \
--namespace rag-learning \
--create-namespace \
--values deploy/helm/rag-server/values-openshift.yaml

# Port-forward for local access
oc port-forward -n rag-learning service/rag-learning-frontend 3000:3000 --address 0.0.0.0
oc port-forward -n rag-learning service/rag-learning-rag-server 8081:8081 --address 0.0.0.0

# Cleanup
helm uninstall rag-learning -n rag-learning
```

### Testing and Validation
```bash
# Health check endpoints
curl -X 'GET' 'http://localhost:8081/v1/health?check_dependencies=true' -H 'accept: application/json'
curl -X 'GET' 'http://localhost:8082/v1/health' -H 'accept: application/json'

# Run interactive notebooks for API testing
jupyter lab --allow-root --ip=0.0.0.0 --NotebookApp.token='' --port=8889

# Test document ingestion
curl -X POST "http://localhost:8082/v1/documents" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@./data/sample.pdf"

# Test RAG query
curl -X POST "http://localhost:8081/v1/generate" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is this document about?"}'
```

## Configuration Profiles

The blueprint supports performance and accuracy optimization profiles:

### Accuracy Profile
```bash
source deploy/compose/accuracy_profile.env
```
- Larger chunk sizes (1024)
- Reranking enabled
- Higher top-k values (100)

### Performance Profile
```bash
source deploy/compose/perf_profile.env
```
- Smaller chunk sizes (512)
- Reranking disabled
- Lower top-k values (4)

### CPU-Only Configuration
For environments without GPU resources, disable GPU-specific features:
```bash
export APP_VECTORSTORE_ENABLEGPUINDEX=False
export APP_VECTORSTORE_ENABLEGPUSEARCH=False
export ENABLE_RERANKER=False
export ENABLE_VLM_INFERENCE=false
export ENABLE_GUARDRAILS=False
export ENABLE_REFLECTION=False
```

## Hardware Requirements

- **H100**: 2x H100-80GB (recommended for all features)
- **A100**: 2x A100-80GB minimum (some features limited)
- **B200**: Limited feature support (no VLM, guardrails, self-reflection)
- **CPU-only**: Basic RAG functionality with reduced performance

## Chart Verifier and OpenShift Deployment

This blueprint includes Helm charts designed for enterprise Kubernetes/OpenShift deployment. Key considerations:

### Security Context Constraints
OpenShift requires specific security contexts. Common fixes:
```bash
# Grant anyuid SCC to service accounts that need it
oc adm policy add-scc-to-user anyuid system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT

# Restart deployments to apply SCC changes
oc rollout restart deployment/DEPLOYMENT_NAME -n NAMESPACE
```

### Chart Verifier Validation
```bash
# Run chart-verifier against the Helm chart
chart-verifier verify deploy/helm/rag-server --set profile.vendorType=partner,profile.version=v1.3

# Enable specific checks only during development
chart-verifier verify deploy/helm/rag-server --enable helm-lint,contains-values
```

## API Endpoints

- **RAG Server**: `http://localhost:8081/v1`
- **Ingestor Server**: `http://localhost:8082/v1`
- **RAG Playground UI**: `http://localhost:8090`

## Important Notes

- Always start NIMs first as other services depend on them
- For B200/A100 GPUs, disable GPU indexing in Milvus using CPU-only configuration
- Models are cached in `~/.cache/model-cache` directory
- Use `--build` flag when making source code changes to containers
- NGC API key required for pulling containers and accessing hosted models
- The blueprint supports both on-premises and cloud-hosted NVIDIA models

## File Structure

- `src/nvidia_rag/`: Core Python package with RAG and ingestion servers
- `deploy/`: Docker Compose and Helm deployment configurations
- `notebooks/`: Jupyter notebooks demonstrating API usage
- `frontend/`: React-based user interface
- `docs/`: Comprehensive documentation including customization guides
- `data/`: Sample datasets for testing

## Previous Implementation Reference

The `../docs/attempt-1/` directory contains comprehensive learnings from a previous OpenShift deployment attempt, including:
- SCC configuration patterns
- Resource allocation strategies
- Troubleshooting playbooks
- Chart modification approaches

This documentation should be referenced when deploying to OpenShift environments or when troubleshooting deployment issues.