# Prometheus: Beginner to Practitioner Guide
## From Zero Knowledge → Sample Project → K8s Monitoring → Azure VM Monitoring → 20 Real Scenarios

> **Who this guide is for:** You know how to deploy apps on AKS with Helm and on Azure VMs, but you have never used Prometheus before. This guide explains every concept in plain English and walks you step by step through a real project.

---

## Table of Contents

1. [What is Prometheus? (Explained Simply)](#1-what-is-prometheus-explained-simply)
2. [How Prometheus Works — The Big Picture](#2-how-prometheus-works--the-big-picture)
3. [Simple Sample Project — Deploy & Monitor a Node.js App](#3-simple-sample-project--deploy--monitor-a-nodejs-app)
4. [Install Prometheus on Kubernetes (AKS with Helm)](#4-install-prometheus-on-kubernetes-aks-with-helm)
5. [Install Prometheus on Azure VMs](#5-install-prometheus-on-azure-vms)
6. [PromQL — How to Query Your Metrics](#6-promql--how-to-query-your-metrics)
7. [10 Scenarios: Kubernetes Failures & Successes](#7-10-scenarios-kubernetes-failures--successes)
8. [10 Scenarios: Azure VM Failures & Successes](#8-10-scenarios-azure-vm-failures--successes)
9. [Common Beginner Mistakes & Fixes](#9-common-beginner-mistakes--fixes)
10. [Quick Reference Cheat Sheet](#10-quick-reference-cheat-sheet)

---

## 1. What is Prometheus? (Explained Simply)

### Think of it like a health checkup machine

Your app and your servers are doing things every second — using CPU, handling requests, consuming memory. Without monitoring, you only find out something is wrong when users complain.

**Prometheus solves this by:**
1. Going to your app/server every 15 seconds and asking: "How are you doing?"
2. The app/server answers with numbers (called **metrics**): "I handled 1500 requests. My memory is at 400MB. I had 3 errors."
3. Prometheus stores all these numbers with timestamps
4. You can then ask Prometheus: "Show me the error rate over the last 1 hour" → it shows you exactly what happened

### What is a metric?

A metric is a number with a name and some labels (tags). Example:

```
http_requests_total{method="GET", status="200", app="my-nodejs-app"} 1500
http_requests_total{method="POST", status="500", app="my-nodejs-app"} 3
node_memory_MemAvailable_bytes{instance="vm-01"} 4294967296
```

Breaking this down:
- `http_requests_total` → the **metric name** (what we are measuring)
- `{method="GET", status="200"}` → **labels** (extra context/tags)
- `1500` → the **current value**

### 4 Types of metrics (simple explanation)

| Type | What it is | Real example |
|---|---|---|
| **Counter** | Only goes UP (like an odometer) | Total HTTP requests: 1500 → 1501 → 1502 |
| **Gauge** | Goes UP and DOWN (like a thermometer) | Memory used: 400MB → 450MB → 380MB |
| **Histogram** | Records how long things take, grouped in buckets | 80% of requests < 100ms, 95% < 500ms |
| **Summary** | Like histogram but pre-calculates percentiles | P99 latency = 1.2 seconds |

### Key Terms (Beginner Dictionary)

| Term | Plain English meaning |
|---|---|
| **Scrape** | Prometheus visiting your app to collect metrics |
| **Target** | Any server/app that Prometheus scrapes |
| **Exporter** | A translator that reads system data and converts it to Prometheus format (e.g., Node Exporter reads Linux OS metrics) |
| **PromQL** | The query language to ask Prometheus questions about your metrics |
| **Alertmanager** | The component that sends notifications (Slack, email) when alerts fire |
| **Alert Rule** | A condition you define: "If CPU > 90% for 5 minutes → fire alert" |
| **Recording Rule** | A pre-computed query saved as a new metric (for performance) |
| **/metrics endpoint** | The URL on your app where Prometheus reads data from (e.g., http://myapp:8080/metrics) |
| **Label** | A key=value tag attached to a metric (like metadata) |
| **Cardinality** | The number of unique metric series — high cardinality = many labels = more memory |

---

## 2. How Prometheus Works — The Big Picture

```
                        ┌─────────────────────────────────────────┐
                        │           YOUR INFRASTRUCTURE           │
                        │                                         │
  ┌──────────────┐      │  ┌──────────────┐  ┌────────────────┐  │
  │  Prometheus  │ ───scrapes──► Node Exporter  │  │  Your App      │  │
  │  (stores     │      │  │ (OS metrics: │  │ /metrics       │  │
  │   metrics)   │      │  │  CPU, RAM,   │  │ (app metrics:  │  │
  └──────┬───────┘      │  │  disk, net)  │  │  req/s, errors)│  │
         │              │  └──────────────┘  └────────────────┘  │
         │ stores       │                                         │
         │              │  ┌──────────────────────────────────┐   │
         ▼              │  │  kube-state-metrics (K8s only)   │   │
  ┌──────────────┐      │  │  (pod status, deployments, etc.) │   │
  │  Time-series │      │  └──────────────────────────────────┘   │
  │  Database    │      └─────────────────────────────────────────┘
  └──────┬───────┘
         │ query (PromQL)
         ▼
  ┌──────────────┐      ┌──────────────────┐
  │   Grafana    │      │  Alertmanager    │
  │  (dashboards)│      │  (Slack, email,  │
  └──────────────┘      │   PagerDuty)     │
                        └──────────────────┘
```

### How Prometheus collects data (Pull Model)

Prometheus works by **pulling** data from your apps — it visits a special URL called `/metrics` on your app every 15 seconds and reads all the numbers.

Your app's `/metrics` URL looks like this:
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",status="200"} 1500
http_requests_total{method="POST",status="500"} 3
# HELP process_resident_memory_bytes Memory in use
# TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 52428800
```

**This is the standard Prometheus exposition format.** Libraries exist for every language (Node.js, Python, Java, Go) that expose this automatically.

---

## 3. Sample Project — 8 Microservices Monitored by Prometheus

> **Real-world scenario:** You are a DevOps engineer on a team that built an e-commerce platform. There are **8 microservices** deployed across two namespaces (`dev` and `test`) in the same AKS cluster. Developers wrote the services — your job is to configure Prometheus to monitor all of them **without touching a single line of application code**.

### 3.0 Architecture Overview

```
AKS Cluster
├── namespace: dev  (developers actively working here)
│   ├── api-gateway        (pod) → routes traffic to all services
│   ├── user-service        (pod) → user registration/login
│   ├── product-service     (pod) → product catalog
│   ├── order-service       (pod) → order placement
│   ├── payment-service     (pod) → payment processing
│   ├── inventory-service   (pod) → stock management
│   ├── notification-service(pod) → sends emails/SMS
│   └── auth-service        (pod) → JWT token management
│
├── namespace: test  (same 8 services, QA testing here)
│   └── (same 8 pods as dev)
│
└── namespace: monitoring
    ├── Prometheus  ← scrapes ALL 8 pods in dev AND test automatically
    ├── Grafana     ← dashboards
    └── Alertmanager← sends Slack/email alerts
```

**Key DevOps insight:** Prometheus discovers ALL pods in both namespaces automatically using a **single scrape config**. You never touch app code.

---

### 3.1 The Shared Application Template (Developer's responsibility)

> **As a DevOps engineer**, you don't write this code. But you need to know what it looks like so you can verify the `/metrics` endpoint exists and understand what labels developers expose.

All 8 microservices share the same pattern — only the `SERVICE_NAME` environment variable changes:

**File: `shared/app.js`** (used by all 8 services)
```javascript
const express = require('express');
const promClient = require('prom-client');

const app = express();

// SERVICE_NAME is injected by Kubernetes as an env variable
// DevOps sets this in the Deployment manifest — no code change needed
const SERVICE_NAME = process.env.SERVICE_NAME || 'unknown-service';
const ENV = process.env.APP_ENV || 'dev';   // 'dev' or 'test'

// ─── Prometheus Setup ────────────────────────────────────────────────────────
const register = new promClient.Registry();
register.setDefaultLabels({ service: SERVICE_NAME, env: ENV });
promClient.collectDefaultMetrics({ register });

// Counter: HTTP requests (labelled with service name automatically)
const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

// Histogram: request duration
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  registers: [register],
});

// Gauge: active connections
const activeConnections = new promClient.Gauge({
  name: 'active_connections',
  help: 'Current active connections',
  registers: [register],
});

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  if (req.path === '/metrics' || req.path === '/health') return next();
  activeConnections.inc();
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    httpRequestsTotal.inc({ method: req.method, route: req.path, status_code: res.statusCode });
    end({ method: req.method, route: req.path, status_code: res.statusCode });
    activeConnections.dec();
  });
  next();
});

// ─── Routes (each service adds its own business logic here) ─────────────────
app.get('/', (req, res) => res.json({ service: SERVICE_NAME, env: ENV, status: 'running' }));
app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));
app.get('/slow', async (req, res) => {
  await new Promise(r => setTimeout(r, Math.floor(Math.random() * 2000) + 300));
  res.json({ service: SERVICE_NAME, message: 'slow response simulated' });
});
app.get('/error', (req, res) => {
  Math.random() < 0.5
    ? res.status(500).json({ error: 'simulated error', service: SERVICE_NAME })
    : res.json({ ok: true, service: SERVICE_NAME });
});

// ─── /metrics endpoint — THIS IS WHAT PROMETHEUS SCRAPES ────────────────────
app.get('/metrics', async (req, res) => {
  res.setHeader('Content-Type', register.contentType);
  res.end(await register.metrics());
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`[${SERVICE_NAME}] running on :${PORT} | env=${ENV}`));
```

**File: `shared/package.json`**
```json
{
  "name": "ecommerce-service",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": { "start": "node app.js" },
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.1.0"
  }
}
```

**File: `shared/Dockerfile`** (one Dockerfile for all 8 services)
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY app.js ./
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 8080
CMD ["node", "app.js"]
```

---

### 3.2 Build and push all 8 images

> **DevOps task:** Build one image per service with a different tag, or use a single image and control behavior via environment variables.

```bash
ACR_NAME="yourregistry"   # Your Azure Container Registry name
az acr login --name $ACR_NAME

# All 8 services use the SAME Dockerfile — SERVICE_NAME is set by K8s env var
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

for SERVICE in "${SERVICES[@]}"; do
  echo "Building: $SERVICE"
  docker build \
    -t ${ACR_NAME}.azurecr.io/ecommerce/${SERVICE}:v1.0 \
    ./shared/
  docker push ${ACR_NAME}.azurecr.io/ecommerce/${SERVICE}:v1.0
done

echo "All 8 images pushed!"
```

---

### 3.3 Kubernetes manifests — DevOps controls everything here

> **This is your zone as a DevOps engineer.** You set `SERVICE_NAME`, resource limits, health checks, replicas, and — most importantly — the Prometheus scrape annotations. No developer involvement needed.

**File: `k8s/services-template.yaml`** — Shows 2 of the 8 services; all others follow the same pattern:

```yaml
# ════════════════════════════════════════════════════════════
# 1. api-gateway  (dev namespace)
# ════════════════════════════════════════════════════════════
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: dev
  labels:
    app: api-gateway
    team: platform
    monitored-by: prometheus   # custom label for grouping in Grafana
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        team: platform
      annotations:
        # ── DevOps adds these 3 lines — this is ALL you need for Prometheus ──
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: api-gateway
          image: yourregistry.azurecr.io/ecommerce/api-gateway:v1.0
          ports:
            - containerPort: 8080
          env:
            - name: SERVICE_NAME         # DevOps sets this — no code change
              value: "api-gateway"
            - name: APP_ENV
              value: "dev"
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          livenessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: dev
  labels:
    app: api-gateway
    monitor: "true"          # used by ServiceMonitor selector below
spec:
  selector:
    app: api-gateway
  ports:
    - name: http
      port: 80
      targetPort: 8080
  type: ClusterIP
---
# ════════════════════════════════════════════════════════════
# 2. order-service  (dev namespace)
# ════════════════════════════════════════════════════════════
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: dev
  labels:
    app: order-service
    team: orders
    monitored-by: prometheus
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
        team: orders
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: order-service
          image: yourregistry.azurecr.io/ecommerce/order-service:v1.0
          ports:
            - containerPort: 8080
          env:
            - name: SERVICE_NAME
              value: "order-service"
            - name: APP_ENV
              value: "dev"
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          livenessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: dev
  labels:
    app: order-service
    monitor: "true"
spec:
  selector:
    app: order-service
  ports:
    - name: http
      port: 80
      targetPort: 8080
  type: ClusterIP
```

> **All 8 services follow this exact pattern.** Only `name`, `image`, and `SERVICE_NAME` env var change. Copy-paste and update for:
> `user-service`, `product-service`, `payment-service`, `inventory-service`, `notification-service`, `auth-service`.

---

### 3.4 Single ServiceMonitor — covers ALL 8 services in BOTH namespaces

> **Key DevOps concept:** You write **ONE** ServiceMonitor object and Prometheus discovers all services with `monitor: "true"` in both `dev` and `test` namespaces automatically.

**File: `k8s/servicemonitor-all.yaml`**
```yaml
# This ONE object tells Prometheus to scrape ALL 8 services
# in BOTH dev and test namespaces — no changes needed when adding new services
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ecommerce-all-services
  namespace: monitoring
  labels:
    release: kube-prometheus-stack   # Must match your Helm release name
spec:
  # Watch BOTH namespaces — dev and test
  namespaceSelector:
    matchNames:
      - dev
      - test

  # Only scrape services that have label: monitor="true"
  selector:
    matchLabels:
      monitor: "true"

  endpoints:
    - port: http
      path: /metrics
      interval: 15s
      # Add namespace and service labels to every metric
      relabelings:
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
        - sourceLabels: [__meta_kubernetes_service_name]
          targetLabel: service
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod
```

---

### 3.5 Deploy everything

```bash
# Create namespaces
kubectl create namespace dev
kubectl create namespace test

# Deploy all 8 services to dev
kubectl apply -f k8s/services-template.yaml -n dev
# (repeat apply for all 8 service yamls)

# Copy same manifests to test namespace (change APP_ENV=test)
# kubectl apply -f k8s/services-test.yaml -n test

# Apply the single ServiceMonitor (covers both namespaces)
kubectl apply -f k8s/servicemonitor-all.yaml

# Verify all 8 pods are running in dev
kubectl get pods -n dev
# Expected: 8 pods (2 replicas each = 16 pod instances total)
# api-gateway-xxx          Running
# user-service-xxx         Running
# product-service-xxx      Running
# order-service-xxx        Running
# payment-service-xxx      Running
# inventory-service-xxx    Running
# notification-service-xxx Running
# auth-service-xxx         Running

# Verify all 8 pods are running in test
kubectl get pods -n test

# Verify Prometheus sees all targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Open: http://localhost:9090/targets
# You should see 16 targets (8 services × 2 namespaces), all "UP"
```

---

### 3.6 Verify Prometheus is scraping all services

```bash
# Check targets via API (shows all scraped services)
curl -s http://localhost:9090/api/v1/targets | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    ns  = t['labels'].get('namespace','?')
    svc = t['labels'].get('service','?')
    health = t['health']
    print(f'  [{health}] namespace={ns}  service={svc}')
" | sort

# Expected output (16 lines — 8 services × 2 namespaces):
# [up] namespace=dev   service=api-gateway
# [up] namespace=dev   service=auth-service
# [up] namespace=dev   service=inventory-service
# [up] namespace=dev   service=notification-service
# [up] namespace=dev   service=order-service
# [up] namespace=dev   service=payment-service
# [up] namespace=dev   service=product-service
# [up] namespace=dev   service=user-service
# [up] namespace=test  service=api-gateway
# ... (same 8 for test)

# ─── Useful PromQL queries for 8-service monitoring ─────────────────────────

# Request rate for ALL services (grouped by service and namespace)
sum(rate(http_requests_total[5m])) by (service, namespace)

# Error rate per service (which service has most errors?)
sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service, namespace)
  /
sum(rate(http_requests_total[5m])) by (service, namespace)
* 100

# P99 latency per service
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# Compare dev vs test error rates for a specific service
sum(rate(http_requests_total{status_code=~"5..", service="order-service"}[5m])) by (namespace)
```

---

### 3.7 What you see at `/metrics` for any service

```bash
# Port-forward to order-service in dev
kubectl port-forward -n dev svc/order-service 8081:80 &
curl http://localhost:8081/metrics | grep -v "^#"
```
```
# Output (labels automatically include service="order-service", env="dev")
http_requests_total{method="GET",route="/",status_code="200",service="order-service",env="dev"} 42
http_requests_total{method="GET",route="/error",status_code="500",service="order-service",env="dev"} 7
http_request_duration_seconds_bucket{le="0.1",service="order-service",env="dev",...} 38
active_connections{service="order-service",env="dev"} 0
process_resident_memory_bytes{service="order-service",env="dev"} 52428800
```

> **DevOps takeaway:** The `service` and `env` labels come from `register.setDefaultLabels()` in the app code (set by the `SERVICE_NAME` and `APP_ENV` env vars that **DevOps controls** via the Deployment manifest). Developers write the metrics pattern once; DevOps controls what name/environment each pod reports.

---

## 4. Install Prometheus on Kubernetes (AKS with Helm)

### 4.1 Connect to your AKS cluster

```bash
# Login to Azure
az login

# Get AKS credentials
az aks get-credentials \
  --resource-group YOUR_RESOURCE_GROUP \
  --name YOUR_AKS_CLUSTER_NAME

# Verify connection
kubectl get nodes
```

### 4.2 Add Helm repos

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 4.3 Create the values file

```yaml
# prometheus-stack-values.yaml

# ─── Prometheus ──────────────────────────────────────────────────────────────
prometheus:
  prometheusSpec:
    # How long to keep data
    retention: 30d
    retentionSize: "10GB"

    # Scrape ALL pods with annotation prometheus.io/scrape="true"
    # This lets Prometheus discover your app automatically
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector: {}
    serviceMonitorSelector: {}

    # Resources
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi

    # Storage (persistent volume for metrics data)
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

    # Extra scrape configs (for apps with prometheus.io/scrape annotation)
    additionalScrapeConfigs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          # Only scrape pods with prometheus.io/scrape="true"
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          # Use the path from annotation (default: /metrics)
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          # Use the port from annotation
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          # Add pod labels as Prometheus labels
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: pod

# ─── Grafana ─────────────────────────────────────────────────────────────────
grafana:
  adminUser: admin
  adminPassword: "YourGrafanaPassword123!"

  service:
    type: LoadBalancer   # For AKS (gets a public IP)

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          isDefault: true
          access: proxy

  # Pre-import dashboards
  dashboards:
    default:
      node-exporter-full:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      k8s-cluster:
        gnetId: 315
        revision: 3
        datasource: Prometheus
      k8s-pods:
        gnetId: 13770
        revision: 1
        datasource: Prometheus

# ─── Alertmanager ────────────────────────────────────────────────────────────
alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 128Mi
      limits:
        memory: 256Mi

  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'slack-notifications'
      routes:
        - receiver: 'slack-notifications'
          matchers:
            - alertname =~ ".*"
    receivers:
      - name: 'slack-notifications'
        slack_configs:
          - api_url: 'YOUR_SLACK_WEBHOOK_URL'   # Replace with your Slack webhook
            channel: '#alerts'
            text: |
              {{ range .Alerts }}
              *Alert:* {{ .Annotations.summary }}
              *Description:* {{ .Annotations.description }}
              *Severity:* {{ .Labels.severity }}
              {{ end }}
    inhibit_rules:
      - source_matchers: [severity="critical"]
        target_matchers: [severity="warning"]
        equal: ['alertname', 'namespace']

# ─── Node Exporter (installs on every K8s node) ──────────────────────────────
nodeExporter:
  enabled: true

# ─── kube-state-metrics (K8s object state metrics) ───────────────────────────
kubeStateMetrics:
  enabled: true

# ─── Default alert rules ─────────────────────────────────────────────────────
defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: false         # Only if you have etcd monitoring access
    configReloaders: true
    general: true
    k8sContainerCpuUsageSecondsTotal: true
    k8sContainerMemoryCache: true
    k8sContainerMemoryRss: true
    k8sPodOwner: true
    kubeApiserverAvailability: true
    kubeApiserverBurnrate: true
    kubeApiserverHistogram: true
    kubeApiserverSlos: true
    kubeControllerManager: false
    kubelet: true
    kubePrometheusGeneral: true
    kubePrometheusNodeRecording: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeSchedulerAlerting: false
    kubeSchedulerRecording: false
    kubeStateMetrics: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true
```

### 4.4 Install the stack

```bash
# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-stack-values.yaml \
  --wait --timeout 10m

# Verify everything is running
kubectl get pods -n monitoring

# Expected output (all should be Running):
# NAME                                                   READY   STATUS
# alertmanager-kube-prometheus-stack-alertmanager-0      2/2     Running
# kube-prometheus-stack-grafana-xxxx                     3/3     Running
# kube-prometheus-stack-kube-state-metrics-xxxx          1/1     Running
# kube-prometheus-stack-operator-xxxx                    1/1     Running
# kube-prometheus-stack-prometheus-node-exporter-xxxx    1/1     Running  (one per node)
# prometheus-kube-prometheus-stack-prometheus-0          2/2     Running
```

### 4.5 Access Prometheus and Grafana

```bash
# Access Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
echo "Prometheus: http://localhost:9090"

# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
echo "Grafana: http://localhost:3000 (admin / YourGrafanaPassword123!)"

# OR get the LoadBalancer external IP for Grafana
kubectl get svc kube-prometheus-stack-grafana -n monitoring
# Wait for EXTERNAL-IP to appear, then open http://<EXTERNAL-IP>
```

### 4.6 Verify Prometheus is scraping your app

```bash
# After deploying your sample app to the 'demo' namespace:
# Open Prometheus UI: http://localhost:9090

# Go to: Status > Targets
# You should see your app listed as a target with state "UP"

# Or check via API
curl http://localhost:9090/api/v1/targets | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{t['labels']['job']}: {t['health']} - {t['labels'].get('pod','')}\")
"

# Try your first query in Prometheus UI (Status > Graph):
myapp_http_requests_total
```

---

## 5. Install Prometheus on Azure VMs

### 5.1 Architecture

```
Azure VM - Monitoring Server          Azure VM - App Server(s)
├── Prometheus (port 9090)            ├── Node Exporter (port 9100)
├── Alertmanager (port 9093)          └── Your App (port 8080, /metrics)
└── Grafana (port 3000)
```

### 5.2 Create Azure VMs

```bash
# Create resource group
az group create --name prometheus-demo-rg --location eastus

# Monitoring VM (Prometheus + Grafana live here)
az vm create \
  --resource-group prometheus-demo-rg \
  --name monitoring-vm \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys

# App VM (your Node.js app runs here)
az vm create \
  --resource-group prometheus-demo-rg \
  --name app-vm-01 \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys

# Open ports on Monitoring VM
az vm open-port -g prometheus-demo-rg -n monitoring-vm --port 9090  # Prometheus
az vm open-port -g prometheus-demo-rg -n monitoring-vm --port 9093  # Alertmanager
az vm open-port -g prometheus-demo-rg -n monitoring-vm --port 3000  # Grafana

# Open ports on App VM
az vm open-port -g prometheus-demo-rg -n app-vm-01 --port 8080  # App
az vm open-port -g prometheus-demo-rg -n app-vm-01 --port 9100  # Node Exporter

# Get IPs
MONITORING_IP=$(az vm show -d -g prometheus-demo-rg -n monitoring-vm --query publicIps -o tsv)
APP_IP=$(az vm show -d -g prometheus-demo-rg -n app-vm-01 --query publicIps -o tsv)
APP_PRIVATE_IP=$(az vm show -d -g prometheus-demo-rg -n app-vm-01 --query privateIps -o tsv)

echo "Monitoring VM: $MONITORING_IP"
echo "App VM: $APP_IP  (Private: $APP_PRIVATE_IP)"
```

### 5.3 Install Node Exporter and sample app on App VM

```bash
ssh azureuser@$APP_IP

# ─── Install Node Exporter ────────────────────────────────────────────────
NODE_EXPORTER_VERSION="1.7.0"
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz -C /tmp/
sudo mv /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

sudo tee /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
echo "Node Exporter running: $(curl -s http://localhost:9100/metrics | head -3)"

# ─── Install Node.js and deploy sample app ───────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

mkdir -p /opt/prometheus-demo-app
cd /opt/prometheus-demo-app

# Create package.json
cat > package.json << 'EOF'
{
  "name": "prometheus-demo-app",
  "version": "1.0.0",
  "main": "app.js",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.1.0"
  }
}
EOF

# Create app.js (same as shown in Section 3.1)
cat > app.js << 'APPEOF'
const express = require('express');
const promClient = require('prom-client');

const app = express();
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestsTotal = new promClient.Counter({
  name: 'myapp_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new promClient.Histogram({
  name: 'myapp_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  registers: [register],
});

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    httpRequestsTotal.inc({ method: req.method, route: req.path, status_code: res.statusCode });
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

app.get('/', (req, res) => res.json({ message: 'Hello from VM app!', timestamp: new Date() }));
app.get('/slow', async (req, res) => {
  await new Promise(r => setTimeout(r, Math.floor(Math.random() * 2000) + 500));
  res.json({ message: 'slow response' });
});
app.get('/error', (req, res) => {
  Math.random() < 0.7 ? res.status(500).json({ error: 'simulated error' }) : res.json({ ok: true });
});
app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.get('/metrics', async (req, res) => {
  res.setHeader('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(8080, () => console.log('App on port 8080 — metrics at /metrics'));
APPEOF

npm install
sudo useradd -rs /bin/false appuser

sudo tee /etc/systemd/system/prometheus-demo-app.service << 'EOF'
[Unit]
Description=Prometheus Demo App
After=network.target
[Service]
User=appuser
WorkingDirectory=/opt/prometheus-demo-app
ExecStart=/usr/bin/node app.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo chown -R appuser:appuser /opt/prometheus-demo-app
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus-demo-app

echo "App running: $(curl -s http://localhost:8080/health)"
echo "Metrics: $(curl -s http://localhost:8080/metrics | grep myapp_http | head -3)"
exit
```

### 5.4 Install Prometheus on Monitoring VM

```bash
ssh azureuser@$MONITORING_IP

PROMETHEUS_VERSION="2.49.0"
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xvfz prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz -C /tmp/
sudo mv /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo mv /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/

sudo mkdir -p /etc/prometheus/rules /var/lib/prometheus
sudo useradd -rs /bin/false prometheus

# Create Prometheus configuration
# IMPORTANT: Replace APP_PRIVATE_IP with the actual private IP of your App VM
sudo tee /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    environment: 'production'
    region: 'eastus'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  # Prometheus monitors itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Monitoring VM OS metrics
  - job_name: 'monitoring-vm'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          vm_name: 'monitoring-vm'

  # App VM OS metrics
  - job_name: 'app-vm-01'
    static_configs:
      - targets: ['APP_PRIVATE_IP:9100']    # <-- REPLACE THIS
        labels:
          vm_name: 'app-vm-01'

  # App VM application metrics
  - job_name: 'prometheus-demo-app'
    static_configs:
      - targets: ['APP_PRIVATE_IP:8080']    # <-- REPLACE THIS
        labels:
          vm_name: 'app-vm-01'
          app: 'prometheus-demo-app'
    metrics_path: '/metrics'
EOF

# Create alert rules
sudo tee /etc/prometheus/rules/alerts.yml << 'EOF'
groups:
  - name: vm-alerts
    interval: 30s
    rules:
      - alert: HighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU is {{ $value | printf \"%.1f\" }}%"

      - alert: HighMemory
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High Memory on {{ $labels.instance }}"
          description: "Memory is {{ $value | printf \"%.1f\" }}% used"

      - alert: DiskAlmostFull
        expr: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint="/"} / node_filesystem_size_bytes{fstype!="tmpfs",mountpoint="/"})) * 100 > 80
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk almost full on {{ $labels.instance }}"

      - alert: AppHighErrorRate
        expr: rate(myapp_http_requests_total{status_code=~"5.."}[5m]) / rate(myapp_http_requests_total[5m]) * 100 > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate: {{ $value | printf \"%.1f\" }}%"
EOF

sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

sudo tee /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle \
  --web.listen-address=0.0.0.0:9090
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
echo "Prometheus: $(curl -s http://localhost:9090/-/ready)"
```

### 5.5 Install Grafana on Monitoring VM

```bash
# Still on monitoring-vm
sudo apt-get install -y apt-transport-https software-properties-common wget gnupg
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update && sudo apt-get install -y grafana

# Pre-configure Prometheus datasource
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo tee /etc/grafana/provisioning/datasources/prometheus.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
EOF

sudo tee /etc/grafana/grafana.ini << 'EOF'
[server]
http_port = 3000
[security]
admin_user = admin
admin_password = YourGrafanaPassword123!
[unified_alerting]
enabled = true
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
echo "Grafana: http://$MONITORING_IP:3000"
exit
```

### 5.6 Verify everything is working

```bash
# 1. Prometheus targets — open in browser:
#    http://<MONITORING_IP>:9090/targets
#    All targets should show state: UP (green)

# 2. Test a query in Prometheus (Status > Graph):
#    up                               → should show 1 for all targets
#    myapp_http_requests_total        → should show counter increasing

# 3. Generate some traffic to see metrics moving:
for i in {1..50}; do
  curl -s http://$APP_IP:8080/ > /dev/null
  curl -s http://$APP_IP:8080/slow > /dev/null &
  curl -s http://$APP_IP:8080/error > /dev/null
done
echo "Traffic generated!"
```

---

## 6. PromQL — How to Query Your Metrics

> PromQL is the language you use to ask Prometheus questions. You run PromQL queries in the **Prometheus UI** (Status > Graph) or in **Grafana** (Explore tab).

### 6.1 Basic query types

```promql
# ─── INSTANT QUERY: "What is the current value?" ───────────────────────────

# Show ALL time series for a metric
up

# Filter by label (show only app-vm-01)
up{job="app-vm-01"}

# Show current HTTP request count for our app
myapp_http_requests_total

# Show only 5xx errors
myapp_http_requests_total{status_code=~"5.."}

# ─── RANGE QUERY: "How did the value change over time?" ────────────────────

# Show last 5 minutes of CPU data
node_cpu_seconds_total[5m]

# ─── RATE: "How fast is a counter increasing per second?" ──────────────────
# Most important function! Use rate() for counters, NEVER use a counter directly in graphs.

# HTTP requests per second (averaged over last 5 minutes)
rate(myapp_http_requests_total[5m])

# ─── AGGREGATION ────────────────────────────────────────────────────────────

# Total requests per second across all pods
sum(rate(myapp_http_requests_total[5m]))

# Requests per second grouped by status code
sum(rate(myapp_http_requests_total[5m])) by (status_code)

# Average memory across all VMs
avg(node_memory_MemAvailable_bytes)
```

### 6.2 Most useful queries to know

```promql
# ─── CPU ────────────────────────────────────────────────────────────────────

# CPU usage % per VM/node
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU usage % per pod (in K8s)
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod, namespace)

# ─── MEMORY ─────────────────────────────────────────────────────────────────

# Memory used % per VM
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Memory used by a specific pod (MB)
container_memory_working_set_bytes{pod="my-pod-name", container!=""} / 1024 / 1024

# ─── HTTP APP METRICS ────────────────────────────────────────────────────────

# Request rate (requests per second)
sum(rate(myapp_http_requests_total[5m])) by (route)

# Error rate (% of requests that are 5xx)
sum(rate(myapp_http_requests_total{status_code=~"5.."}[5m]))
/
sum(rate(myapp_http_requests_total[5m]))
* 100

# P99 request latency (99th percentile - slowest 1% of requests)
histogram_quantile(0.99, sum(rate(myapp_http_request_duration_seconds_bucket[5m])) by (le))

# ─── KUBERNETES ─────────────────────────────────────────────────────────────

# Count of running pods per namespace
sum(kube_pod_status_phase{phase="Running"}) by (namespace)

# Pods in CrashLoopBackOff
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1

# Pod restart count in last hour
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

### 6.3 Understanding rate() vs increase()

```promql
# rate() → "how many per second on average?"
rate(myapp_http_requests_total[5m])
# Returns: 2.5 (meaning 2.5 requests per second on average over last 5 minutes)

# increase() → "how many total in this time window?"
increase(myapp_http_requests_total[5m])
# Returns: 750 (meaning 750 requests happened in the last 5 minutes)

# When to use each:
# rate()     → for graphs showing throughput/speed (req/s, errors/s)
# increase() → for counts in a time window (how many restarts in last hour?)
```

---

## 7. 10 Scenarios: Kubernetes Failures & Successes

> For each scenario: trigger it, observe in Prometheus, then see the alert fire.

### Setup: Generate load for realistic metrics

```bash
# Deploy a load generator pod to continuously call our app
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: demo
spec:
  containers:
    - name: load
      image: busybox
      command: ["/bin/sh"]
      args:
        - -c
        - |
          while true; do
            wget -q -O- http://prometheus-demo-app.demo.svc.cluster.local/
            wget -q -O- http://prometheus-demo-app.demo.svc.cluster.local/error 2>/dev/null || true
            sleep 0.5
          done
  restartPolicy: Always
EOF
```

---

### K8s Scenario 1: ✅ SUCCESS — Application Starts and Metrics Are Collected

**Goal:** Verify that your app is being scraped and metrics appear in Prometheus.

**Steps:**
```bash
# 1. Deploy the app
kubectl apply -f k8s/deployment.yaml

# 2. Wait for pods to be ready
kubectl rollout status deployment/prometheus-demo-app -n demo

# 3. Check Prometheus target is UP
# Open: http://localhost:9090/targets
# Look for: job="prometheus-demo-app" → state: UP
```

**PromQL to verify success:**
```promql
# Should return 1 (meaning the target is UP)
up{job="prometheus-demo-app"}

# Should show request counts increasing
rate(myapp_http_requests_total[1m])

# Should show the pods running
kube_pod_status_phase{namespace="demo", phase="Running"}
```

**What you see in Prometheus:** Green `UP` on the Targets page. Metrics flowing in the Graph tab.

---

### K8s Scenario 2: ❌ FAILURE — Pod CrashLoopBackOff

**Goal:** Detect a crashing pod using Prometheus.

**Trigger the failure:**
```bash
# Deploy a broken app (image that doesn't exist = ImagePullBackOff leading to crash)
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-app
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: broken-app
  template:
    metadata:
      labels:
        app: broken-app
    spec:
      containers:
        - name: app
          image: nginx:latest
          command: ["/bin/sh", "-c", "exit 1"]   # Immediately exits with error
          resources:
            limits:
              memory: 64Mi
EOF
```

**Observe in Prometheus:**
```promql
# Watch restart count climb
kube_pod_container_status_restarts_total{namespace="demo"}

# See CrashLoopBackOff reason
kube_pod_container_status_waiting_reason{namespace="demo", reason="CrashLoopBackOff"}

# Alert rule: fires when this == 1 for 2 minutes
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
```

**What you see:** Restart counter climbing. After 2 minutes, the alert fires.

**Clean up:**
```bash
kubectl delete deployment broken-app -n demo
```

---

### K8s Scenario 3: ❌ FAILURE — High Error Rate

**Goal:** Detect when your app starts returning too many 5xx errors.

**Trigger the failure:**
```bash
# Generate traffic to the /error endpoint only
kubectl run error-load --image=busybox --restart=Never -n demo -- \
  sh -c "while true; do wget -q -O- http://prometheus-demo-app.demo.svc.cluster.local/error 2>/dev/null; done"
```

**Observe in Prometheus:**
```promql
# Error rate as a percentage
sum(rate(myapp_http_requests_total{status_code=~"5.."}[2m]))
/
sum(rate(myapp_http_requests_total[2m]))
* 100

# Count of 5xx errors per second
sum(rate(myapp_http_requests_total{status_code=~"5.."}[1m]))
```

**You should see:** Error rate climbing to ~70% (because our /error route returns 500 70% of the time).

**Alert rule for this:**
```yaml
alert: HighErrorRate
expr: |
  sum(rate(myapp_http_requests_total{status_code=~"5.."}[5m]))
  /
  sum(rate(myapp_http_requests_total[5m]))
  * 100 > 10
for: 2m
annotations:
  summary: "Error rate is {{ $value | printf \"%.1f\" }}%"
```

**Clean up:**
```bash
kubectl delete pod error-load -n demo
```

---

### K8s Scenario 4: ❌ FAILURE — Pod Out of Memory (OOMKilled)

**Goal:** Detect pods being killed due to memory limits.

**Trigger the failure:**
```bash
# Deploy a memory-hungry app (will exceed 64Mi limit and be OOMKilled)
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
  namespace: demo
spec:
  containers:
    - name: memory-hog
      image: progrium/stress
      args: ["--vm", "1", "--vm-bytes", "200M", "--timeout", "60s"]
      resources:
        limits:
          memory: 64Mi     # Only 64MB allowed, app needs 200MB = OOMKilled!
EOF
```

**Observe in Prometheus:**
```promql
# See the pod being OOMKilled (container_oom_events counter)
kube_pod_container_status_last_terminated_reason{reason="OOMKilled", namespace="demo"}

# Watch memory rising then dropping suddenly (the drop is the OOM kill)
container_memory_working_set_bytes{namespace="demo", pod=~"memory-hog.*"}

# Check pod restart count
kube_pod_container_status_restarts_total{namespace="demo", pod=~"memory-hog.*"}
```

**What you see:** Memory climbs, then drops to zero (pod killed), then restart count goes up.

**Alert rule:**
```yaml
alert: PodOOMKilled
expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
for: 0m
annotations:
  summary: "Pod {{ $labels.pod }} was OOMKilled"
```

**Clean up:**
```bash
kubectl delete pod memory-hog -n demo
```

---

### K8s Scenario 5: ❌ FAILURE — High Latency (Slow Response)

**Goal:** Detect when your app becomes slow.

**Trigger the failure:**
```bash
# Generate traffic specifically to the /slow endpoint
kubectl run slow-load --image=busybox --restart=Never -n demo -- \
  sh -c "while true; do wget -q -O- http://prometheus-demo-app.demo.svc.cluster.local/slow 2>/dev/null; sleep 0.1; done"
```

**Observe in Prometheus:**
```promql
# P99 latency — 99th percentile of request duration
histogram_quantile(
  0.99,
  sum(rate(myapp_http_request_duration_seconds_bucket[5m])) by (le)
)

# P50 latency (median)
histogram_quantile(
  0.50,
  sum(rate(myapp_http_request_duration_seconds_bucket[5m])) by (le)
)

# Average latency
rate(myapp_http_request_duration_seconds_sum[5m])
/
rate(myapp_http_request_duration_seconds_count[5m])
```

**You should see:** P99 latency jumping to 2-3 seconds.

**Alert rule:**
```yaml
alert: HighLatencyP99
expr: |
  histogram_quantile(0.99,
    sum(rate(myapp_http_request_duration_seconds_bucket[5m])) by (le)
  ) > 1
for: 5m
annotations:
  summary: "P99 latency is {{ $value | printf \"%.2f\" }}s (threshold: 1s)"
```

**Clean up:**
```bash
kubectl delete pod slow-load -n demo
```

---

### K8s Scenario 6: ❌ FAILURE — Deployment Rollout Failure

**Goal:** Detect when a new deployment version fails to roll out.

**Trigger the failure:**
```bash
# Update deployment with a bad image that doesn't exist
kubectl set image deployment/prometheus-demo-app \
  app=yourregistry.azurecr.io/nonexistent-image:v99 -n demo
```

**Observe in Prometheus:**
```promql
# Unavailable replicas (should be 0 during healthy rollout)
kube_deployment_status_replicas_unavailable{namespace="demo", deployment="prometheus-demo-app"}

# Ready vs desired replicas
kube_deployment_status_replicas_ready{namespace="demo"}
kube_deployment_spec_replicas{namespace="demo"}

# Pods in ImagePullBackOff
kube_pod_container_status_waiting_reason{reason="ImagePullBackOff", namespace="demo"} == 1
```

**Alert rule:**
```yaml
alert: DeploymentRolloutFailed
expr: |
  kube_deployment_status_replicas_unavailable{namespace="demo"} > 0
for: 5m
annotations:
  summary: "Deployment {{ $labels.deployment }} has {{ $value }} unavailable replicas"
```

**Rollback:**
```bash
kubectl rollout undo deployment/prometheus-demo-app -n demo
kubectl rollout status deployment/prometheus-demo-app -n demo
```

---

### K8s Scenario 7: ❌ FAILURE — CPU Throttling

**Goal:** Detect when a pod's CPU is being throttled (hitting its CPU limit).

**Trigger the failure:**
```bash
# Generate high CPU load in our app pod
APP_POD=$(kubectl get pod -n demo -l app=prometheus-demo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n demo $APP_POD -- sh -c "while true; do :; done" &
```

**Observe in Prometheus:**
```promql
# CPU throttled time ratio (% of time CPU was throttled)
rate(container_cpu_throttled_seconds_total{namespace="demo"}[5m])
/
rate(container_cpu_usage_seconds_total{namespace="demo"}[5m])
* 100

# CPU usage vs limit
sum(rate(container_cpu_usage_seconds_total{namespace="demo",container!=""}[5m])) by (pod)
/
sum(kube_pod_container_resource_limits{namespace="demo",resource="cpu"}) by (pod)
* 100
```

**Alert rule:**
```yaml
alert: CPUThrottling
expr: |
  rate(container_cpu_throttled_seconds_total{namespace="demo"}[5m])
  /
  rate(container_cpu_usage_seconds_total{namespace="demo"}[5m])
  * 100 > 50
for: 5m
annotations:
  summary: "Pod {{ $labels.pod }} CPU is {{ $value | printf \"%.0f\" }}% throttled"
```

---

### K8s Scenario 8: ✅ SUCCESS — Horizontal Pod Autoscaling (HPA) Works

**Goal:** Watch Prometheus metrics as HPA scales your app up under load.

**Setup HPA:**
```bash
# Enable metrics-server (needed for HPA) - usually pre-installed on AKS
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA for our app
kubectl autoscale deployment prometheus-demo-app \
  --namespace demo \
  --cpu-percent=50 \
  --min=2 \
  --max=8
```

**Trigger scale-up:**
```bash
# Generate high load
for i in {1..10}; do
  kubectl run load-$i --image=busybox --restart=Never -n demo -- \
    sh -c "while true; do wget -q -O- http://prometheus-demo-app.demo.svc.cluster.local/ > /dev/null; done" &
done
```

**Observe in Prometheus:**
```promql
# Watch replica count increase
kube_deployment_status_replicas_ready{namespace="demo", deployment="prometheus-demo-app"}

# Watch CPU usage per pod drop as more pods join
sum(rate(container_cpu_usage_seconds_total{namespace="demo",container!=""}[1m])) by (pod)

# Total request rate spreading across pods
sum(rate(myapp_http_requests_total[1m])) by (pod)
```

**What you see:** Replica count climbing from 2 → 4 → 8. CPU per pod dropping as load distributes.

**Clean up:**
```bash
for i in {1..10}; do kubectl delete pod load-$i -n demo 2>/dev/null; done
kubectl delete hpa prometheus-demo-app -n demo
```

---

### K8s Scenario 9: ❌ FAILURE — Node Not Ready

**Goal:** Detect a Kubernetes node going offline.

> **Note:** On AKS, you cannot easily kill a node. You can simulate this by cordoning a node.

```bash
# Get a node name
NODE=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}')

# Cordon the node (simulate it being unavailable)
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
```

**Observe in Prometheus:**
```promql
# Node readiness (1 = ready, 0 = not ready)
kube_node_status_condition{condition="Ready", status="true"}

# Pods pending because no node is available
kube_pod_status_phase{phase="Pending"}

# Node info
kube_node_info
```

**Alert rule:**
```yaml
alert: NodeNotReady
expr: kube_node_status_condition{condition="Ready",status="true"} == 0
for: 2m
annotations:
  summary: "Kubernetes node {{ $labels.node }} is not ready"
```

**Restore:**
```bash
kubectl uncordon $NODE
```

---

### K8s Scenario 10: ✅ SUCCESS — Canary Deployment Monitoring

**Goal:** Deploy a new version of the app as a canary (10% traffic) and monitor error rate vs the stable version.

```bash
# Deploy canary version (same app, different label)
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-demo-app-canary
  namespace: demo
spec:
  replicas: 1     # 1 canary vs 2 stable = ~33% traffic to canary
  selector:
    matchLabels:
      app: prometheus-demo-app
      version: canary
  template:
    metadata:
      labels:
        app: prometheus-demo-app
        version: canary
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: app
          image: yourregistry.azurecr.io/prometheus-demo-app:v1.0
          env:
            - name: VERSION
              value: "canary"
          resources:
            limits:
              memory: 128Mi
              cpu: 200m
EOF
```

**Observe in Prometheus:**
```promql
# Compare error rates between stable and canary
sum(rate(myapp_http_requests_total{status_code=~"5.."}[5m])) by (pod)
/
sum(rate(myapp_http_requests_total[5m])) by (pod)
* 100

# Compare latency between versions
histogram_quantile(0.99,
  sum(rate(myapp_http_request_duration_seconds_bucket[5m])) by (le, pod)
)
```

**If canary has higher error rate → roll it back:**
```bash
kubectl delete deployment prometheus-demo-app-canary -n demo
```

---

## 8. 10 Scenarios: Azure VM Failures & Successes

---

### VM Scenario 1: ✅ SUCCESS — All Targets UP and Metrics Flowing

**Verify your setup is working:**
```bash
# Check all Prometheus targets are UP
curl -s http://localhost:9090/api/v1/targets | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(f\"{t['labels']['job']:30s} {t['health']:6s} {t['lastScrape'][:19]}\")
"
```

**PromQL to confirm:**
```promql
# Should return 1 for all targets
up

# Should return values for all VMs
node_memory_MemAvailable_bytes

# App metrics flowing
myapp_http_requests_total
```

**Generate test traffic:**
```bash
for i in {1..20}; do
  curl -s http://$APP_IP:8080/ > /dev/null
  curl -s http://$APP_IP:8080/slow > /dev/null &
  curl -s http://$APP_IP:8080/error > /dev/null
done
```

---

### VM Scenario 2: ❌ FAILURE — CPU Spike (Runaway Process)

**Trigger:**
```bash
ssh azureuser@$APP_IP
sudo apt-get install -y stress-ng
stress-ng --cpu 2 --timeout 120s &
exit
```

**Observe in Prometheus:**
```promql
# CPU usage % (watch it spike)
100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)

# CPU by mode (see 'user' mode spike — that's the stress process)
avg by(instance, mode)(rate(node_cpu_seconds_total[1m])) * 100

# Number of running processes
node_procs_running
```

**Alert fires when CPU > 85% for 5 minutes.**

**Investigate:**
```bash
ssh azureuser@$APP_IP
top -bn1 | head -20    # See which process is using CPU
ps aux --sort=-%cpu | head -10
# Kill the stress process
pkill stress-ng
exit
```

---

### VM Scenario 3: ❌ FAILURE — Memory Leak Simulation

**Trigger:**
```bash
ssh azureuser@$APP_IP
# Allocate memory gradually (simulates a memory leak)
stress-ng --vm 1 --vm-bytes 600M --vm-keep --timeout 90s &
exit
```

**Observe in Prometheus:**
```promql
# Available memory dropping over time
node_memory_MemAvailable_bytes{job="app-vm-01"} / 1024 / 1024

# Memory used %
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Swap usage (bad sign — system is swapping to disk)
node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes * 100
```

**What you see in Grafana:** The "Available Memory" line drops steadily like a waterfall — classic memory leak pattern.

**Predict when OOM will happen:**
```promql
# Predict available memory in 1 hour based on current trend
predict_linear(node_memory_MemAvailable_bytes{job="app-vm-01"}[30m], 3600)
# If this returns a negative number → OOM within 1 hour!
```

**Alert:**
```yaml
alert: MemoryWillRunOut
expr: predict_linear(node_memory_MemAvailable_bytes[1h], 4*3600) < 0
for: 10m
annotations:
  summary: "{{ $labels.instance }} will run out of memory in 4 hours"
```

---

### VM Scenario 4: ❌ FAILURE — Disk Filling Up

**Trigger:**
```bash
ssh azureuser@$APP_IP
# Fill 3GB of disk space
fallocate -l 3G /tmp/disk-fill-test.dat
exit
```

**Observe in Prometheus:**
```promql
# Disk used % per mountpoint
(1 - (
  node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint="/"}
  /
  node_filesystem_size_bytes{fstype!="tmpfs",mountpoint="/"}
)) * 100

