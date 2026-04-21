# E-Commerce Microservices — Prometheus Monitoring Demo

8 Spring Boot microservices deployed across `dev` and `test` namespaces, monitored by a single Prometheus instance via `kube-prometheus-stack`.

## Folder Structure

```
ecommerce-microservices/
├── shared/                   ← One codebase for all 8 services
│   ├── app.js                ← The application (same for every service)
│   ├── package.json
│   └── Dockerfile
├── k8s/
│   ├── namespaces.yaml       ← Creates dev + test namespaces
│   ├── api-gateway.yaml
│   ├── user-service.yaml
│   ├── product-service.yaml
│   ├── order-service.yaml
│   ├── payment-service.yaml
│   ├── inventory-service.yaml
│   ├── notification-service.yaml
│   ├── auth-service.yaml
│   ├── servicemonitor-all.yaml   ← ONE file covers all 8 services in both namespaces
│   └── prometheus-values.yaml    ← Helm values for kube-prometheus-stack
└── scripts/
    ├── build-push.sh         ← Builds + pushes all 8 images to ACR
    └── deploy.sh             ← Full deployment to AKS
```

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Docker | 20+ | Build images locally |
| minikube | 1.32+ | Local Kubernetes cluster |
| `kubectl` | 1.28+ | Deploy and inspect resources |
| `helm` | 3.12+ | Install kube-prometheus-stack |
| Java | 21 | Build Spring Boot fat JAR |

---

## Local Minikube Setup (Quick Start)

### Step 1 — Start minikube

```powershell
minikube start --memory=4096 --cpus=4
minikube status
```

Expected output:
```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

---

### Step 2 — Build the application JAR

```powershell
cd shared
./gradlew bootJar --no-daemon
# Output: build/libs/app.jar
```

---

### Step 3 — Build and push Docker images

Build all 8 service images and push to Docker Hub (replace `<dockerhub-user>` with your username):

```powershell
$REGISTRY = "<dockerhub-user>"
$TAG = "v1.0"
$services = @("api-gateway","user-service","product-service","order-service","payment-service","inventory-service","notification-service","auth-service")

# Login
docker login -u $REGISTRY

# Build & push
foreach ($svc in $services) {
    docker build -t "$REGISTRY/$svc`:$TAG" .
    docker push "$REGISTRY/$svc`:$TAG"
}
```

---

### Step 4 — Create namespaces

```powershell
kubectl apply -f k8s/namespaces.yaml
kubectl get namespaces
```

Expected:
```
NAME          STATUS   AGE
dev           Active   Xs
test          Active   Xs
```

---

### Step 5 — Deploy 3 services to dev

Replace `<dockerhub-user>` with your Docker Hub username:

```powershell
$REGISTRY = "<dockerhub-user>"
$TAG = "v1.0"
$K8S = "k8s"
$services = @("api-gateway","user-service","product-service")

foreach ($svc in $services) {
    $yaml = (Get-Content "$K8S\$svc.yaml" -Raw) `
        -replace 'ecommersimages\.azurecr\.io/ecommerce/app:v1\.0', "$REGISTRY/$svc`:$TAG" `
        -replace '      imagePullSecrets:\r?\n        - name: acr-secret\r?\n', ''
    $yaml | kubectl apply -n dev -f -
}
```

Verify rollout:
```powershell
kubectl rollout status deployment/api-gateway deployment/user-service deployment/product-service -n dev
```

---

### Step 6 — Install Prometheus via Helm

```powershell
# Add the Prometheus community Helm chart repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack with custom values
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace monitoring `
    --values k8s/prometheus-values.yaml `
    --wait
```

Verify installation:
```powershell
kubectl get pods -n monitoring
```

Expected (all pods `Running`):
```
NAME                                                  READY   STATUS    RESTARTS
alertmanager-kube-prometheus-stack-alertmanager-0     2/2     Running   0
kube-prometheus-stack-grafana-xxx                     3/3     Running   0
kube-prometheus-stack-kube-state-metrics-xxx          1/1     Running   0
kube-prometheus-stack-operator-xxx                    1/1     Running   0
kube-prometheus-stack-prometheus-node-exporter-xxx    1/1     Running   0
prometheus-kube-prometheus-stack-prometheus-0         2/2     Running   0
```

---

### Step 7 — Apply ServiceMonitor

```powershell
kubectl apply -f k8s/servicemonitor-all.yaml
kubectl get servicemonitor -n monitoring
```

Expected:
```
NAME                     AGE
ecommerce-all-services   Xs
```

---

### Step 8 — Validate Prometheus is scraping

Port-forward Prometheus UI:
```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Open in browser: **http://localhost:9090/targets**

You should see all deployed services listed with **State: UP**.

Run validation PromQL queries in the browser at **http://localhost:9090/graph**:

