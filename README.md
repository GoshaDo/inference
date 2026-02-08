# LLM Inference with vLLM

TinyLlama-1.1B served via vLLM on Kubernetes with S3 model storage.

## Architecture

```
K8s Cluster (Run:ai / Kind)
├── Ingress (routes to vLLM)
├── vLLM (GPU inference, loads model from S3)
└── MinIO (optional, local S3-compatible storage)
```

## Project Structure

```
├── makefile                        # Local dev orchestration
├── scripts/
│   ├── init-kind.sh                # Kind cluster + local registry
│   ├── init-nginx.sh               # Nginx ingress controller
│   ├── init-minio.sh               # MinIO + credentials secret
│   ├── init-model.sh               # Runs model-loader k8s job
│   ├── init-vllm.sh                # Deploys vLLM via Helm
│   └── chat.sh                     # Interactive chat CLI
├── helm/vllm/                      # Generic vLLM Helm chart (S3-agnostic)
├── local-dev/values.yaml           # Local Kind overrides (MinIO)
├── run-ai/values.yaml              # Run:ai cluster values (GPU)
├── k8s/model-loader-job.yaml       # Job: HuggingFace → MinIO
└── docker/model-loader/Dockerfile  # Image with mc + huggingface_hub
```

## Deploy on Run:ai

### 1. Create S3 credentials secret

```bash
kubectl create secret generic s3-credentials \
  -n <your-namespace> \
  --from-literal=AWS_ACCESS_KEY_ID=<key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
```

### 2. Upload the model to S3

```bash
pip install huggingface_hub
huggingface-cli download TinyLlama/TinyLlama-1.1B-Chat-v1.0 --local-dir ./model
aws s3 cp --recursive ./model s3://models/TinyLlama-1.1B-Chat-v1.0/
```

Or use the model-loader job (see `k8s/model-loader-job.yaml`).

### 3. Edit values and deploy

```bash
# Edit run-ai/values.yaml with your S3 endpoint, ingress host, etc.
vim run-ai/values.yaml

# Deploy
helm install vllm ./helm/vllm \
  -n <your-namespace> \
  -f run-ai/values.yaml
```

### 4. Test

```bash
curl http://llm.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "TinyLlama-1.1B-Chat-v1.0", "messages": [{"role": "user", "content": "Hello"}]}'
```

If no ingress, use port-forward:

```bash
kubectl port-forward svc/vllm 8000:8000 -n <your-namespace>
curl http://localhost:8000/v1/models
```

## Local Dev (Kind)

Sets up MinIO for S3 storage and loads the model. Useful for testing the pipeline before deploying on Run:ai.

> **Note:** vLLM requires a CUDA GPU. The local Kind deployment will set up MinIO and load the model, but vLLM inference requires a GPU cluster.

```bash
# Prerequisites: docker, kind, helm, kubectl, jq

# Set up local infrastructure (kind + nginx + minio + model)
make deploy

# Check status
make status
```

### Make Targets

| Target | Description |
|--------|-------------|
| `deploy` | Full local setup (kind + nginx + minio + model + vllm chart) |
| `chat` | Interactive chat session (requires running vLLM) |
| `test-inference` | Quick API test |
| `status` | Cluster and pod status |
| `logs-vllm` | Stream vLLM logs |
| `clean` | Tear down cluster |

## API

vLLM exposes an OpenAI-compatible API. Works with any OpenAI SDK client by setting `base_url` to the vLLM endpoint.

```bash
# Chat completions
curl http://<endpoint>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TinyLlama-1.1B-Chat-v1.0",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# List models
curl http://<endpoint>/v1/models
```