# Free disk space in GB
node_filesystem_avail_bytes{mountpoint="/"} / 1024 / 1024 / 1024

# Predict when disk will be full
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600) / 1024 / 1024 / 1024
```

**Clean up:**
```bash
ssh azureuser@$APP_IP
rm /tmp/disk-fill-test.dat
exit
```

---

### VM Scenario 5: ❌ FAILURE — App Service Goes Down

**Trigger:**
```bash
ssh azureuser@$APP_IP
sudo systemctl stop prometheus-demo-app
exit
```

**What happens in Prometheus:**
- The scrape target `prometheus-demo-app` changes from UP to DOWN
- The `up` metric for that job drops to 0

**Observe:**
```promql
# Target is down (returns 0)
up{job="prometheus-demo-app"}

# When did it go down?
changes(up{job="prometheus-demo-app"}[30m])
```

**In the Prometheus UI:** Go to **Status > Targets** — you'll see the target in RED with the last error message.

**Alert:**
```yaml
alert: AppDown
expr: up{job="prometheus-demo-app"} == 0
for: 1m
annotations:
  summary: "Application {{ $labels.job }} on {{ $labels.instance }} is DOWN"
```

**Restore:**
```bash
ssh azureuser@$APP_IP
sudo systemctl start prometheus-demo-app
exit
```

---

### VM Scenario 6: ❌ FAILURE — High Disk I/O

**Trigger:**
```bash
ssh azureuser@$APP_IP
stress-ng --io 4 --hdd 2 --timeout 60s &
exit
```

**Observe in Prometheus:**
```promql
# Disk read throughput (MB/s)
rate(node_disk_read_bytes_total{job="app-vm-01"}[1m]) / 1024 / 1024

