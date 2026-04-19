#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# deploy.sh — Deploy all 8 microservices + Prometheus stack to AKS
#
# Usage:
#   chmod +x scripts/deploy.sh
#   ACR_NAME=yourregistry RESOURCE_GROUP=my-rg AKS_NAME=my-aks ./scripts/deploy.sh
#
# What this script does:
#   1. Connects to your AKS cluster
#   2. Creates dev, test, and monitoring namespaces
#   3. Installs kube-prometheus-stack via Helm
#   4. Replaces REGISTRY_PLACEHOLDER in all K8s manifests with your ACR name
#   5. Deploys all 8 services to dev and test namespaces
#   6. Applies the ServiceMonitor
#   7. Prints access URLs
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ACR_NAME="${ACR_NAME:?ERROR: Set ACR_NAME. Example: export ACR_NAME=myregistry}"
RESOURCE_GROUP="${RESOURCE_GROUP:?ERROR: Set RESOURCE_GROUP. Example: export RESOURCE_GROUP=my-rg}"
AKS_NAME="${AKS_NAME:?ERROR: Set AKS_NAME. Example: export AKS_NAME=my-aks}"
IMAGE_TAG="${IMAGE_TAG:-v1.0}"
REGISTRY="${ACR_NAME}.azurecr.io"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

SERVICES=(
  api-gateway
  user-service
  product-service
  order-service
  payment-service
  inventory-service
  notification-service
  auth-service
)

# ── Step 1: Connect to AKS ────────────────────────────────────────────────────
echo ""
echo "==> [1/6] Connecting to AKS cluster: ${AKS_NAME}"
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --overwrite-existing

kubectl get nodes
echo ""

# ── Step 2: Create namespaces ─────────────────────────────────────────────────
echo "==> [2/6] Creating namespaces: dev, test, monitoring"
kubectl apply -f "${K8S_DIR}/namespaces.yaml"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
echo ""

# ── Step 3: Install kube-prometheus-stack ─────────────────────────────────────
echo "==> [3/6] Installing kube-prometheus-stack via Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "${K8S_DIR}/prometheus-values.yaml" \
  --wait --timeout 10m

echo "  [OK] Prometheus stack installed"
echo ""

# ── Step 4: Deploy all 8 services to dev namespace ───────────────────────────
echo "==> [4/6] Deploying 8 services to 'dev' namespace"
for SERVICE in "${SERVICES[@]}"; do
  MANIFEST="${K8S_DIR}/${SERVICE}.yaml"
  echo "  Deploying: ${SERVICE}"
  # Replace the placeholder image tag with the real registry path
  sed "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g; s|:v1.0|:${IMAGE_TAG}|g" \
    "${MANIFEST}" | kubectl apply -n dev -f -
done
echo ""

# ── Step 5: Deploy all 8 services to test namespace ──────────────────────────
echo "==> [5/6] Deploying 8 services to 'test' namespace"
for SERVICE in "${SERVICES[@]}"; do
  MANIFEST="${K8S_DIR}/${SERVICE}.yaml"
  echo "  Deploying: ${SERVICE}"
  sed "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g; s|:v1.0|:${IMAGE_TAG}|g" \
    "${MANIFEST}" | kubectl apply -n test -f -
done
echo ""

# ── Step 6: Apply ServiceMonitor ──────────────────────────────────────────────
echo "==> [6/6] Applying ServiceMonitor (covers dev + test)"
kubectl apply -f "${K8S_DIR}/servicemonitor-all.yaml"
echo ""

# ── Wait for pods ─────────────────────────────────────────────────────────────
echo "==> Waiting for all pods to be ready..."
kubectl rollout status deployment --namespace dev --timeout=3m
kubectl rollout status deployment --namespace test --timeout=3m
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=========================================="
echo "  DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "  Pods in dev:"
kubectl get pods -n dev -o wide
echo ""
echo "  Pods in test:"
kubectl get pods -n test -o wide
echo ""
echo "  Prometheus targets (should all be UP in ~30s):"
echo "    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &"
echo "    open http://localhost:9090/targets"
echo ""
echo "  Grafana:"
GRAFANA_IP=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "    LoadBalancer IP: ${GRAFANA_IP}"
echo "    (If pending, run: kubectl get svc -n monitoring kube-prometheus-stack-grafana)"
echo "    Login: admin / DevOpsLab2026!"
echo ""
echo "  Quick PromQL to verify all services:"
echo "    sum(up{namespace=~\"dev|test\"}) by (service, namespace)"
echo "    (Should return 1 for every service in both namespaces)"
echo "=========================================="
