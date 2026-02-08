SHELL := /bin/bash
CLUSTER_NAME := inference
CLUSTER_DEPLOYED := $(shell kind get clusters -q | grep -x $(CLUSTER_NAME))

.PHONY: help
help:
	@echo "TinyLlama Local Inference Setup"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy          - Full deployment (cluster + minio + model + vllm)"
	@echo "  make init-kind       - Create Kind cluster with registry"
	@echo "  make init-nginx      - Deploy nginx ingress controller"
	@echo "  make init-minio      - Deploy MinIO to cluster"
	@echo "  make init-model      - Download and upload model to MinIO"
	@echo "  make init-vllm       - Deploy vLLM to cluster"
	@echo "  make chat            - Interactive chat with the LLM"
	@echo "  make test-inference  - Test the inference endpoint"
	@echo "  make clean           - Tear down cluster and registry"
	@echo "  make status          - Show cluster status"
	@echo ""

.PHONY: init-kind
init-kind:
ifndef CLUSTER_DEPLOYED
	@echo "Creating Kind cluster..."
	bash ./scripts/init-kind.sh
else
	@echo "Kind $(CLUSTER_NAME) cluster exists, skipping cluster installation"
endif
	kubectl config use-context kind-$(CLUSTER_NAME)

.PHONY: init-nginx
init-nginx: init-kind
	bash ./scripts/init-nginx.sh

.PHONY: init-minio
init-minio: init-nginx
	bash ./scripts/init-minio.sh

.PHONY: build-model-loader
build-model-loader: init-kind
	docker build -t localhost:5001/model-loader:latest ./docker/model-loader
	docker push localhost:5001/model-loader:latest

.PHONY: init-model
init-model: init-minio build-model-loader
	bash ./scripts/init-model.sh

.PHONY: init-vllm
init-vllm: init-model
	bash ./scripts/init-vllm.sh

.PHONY: deploy
deploy: init-vllm
	@echo ""
	@echo "Deployment complete!"
	@echo "MinIO Console: http://localhost:9001"
	@echo "vLLM API:      http://llm.local  (add to /etc/hosts: 127.0.0.1 llm.local)"
	@echo ""
	@echo "Chat: make chat"

.PHONY: chat
chat:
	@bash ./scripts/chat.sh

.PHONY: test-inference
test-inference:
	@curl -s http://llm.local/v1/completions \
		-H "Content-Type: application/json" \
		-d '{"model": "TinyLlama-1.1B-Chat-v1.0", "prompt": "Hello, how are you?", "max_tokens": 50}' | jq .

.PHONY: status
status:
	@kubectl get nodes 2>/dev/null || echo "Cluster not running"
	@echo ""
	@kubectl get pods -A 2>/dev/null || true
	@echo ""
	@kubectl get svc -A 2>/dev/null || true

.PHONY: logs-vllm
logs-vllm:
	kubectl logs -f deployment/vllm

.PHONY: logs-minio
logs-minio:
	kubectl logs -f deployment/minio

.PHONY: clean
clean:
	-kind delete cluster --name $(CLUSTER_NAME)
	-docker stop kind-registry && docker rm kind-registry