# Disk write throughput (MB/s)
rate(node_disk_written_bytes_total{job="app-vm-01"}[1m]) / 1024 / 1024

# Disk I/O utilization % (how busy is the disk?)
rate(node_disk_io_time_seconds_total{job="app-vm-01"}[1m]) * 100

# I/O wait — CPU sitting idle waiting for disk (bad sign)
avg(rate(node_cpu_seconds_total{mode="iowait",job="app-vm-01"}[1m])) * 100
```

**Alert:**
```yaml
alert: HighDiskIO
expr: rate(node_disk_io_time_seconds_total[5m]) * 100 > 80
for: 5m
annotations:
  summary: "Disk on {{ $labels.instance }} is {{ $value | printf \"%.0f\" }}% busy"
```

---

### VM Scenario 7: ❌ FAILURE — Network Congestion

**Trigger:**
```bash
ssh azureuser@$APP_IP
# Download large files to simulate outbound bandwidth saturation
wget -O /dev/null http://speedtest.tele2.net/10MB.zip &
wget -O /dev/null http://speedtest.tele2.net/10MB.zip &
wget -O /dev/null http://speedtest.tele2.net/10MB.zip &
exit
```

**Observe in Prometheus:**
```promql
# Receive bandwidth (MB/s)
rate(node_network_receive_bytes_total{device!="lo",job="app-vm-01"}[1m]) / 1024 / 1024

