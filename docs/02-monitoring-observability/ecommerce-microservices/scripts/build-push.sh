#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build-push.sh — Build and push all 8 microservice images to Azure Container Registry
# Stack: Java 21 + Spring Boot 3 + Gradle 8.5
#
# Usage:
#   chmod +x scripts/build-push.sh
#   ACR_NAME=yourregistry ./scripts/build-push.sh
#
# Prerequisites:
#   - Java 21 installed (JAVA_HOME set correctly)
#   - Docker running locally
#   - Azure CLI installed and logged in (az login)
#   - ACR_NAME environment variable set
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ACR_NAME="${ACR_NAME:?ERROR: Set ACR_NAME environment variable. Example: export ACR_NAME=myregistry}"
IMAGE_TAG="${IMAGE_TAG:-v1.0}"
REGISTRY="${ACR_NAME}.azurecr.io"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

# ── Verify Java 21 ────────────────────────────────────────────────────────────
echo ""
echo "==> Verifying Java version"
java -version
echo ""

# ── Build the fat JAR once (shared by all services) ──────────────────────────
echo "==> Building Spring Boot fat JAR with Gradle 8.5"
cd "${SHARED_DIR}"
./gradlew bootJar --no-daemon
echo "  [OK] JAR built: build/libs/app.jar"
echo ""

# ── Login to ACR ──────────────────────────────────────────────────────────────
echo "==> Logging into Azure Container Registry: ${REGISTRY}"
az acr login --name "${ACR_NAME}"

# ── Build and push each service image ─────────────────────────────────────────
echo ""
echo "==> Building and pushing ${#SERVICES[@]} images (tag: ${IMAGE_TAG})"
echo ""

for SERVICE in "${SERVICES[@]}"; do
  FULL_IMAGE="${REGISTRY}/ecommerce/${SERVICE}:${IMAGE_TAG}"

  echo "──────────────────────────────────────────"
  echo "  Service : ${SERVICE}"
  echo "  Image   : ${FULL_IMAGE}"
  echo "──────────────────────────────────────────"

  # Docker builds the multi-stage image (compile + runtime)
  # SERVICE_NAME is passed as a build-arg but is also set at runtime via K8s env var
  docker build \
    --build-arg SERVICE_NAME="${SERVICE}" \
    -t "${FULL_IMAGE}" \
    "${SHARED_DIR}"

  docker push "${FULL_IMAGE}"
  echo "  [OK] Pushed: ${FULL_IMAGE}"
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=========================================="
echo "  All 8 images pushed to ${REGISTRY}"
echo "  Stack : Java 21 + Spring Boot 3 + Gradle 8.5"
echo "  Tag   : ${IMAGE_TAG}"
echo ""
echo "  Images:"
for SERVICE in "${SERVICES[@]}"; do
  echo "    ${REGISTRY}/ecommerce/${SERVICE}:${IMAGE_TAG}"
done
echo ""
echo "  Next step: run ./scripts/deploy.sh"
echo "=========================================="
