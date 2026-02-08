#!/bin/bash
set -o errexit

NAMESPACE="default"
RELEASE_NAME="minio"
BUCKET_NAME="models"
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"

echo "=== Deploying MinIO ==="

# Add MinIO Helm repo
echo "Adding MinIO Helm repository..."
helm repo add minio https://charts.min.io/ 2>/dev/null || true
helm repo update

# Check if MinIO is already deployed
if helm status ${RELEASE_NAME} -n ${NAMESPACE} &>/dev/null; then
  echo "MinIO already deployed, upgrading..."
  HELM_CMD="helm upgrade"
else
  echo "Installing MinIO..."
  HELM_CMD="helm install"
fi

# Deploy MinIO with inline values
${HELM_CMD} ${RELEASE_NAME} minio/minio \
  -n ${NAMESPACE} \
  --set mode=standalone \
  --set replicas=1 \
  --set rootUser=${MINIO_ROOT_USER} \
  --set rootPassword=${MINIO_ROOT_PASSWORD} \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set service.type=NodePort \
  --set service.nodePort=30900 \
  --set consoleService.type=NodePort \
  --set consoleService.nodePort=30901 \
  --set resources.requests.memory=512Mi \
  --set resources.requests.cpu=250m \
  --set resources.limits.memory=1Gi \
  --set resources.limits.cpu=500m \
  --set buckets[0].name=${BUCKET_NAME} \
  --set buckets[0].policy=none \
  --set buckets[0].purge=false

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
kubectl wait --namespace ${NAMESPACE} \
  --for=condition=ready pod \
  --selector=app=minio \
  --timeout=300s

# Wait a bit more for MinIO to fully initialize
sleep 5

# Create MinIO credentials secret for vLLM to use
echo "Creating MinIO credentials secret..."
kubectl create secret generic minio-credentials \
  --namespace ${NAMESPACE} \
  --from-literal=AWS_ACCESS_KEY_ID=${MINIO_ROOT_USER} \
  --from-literal=AWS_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== MinIO deployed ==="
echo "API:     http://localhost:9000"
echo "Console: http://localhost:9001"
echo "Credentials: ${MINIO_ROOT_USER} / ${MINIO_ROOT_PASSWORD}"