# Transmit bandwidth (MB/s)
rate(node_network_transmit_bytes_total{device!="lo",job="app-vm-01"}[1m]) / 1024 / 1024

# Network errors
rate(node_network_receive_errs_total{job="app-vm-01"}[5m])
+ rate(node_network_transmit_errs_total{job="app-vm-01"}[5m])

# Dropped packets
rate(node_network_receive_drop_total{job="app-vm-01"}[5m])
```

---

### VM Scenario 8: ❌ FAILURE — High Application Error Rate

**Trigger:**
```bash
# Generate lots of traffic specifically to the /error endpoint
for i in {1..200}; do curl -s http://$APP_IP:8080/error > /dev/null; done &
```

**Observe in Prometheus:**
```promql
# Error rate %
sum(rate(myapp_http_requests_total{status_code=~"5.."}[2m]))
/
sum(rate(myapp_http_requests_total[2m]))
* 100

# Errors per second
sum(rate(myapp_http_requests_total{status_code=~"5.."}[1m]))

# Successful requests per second
sum(rate(myapp_http_requests_total{status_code="200"}[1m]))

# Requests by status code breakdown
sum(rate(myapp_http_requests_total[2m])) by (status_code)
```

**Create a dashboard panel in Grafana:**
- Panel type: Time series
- Query: `sum(rate(myapp_http_requests_total[2m])) by (status_code)`
- Color override: `5.*` → Red, `2.*` → Green, `3.*` → Blue

---

### VM Scenario 9: ❌ FAILURE — High System Load

**Trigger:**
```bash
ssh azureuser@$APP_IP
# Start 4x more workers than CPUs (simulates extreme overload)
stress-ng --cpu 8 --timeout 90s &
exit
```

**Observe in Prometheus:**
```promql
# 1-minute load average
node_load1{job="app-vm-01"}

