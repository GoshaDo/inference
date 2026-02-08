#!/bin/bash
set -o errexit

JOB_NAME="model-loader"

echo "=== Loading model into MinIO ==="

# Delete previous job if it exists
kubectl delete job ${JOB_NAME} --ignore-not-found

# Launch the job
kubectl apply -f k8s/model-loader-job.yaml

echo "Job started. Waiting for pod to be scheduled..."
sleep 5

# Stream logs while the job runs
echo "--- Job logs ---"
kubectl logs -f job/${JOB_NAME} 2>/dev/null || true

# Check result
if kubectl wait --for=condition=complete job/${JOB_NAME} --timeout=10s 2>/dev/null; then
  echo ""
  echo "=== Model loaded successfully ==="
else
  echo ""
  echo "ERROR: Model loading failed. Check logs with: kubectl logs job/${JOB_NAME}"
  exit 1
fi
