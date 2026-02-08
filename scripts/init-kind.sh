#!/bin/bash
set -o errexit

CLUSTER_NAME="inference"
REG_NAME="kind-registry"
REG_PORT="5001"

echo "=== Setting up Kind cluster for DeepSeek inference ==="

# 1. Create registry container unless it already exists
echo "Setting up local registry..."
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --name "${REG_NAME}" \
    registry:2
  echo "Registry created on port ${REG_PORT}"
else
  echo "Registry already running"
fi

# 2. Create kind cluster with containerd registry config dir enabled
echo "Creating Kind cluster '${CLUSTER_NAME}'..."
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  # MinIO API
  - containerPort: 30900
    hostPort: 9000
    listenAddress: "0.0.0.0"
    protocol: TCP
  # MinIO Console
  - containerPort: 30901
    hostPort: 9001
    listenAddress: "0.0.0.0"
    protocol: TCP
  # Ingress HTTP
  - containerPort: 80
    hostPort: 80
    listenAddress: "0.0.0.0"
    protocol: TCP
  extraMounts:
  # Persistent storage for models (optional, speeds up restarts)
  - hostPath: /tmp/inference-models
    containerPath: /models
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF
  echo "Cluster created"
else
  echo "Cluster '${CLUSTER_NAME}' already exists"
fi

# 3. Add the registry config to the nodes
echo "Configuring registry on nodes..."
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REG_PORT}"
for node in $(kind get nodes --name ${CLUSTER_NAME}); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${REG_NAME}:5000"]
EOF
done

# 4. Connect the registry to the cluster network if not already connected
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
  docker network connect "kind" "${REG_NAME}"
  echo "Registry connected to kind network"
fi

# 5. Document the local registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# 6. Wait for cluster to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Waiting for CoreDNS..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=kube-dns \
  --timeout=60s

echo ""
echo "=== Kind cluster '${CLUSTER_NAME}' is ready ==="
echo "Registry: localhost:${REG_PORT}"
echo "NodePorts configured:"
echo "  - MinIO API:     localhost:9000  (NodePort 30900)"
echo "  - MinIO Console: localhost:9001  (NodePort 30901)"
echo "  - Ingress HTTP:  localhost:80"