# Load relative to CPU count (> 1 = overloaded)
node_load5{job="app-vm-01"}
/
count without(cpu,mode)(node_cpu_seconds_total{mode="idle",job="app-vm-01"})

# Number of runnable processes
node_procs_running{job="app-vm-01"}

# Number of blocked processes (waiting for I/O)
node_procs_blocked{job="app-vm-01"}
```

**Reading load average:**
- `1.0` on a 2-CPU VM = 50% load (fine)
- `2.0` on a 2-CPU VM = 100% capacity
- `4.0` on a 2-CPU VM = 200% (processes queuing — bad)

**Alert:**
```yaml
alert: SystemOverloaded
expr: |
  node_load5
  / count without(cpu,mode)(node_cpu_seconds_total{mode="idle"})
  > 2
for: 10m
annotations:
  summary: "{{ $labels.instance }} is overloaded: load {{ $value | printf \"%.2f\" }}x CPU count"
```

---

### VM Scenario 10: ✅ SUCCESS — Prometheus Scrape Config Hot-Reload

**Goal:** Add a new VM to monitoring without restarting Prometheus.

**Add a new VM target:**
```bash
ssh azureuser@$MONITORING_IP

# Edit prometheus.yml to add a new target
sudo tee -a /etc/prometheus/prometheus.yml << 'EOF'

  - job_name: 'new-vm-added-live'
    static_configs:
      - targets: ['NEW_VM_PRIVATE_IP:9100']    # Replace with actual IP
        labels:
          vm_name: 'new-vm'