```promql
# Check all targets are up
up{namespace="dev"}

# Verify metrics are flowing from api-gateway
jvm_memory_used_bytes{namespace="dev", service="api-gateway"}

# HTTP request rate per service
sum(rate(http_server_requests_seconds_count[5m])) by (uri, namespace)

# Health check endpoint status
http_server_requests_seconds_count{uri="/actuator/health", namespace="dev"}
```

---

### Step 9 — Validate Grafana

Port-forward Grafana:
```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open in browser: **http://localhost:3000**

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `DevOpsLab2026!` |

Go to **Explore → Prometheus** and run:
```promql
up{namespace="dev"}
```
All deployed services should return value `1`.

---

### Step 10 — Full Pod Status Check

```powershell
# Application pods
kubectl get pods -n dev -o wide

# Monitoring stack pods
kubectl get pods -n monitoring

# All services and endpoints
kubectl get svc -n dev
kubectl get svc -n monitoring

# ServiceMonitor picked up by Prometheus operator
kubectl describe servicemonitor ecommerce-all-services -n monitoring
```

---

## Validation Checklist

| Check | Command | Expected Result |
|---|---|---|
| minikube running | `minikube status` | `host: Running` |
| Namespaces exist | `kubectl get ns` | `dev`, `test` listed |
| App pods healthy | `kubectl get pods -n dev` | All `1/1 Running` |
| Prometheus running | `kubectl get pods -n monitoring` | All `Running` |
| ServiceMonitor exists | `kubectl get servicemonitor -n monitoring` | `ecommerce-all-services` |
| Targets UP | http://localhost:9090/targets | State: UP for all services |
| Metrics flowing | PromQL: `up{namespace="dev"}` | Returns `1` for each service |
| Grafana accessible | http://localhost:3000 | Login successful |

---

## Cleanup

```powershell
# Remove application deployments
kubectl delete -f k8s/namespaces.yaml

# Uninstall Prometheus stack
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring

# Stop minikube
minikube stop
```

---

## AKS Production Deployment

For AKS deployment, use the provided scripts:

```bash
export ACR_NAME="yourregistry"
export RESOURCE_GROUP="my-rg"
export AKS_NAME="my-aks-cluster"
export IMAGE_TAG="v1.0"

chmod +x scripts/build-push.sh scripts/deploy.sh
./scripts/build-push.sh
./scripts/deploy.sh
```

## How Prometheus Discovers All Services

```
ServiceMonitor (ONE file)
  └── namespaceSelector: [dev, test]
  └── selector: monitor="true"
        └── finds all 8 services in dev  (8 targets)
        └── finds all 8 services in test (8 targets)
                              TOTAL: 16 targets scraped every 15s
```

All 8 K8s Service manifests have `monitor: "true"` label — no changes needed when adding new services, just add the label.

## Key PromQL Queries

```promql
# Request rate per service and namespace
sum(rate(http_requests_total[5m])) by (service, namespace)

# Error rate per service (%)
sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service, namespace)
/ sum(rate(http_requests_total[5m])) by (service, namespace) * 100

# P99 latency per service
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service, namespace)
)

# Which service is down?
up{namespace=~"dev|test"} == 0

# Compare dev vs test for a specific service
sum(rate(http_requests_total{service="order-service"}[5m])) by (namespace)
```

## DevOps vs Developer Responsibilities

| Task | Who does it |
|---|---|
| Write `app.js` metric code | Developer (done once, shared by all) |
| Set `SERVICE_NAME` env var in Deployment | **DevOps** |
| Add `prometheus.io/scrape` annotations | **DevOps** |
| Manage `ServiceMonitor` | **DevOps** |
| Configure Prometheus, Grafana, Alertmanager | **DevOps** |
| Add new services to monitoring | **DevOps** (just add `monitor: "true"` label) |

## Test Endpoints

Each service exposes these routes:

| Endpoint | What it does |
|---|---|
| `GET /` | Returns service name, env, status |
| `GET /api/data` | Normal response |
| `GET /api/slow` | Random 300ms–2300ms delay (latency testing) |
| `GET /api/error` | 50% chance of 500 error (error rate testing) |
| `GET /api/stress` | 500ms CPU spin (resource testing) |
| `GET /health` | Liveness probe |
| `GET /ready` | Readiness probe |
| `GET /metrics` | Prometheus metrics (scraped every 15s) |

## Generate Test Traffic

```bash
# Port-forward to a service and send traffic
kubectl port-forward -n dev svc/order-service 8080:80 &

# Normal traffic
for i in $(seq 1 50); do curl -s http://localhost:8080/api/data > /dev/null; done

# Trigger errors
for i in $(seq 1 30); do curl -s http://localhost:8080/api/error > /dev/null; done

# Trigger slow requests (watch in Grafana)
for i in $(seq 1 10); do curl -s http://localhost:8080/api/slow & done
```
