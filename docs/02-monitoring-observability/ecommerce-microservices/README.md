# E-Commerce Microservices — Prometheus Monitoring Demo

8 Node.js microservices deployed across `dev` and `test` namespaces on AKS, monitored by a single Prometheus instance.

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

| Tool | Purpose |
|---|---|
| Docker | Build images locally |
| Azure CLI (`az`) | Login to ACR and AKS |
| `kubectl` | Deploy to Kubernetes |
| `helm` | Install kube-prometheus-stack |
| AKS cluster | Target Kubernetes cluster |
| Azure Container Registry | Store Docker images |

## Step 1 — Set environment variables

```bash
export ACR_NAME="yourregistry"          # Your ACR name (without .azurecr.io)
export RESOURCE_GROUP="my-rg"           # AKS resource group
export AKS_NAME="my-aks-cluster"        # AKS cluster name
export IMAGE_TAG="v1.0"                 # Image tag (default: v1.0)
```

## Step 2 — Build and push all 8 images

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

This builds ONE shared `Dockerfile` 8 times (once per service tag) and pushes all images to your ACR.

## Step 3 — Deploy everything to AKS

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

This will:
1. Connect to your AKS cluster
2. Create `dev`, `test`, and `monitoring` namespaces
3. Install Prometheus + Grafana + Alertmanager via Helm
4. Deploy all 8 services to both `dev` and `test`
5. Apply the ServiceMonitor (auto-discovers all 16 pods)

## Step 4 — Verify

```bash
# All 16 pods should be Running (8 services × 2 namespaces)
kubectl get pods -n dev
kubectl get pods -n test

# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Open in browser: http://localhost:9090/targets
# You should see 16 targets — all state: UP
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