EOF

# Reload Prometheus config WITHOUT restarting (zero downtime!)
curl -X POST http://localhost:9090/-/reload

echo "Config reloaded!"

exit
```

**Verify in Prometheus:**
```promql
# New target should appear as UP within 15 seconds
up{job="new-vm-added-live"}
```

**Go to Prometheus UI → Status → Targets** — you'll see the new VM immediately without any Prometheus restart.

---

## 9. Common Beginner Mistakes & Fixes

### Mistake 1: Using a counter directly in a graph (shows weird jumps)

```promql
# ❌ WRONG: This shows the raw counter value (always increasing, resets on restart)
myapp_http_requests_total

# ✅ CORRECT: Use rate() to see requests per second
rate(myapp_http_requests_total[5m])
```

### Mistake 2: Prometheus shows "No data" for my app metrics

```bash
# Step 1: Check if the /metrics endpoint works
curl http://<APP_IP>:<APP_PORT>/metrics | head -20

# Step 2: Check Prometheus targets page
# http://localhost:9090/targets — is your app listed? What state?

# Step 3: If state is DOWN, check error message on targets page
# Common errors:
# - "connection refused" → app is not running or wrong port
# - "context deadline exceeded" → firewall blocking port 9100/8080
# - "no such host" → wrong hostname in prometheus.yml

