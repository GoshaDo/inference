#!/bin/bash
set -o errexit

NAMESPACE="default"
RELEASE_NAME="vllm"

echo "=== Deploying vLLM ==="

# Check if vLLM is already deployed
if helm status ${RELEASE_NAME} -n ${NAMESPACE} &>/dev/null; then
  echo "vLLM already deployed, upgrading..."
  HELM_CMD="helm upgrade"
else
  echo "Installing vLLM..."
  HELM_CMD="helm install"
fi

# Deploy vLLM with local-dev values
${HELM_CMD} ${RELEASE_NAME} ./helm/vllm \
  -n ${NAMESPACE} \
  -f ./local-dev/values.yaml

# Wait for vLLM to be ready (this can take a while as model loads)
echo "Waiting for vLLM to start..."
echo "Note: This may take several minutes as the model loads into memory."
echo "You can watch logs with: kubectl logs -f deployment/vllm"

# Wait for pod to be created first
sleep 10

# Check if pod is running (don't wait for ready as model loading takes time)
kubectl wait --namespace ${NAMESPACE} \
  --for=condition=PodScheduled pod \
  --selector=app.kubernetes.io/name=vllm \
  --timeout=60s || true

echo ""
echo "=== vLLM deployment initiated ==="
echo "API endpoint: http://localhost:8000"
echo ""
echo "Check status with:"
echo "  kubectl get pods"
echo "  kubectl logs -f deployment/vllm"
echo ""
echo "Once ready, test with:"
echo "  curl http://localhost:8000/v1/models"