# Step 4: Validate prometheus.yml
promtool check config /etc/prometheus/prometheus.yml
```

### Mistake 3: Alertmanager not sending notifications

```bash
# Check Alertmanager is running
systemctl status alertmanager

# Check Alertmanager config
curl http://localhost:9093/api/v2/status

# Check if alerts are firing (should appear here if conditions are met)
curl http://localhost:9093/api/v2/alerts

# Check Prometheus → Alertmanager connection
# Prometheus UI → Status → Runtime & Build Information → Alertmanager endpoints
curl http://localhost:9090/api/v1/alertmanagers
```

### Mistake 4: Alert rule never fires even though condition is met

```bash
# Check alert state in Prometheus UI → Alerting tab
# States:
# Inactive → condition not met
# Pending  → condition met, waiting for the "for" duration
# Firing   → alert is active

# Common issue: the "for" duration is too long
# If you set "for: 5m" but the condition only lasts 4 minutes → alert never fires

# Validate alert rules
promtool check rules /etc/prometheus/rules/alerts.yml
```

### Mistake 5: ServiceMonitor not working in K8s

```bash
# Check if Prometheus is finding your ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check if the release label matches
kubectl get servicemonitor prometheus-demo-app -n monitoring -o yaml | grep -A5 labels

# The ServiceMonitor MUST have label: release: kube-prometheus-stack
# (match whatever your Helm release name is)

# Check Prometheus targets (should show your app)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets
```

---

## 10. Quick Reference Cheat Sheet

### Essential PromQL Patterns

```promql
# ─── RATE & INCREASE ────────────────────────────────────────────────────────
rate(counter_metric[5m])          # Per-second rate averaged over 5m
irate(counter_metric[5m])         # Instantaneous rate (more reactive)
increase(counter_metric[1h])      # Total increase over 1 hour

# ─── AGGREGATIONS ────────────────────────────────────────────────────────────
sum(metric)                        # Sum all series
avg(metric)                        # Average of all series
max(metric)                        # Maximum value
min(metric)                        # Minimum value
count(metric)                      # Count of series
sum(metric) by (label)             # Sum, grouped by label
sum(metric) without (label)        # Sum, dropping a label

# ─── FILTERING ───────────────────────────────────────────────────────────────
metric{label="value"}              # Exact match
metric{label!="value"}             # Not equal
metric{label=~"pattern.*"}         # Regex match
metric{label!~"pattern.*"}         # Regex not match

# ─── FUNCTIONS ───────────────────────────────────────────────────────────────
histogram_quantile(0.99, rate(hist_bucket[5m]))  # P99 latency
predict_linear(metric[1h], 3600)                 # Predict value in 1 hour
changes(metric[1h])                              # How many times value changed
absent(metric)                                   # Returns 1 if metric has no data (good for "is it missing?" alerts)
```

### Prometheus API Quick Commands

```bash
# Health check
curl http://localhost:9090/-/ready

# Reload config (no restart needed)
curl -X POST http://localhost:9090/-/reload

# Query a metric
curl "http://localhost:9090/api/v1/query?query=up"

# Query over a time range
curl "http://localhost:9090/api/v1/query_range?query=up&start=2024-01-01T00:00:00Z&end=2024-01-01T01:00:00Z&step=60"

# List all targets
curl http://localhost:9090/api/v1/targets

# List all alert rules
curl http://localhost:9090/api/v1/rules

# List firing alerts
curl http://localhost:9090/api/v1/alerts

# List all metric names
curl http://localhost:9090/api/v1/label/__name__/values
```

### Key Metric Names Reference

| Metric | Type | What it measures |
|---|---|---|
| `up` | Gauge | Is the scrape target reachable? (1=yes, 0=no) |
| `node_cpu_seconds_total` | Counter | CPU time by mode (idle, user, system) |
| `node_memory_MemAvailable_bytes` | Gauge | Available memory in bytes |
| `node_filesystem_avail_bytes` | Gauge | Available disk space in bytes |
| `node_disk_io_time_seconds_total` | Counter | Disk busy time |
| `node_network_receive_bytes_total` | Counter | Bytes received on network |
| `node_load1` | Gauge | 1-minute load average |
| `kube_pod_status_phase` | Gauge | Pod phase (Running=1, Failed=1, etc.) |
| `kube_pod_container_status_restarts_total` | Counter | Container restart count |
| `container_cpu_usage_seconds_total` | Counter | Container CPU time |
| `container_memory_working_set_bytes` | Gauge | Container memory usage |
| `myapp_http_requests_total` | Counter | Our app: total requests |
| `myapp_http_request_duration_seconds` | Histogram | Our app: request latency |

### Alertmanager Useful Commands

```bash
# Check Alertmanager status
curl http://localhost:9093/api/v2/status

# List active alerts
curl http://localhost:9093/api/v2/alerts

# Silence an alert (maintenance window)
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "HighCPU", "isRegex": false}],
    "startsAt": "2024-01-15T02:00:00Z",
    "endsAt": "2024-01-15T04:00:00Z",
    "createdBy": "admin",
    "comment": "Maintenance window"
  }'
```

### Learning Path: What to Do Next

```
✅ Step 1: Install kube-prometheus-stack on AKS
✅ Step 2: Deploy sample Node.js app with /metrics endpoint
✅ Step 3: Verify Prometheus is scraping your app (Status > Targets)
✅ Step 4: Run the 10 K8s and 10 VM scenarios
Next:
→ Step 5: Connect Grafana to Prometheus and build dashboards
         Read: grafana-beginner-to-practitioner.md
→ Step 6: Add log monitoring (read elk-stack-guide.md)
→ Step 7: Add distributed tracing (read jaeger-tracing-guide.md)
→ Step 8: Learn advanced PromQL (prometheus-complete-guide.md)
→ Step 9: Long-term storage with Thanos (for production retention)
→ Step 10: Automate alert rules in Git (GitOps approach)
```

**Related guides in this project:**
- [grafana-beginner-to-practitioner.md](grafana-beginner-to-practitioner.md) — Visualize these metrics in Grafana dashboards
- [prometheus-complete-guide.md](prometheus-complete-guide.md) — Advanced Prometheus reference
- [monitoring-integration.md](monitoring-integration.md) — Connect Prometheus with ELK, Jaeger, and ArgoCD

---

*Guide written for DevOps engineers who know Helm and AKS but are new to Prometheus. Covers K8s and Azure VM monitoring with 20 real failure/success scenarios.*
