# Cross-Namespace Networking in Kubernetes
## How Prometheus (monitoring) Scrapes Apps in `dev` / `test` Namespaces

---

## Table of Contents

1. [Core Concept — Namespaces Are Logical, Not Network Boundaries](#1-core-concept)
2. [How the Network Flow Works (Step-by-Step)](#2-network-flow)
3. [Two Discovery Methods Used in This Project](#3-discovery-methods)
4. [What Happens When Network IS Blocked (NetworkPolicy)](#4-network-blocked)
5. [How to Fix Cross-Namespace Communication When Blocked](#5-fix-blocked-network)
6. [Real Scenarios from This Project](#6-real-scenarios)
7. [Cheat Sheet — Quick Reference](#7-cheat-sheet)

---

## 1. Core Concept

```
┌─────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                     │
│                                                         │
│  ┌──────────────┐   ┌──────────┐   ┌──────────────┐   │
│  │  monitoring  │   │   dev    │   │    test      │   │
│  │  namespace   │   │namespace │   │  namespace   │   │
│  │              │   │          │   │              │   │
│  │  Prometheus  │──►│api-gateway│  │api-gateway   │   │
│  │              │   │user-svc  │  │user-svc      │   │
│  │              │──►│product-  │  │product-svc   │   │
│  │              │   │  svc     │   │              │   │
│  └──────────────┘   └──────────┘   └──────────────┘   │
│                                                         │
│  ← Namespaces = logical grouping, NOT firewall walls →  │
└─────────────────────────────────────────────────────────┘
```

**By default, all pods in all namespaces can talk to each other.**
Namespaces provide isolation of resources (names, RBAC, quotas) — but NOT network isolation.
Network isolation only happens when you explicitly apply a `NetworkPolicy`.

---

## 2. Network Flow — Step by Step

### Without Any NetworkPolicy (Default State — This Project)

```
Step 1: Prometheus Operator reads ServiceMonitor CRD
        (ServiceMonitor lives in: monitoring namespace)
        
Step 2: ServiceMonitor says "watch namespaces: dev, test"
        Prometheus Operator queries kube-apiserver for
        Services with label monitor="true" in dev and test
        
Step 3: kube-apiserver returns Service IPs + port info
        e.g. api-gateway.dev.svc.cluster.local → ClusterIP: 10.96.45.12
        
Step 4: Prometheus directly HTTP-GETs the metrics endpoint
        GET http://10.96.45.12:8080/actuator/prometheus
        
Step 5: Metrics are stored in Prometheus TSDB (Time Series DB)
        
Step 6: Grafana queries Prometheus via PromQL
        GET http://prometheus-operated.monitoring.svc.cluster.local:9090/api/v1/query
```

### DNS Resolution — Full Format

Every Kubernetes Service gets a DNS name:

```
<service-name>.<namespace>.svc.cluster.local:<port>
```

| Service | Namespace | Full DNS Name |
|---------|-----------|---------------|
| api-gateway | dev | `api-gateway.dev.svc.cluster.local:8080` |
| user-service | dev | `user-service.dev.svc.cluster.local:8080` |
| product-service | test | `product-service.test.svc.cluster.local:8080` |
| prometheus | monitoring | `prometheus-operated.monitoring.svc.cluster.local:9090` |
| grafana | monitoring | `kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80` |

**Shorthand within same namespace:** `prometheus-operated:9090`  
**Cross-namespace (required):** `prometheus-operated.monitoring.svc.cluster.local:9090`

---

## 3. Two Discovery Methods Used in This Project

This project uses **both** methods simultaneously.

### Method 1 — ServiceMonitor CRD (Preferred / Declarative)

Defined in: `k8s/servicemonitor-all.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ecommerce-all-services
  namespace: monitoring          # ← lives in monitoring namespace
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - dev                      # ← tells Prometheus: go look in these namespaces
      - test
  selector:
    matchLabels:
      monitor: "true"            # ← only pick Services with this label
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
```

**Flow:**
```
ServiceMonitor (monitoring ns)
    │
    │  "watch dev and test namespaces"
    ▼
kube-apiserver
    │
    │  returns: Services with label monitor="true" in dev/test
    ▼
Prometheus scrape loop
    │
    │  HTTP GET /actuator/prometheus every 15s
    ▼
app pods in dev/test namespaces
```

**Why it works cross-namespace:**  
The Prometheus Operator is granted RBAC (`ClusterRole`) to read Services/Endpoints/Pods in ALL namespaces. Then Prometheus itself makes direct HTTP calls to pod IPs — which works by default because no NetworkPolicy blocks it.

### Method 2 — Pod Annotations (Auto-Discovery)

Defined in each service manifest, e.g. `k8s/api-gateway.yaml`:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"     # ← opt-in this pod for scraping
    prometheus.io/port: "8080"       # ← which port
    prometheus.io/path: "/actuator/prometheus"  # ← which path
```

Enabled in `prometheus-stack-values.yaml`:

```yaml
additionalScrapeConfigs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod                    # ← Prometheus scans ALL pods in ALL namespaces
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true                  # ← only keep pods with scrape=true annotation
```

**Flow:**
```
Prometheus kubernetes_sd (service discovery)
    │
    │  scans ALL pod annotations across ALL namespaces
    ▼
finds pods with prometheus.io/scrape="true"
    │
    │  builds target list dynamically
    ▼
scrapes each pod's metrics endpoint directly
```

---

## 4. What Happens When Network IS Blocked (NetworkPolicy)

A `NetworkPolicy` acts like a firewall rule for pods. When applied, it **denies all traffic by default** and only allows what you explicitly permit.

### Example — Deny All Ingress to `dev` Namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: dev                    # ← applies to dev namespace
spec:
  podSelector: {}                   # ← applies to ALL pods in dev
  policyTypes:
    - Ingress                       # ← blocks all incoming traffic
```

**What breaks:**
```
Prometheus (monitoring ns) ──X──► api-gateway (dev ns)   ← BLOCKED
Grafana (monitoring ns)    ──X──► any app in dev          ← BLOCKED
Other services in dev      ──OK──► each other             ← still works (same ns)
```

**What you see in Prometheus:**
```
Target: api-gateway.dev.svc.cluster.local:8080
Status: DOWN
Error: context deadline exceeded (scrape timed out)
```

### Example — Deny All Traffic Between Namespaces

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-namespace
  namespace: dev
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}            # ← only allow pods IN SAME namespace
  egress:
    - to:
        - podSelector: {}            # ← only allow pods IN SAME namespace
    - ports:                         # ← always allow DNS (critical!)
        - port: 53
          protocol: UDP
```

---

## 5. How to Fix Cross-Namespace Communication When Blocked

### Fix 1 — Allow Prometheus to Scrape Across Namespace

Add this NetworkPolicy to `dev` (and `test`) namespace:

```yaml
# k8s/netpol-allow-prometheus-scrape.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: dev                    # apply same to test namespace too
spec:
  podSelector:
    matchLabels:
      monitor: "true"               # only applies to your app pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring   # only from monitoring ns
      ports:
        - port: 8080
          protocol: TCP
```

Apply it:
```bash
kubectl apply -f k8s/netpol-allow-prometheus-scrape.yaml -n dev
kubectl apply -f k8s/netpol-allow-prometheus-scrape.yaml -n test
```

### Fix 2 — Allow Grafana to Query Prometheus

If Grafana is blocked from reaching Prometheus:

```yaml
# k8s/netpol-allow-grafana-query.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-to-prometheus
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana     # only from grafana pod
      ports:
        - port: 9090
          protocol: TCP
```

### Fix 3 — Allow DNS Resolution (Always Required)

DNS runs in `kube-system` namespace on port 53. Without this, even pod-to-pod communication within a namespace breaks.

```yaml
# k8s/netpol-allow-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: dev
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### Fix 4 — Namespace Label Must Match

NetworkPolicy uses **namespace labels** to identify namespaces. Verify labels exist:

```bash
# Check existing labels
kubectl get namespace monitoring --show-labels
kubectl get namespace dev --show-labels

# Add label if missing
kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring
kubectl label namespace dev kubernetes.io/metadata.name=dev
kubectl label namespace test kubernetes.io/metadata.name=test
```

### Fix 5 — RBAC for Prometheus Operator (Cross-Namespace ServiceMonitor)

Prometheus Operator needs `ClusterRole` to read resources in other namespaces:

```yaml
# k8s/rbac-prometheus-cross-namespace.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-cross-namespace-reader
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-cross-namespace-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-cross-namespace-reader
subjects:
  - kind: ServiceAccount
    name: kube-prometheus-stack-prometheus
    namespace: monitoring
```

---

## 6. Real Scenarios from This Project

### Scenario A — Current Setup (No NetworkPolicy, Works Fine)

```
Cluster State: No NetworkPolicy applied anywhere

monitoring/prometheus ──────────────────────────────────►  dev/api-gateway:8080
                       HTTP GET /actuator/prometheus         dev/user-service:8080
                       (direct ClusterIP, no firewall)      dev/product-service:8080
                                                            test/api-gateway:8080
                                                            test/user-service:8080
                                                            test/product-service:8080

Discovery: ServiceMonitor (monitoring ns) watches dev + test
           Pod annotations prometheus.io/scrape="true" also picked up

Result: All 6 app services scraped every 15 seconds ✓
```

How to verify:
```bash
# Port-forward Prometheus UI
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring

# Open browser → http://localhost:9090/targets
# You should see all dev and test services as UP
```

---

### Scenario B — NetworkPolicy Added to `dev` (Breaks Scraping)

```
Situation: Team adds "deny-all-ingress" NetworkPolicy to dev namespace
           for security hardening

monitoring/prometheus ──X──► dev/api-gateway:8080  ← BLOCKED
                              (connection timeout)

Prometheus target status: DOWN
Grafana panels: "No data" for dev namespace metrics
Alertmanager: fires "PrometheusTargetDown" alert
```

Fix:
```bash
# Apply the allow-prometheus-scrape NetworkPolicy to dev namespace
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: dev
spec:
  podSelector:
    matchLabels:
      monitor: "true"
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - port: 8080
          protocol: TCP
EOF

# Verify targets recover in Prometheus UI within ~30 seconds
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring
```

---

### Scenario C — New `staging` Namespace, Prometheus Not Scraping It

```
Situation: New namespace "staging" added, apps deployed,
           but metrics not appearing in Grafana

Root Cause: ServiceMonitor only watches "dev" and "test"
            ServiceMonitor does NOT include "staging"
```

Fix — Update ServiceMonitor:
```bash
kubectl edit servicemonitor ecommerce-all-services -n monitoring
```

Change:
```yaml
  namespaceSelector:
    matchNames:
      - dev
      - test
      - staging      # ← add this line
```

Or update `servicemonitor-all.yaml` and re-apply:
```bash
kubectl apply -f k8s/servicemonitor-all.yaml
```

Also label the new namespace:
```bash
kubectl label namespace staging monitored-by=prometheus environment=staging
```

---

### Scenario D — Service in `dev` Has Wrong Label, Not Scraped

```
Situation: New service deployed in dev namespace
           but NOT appearing in Prometheus targets

Root Cause: Service is missing label monitor="true"
            ServiceMonitor selector requires this label
```

Check:
```bash
kubectl get svc -n dev --show-labels
# Look for monitor="true" in LABELS column
```

Fix — Add missing label to the Service:
```bash
kubectl label svc <your-service-name> monitor="true" -n dev
```

Or add to the manifest:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-new-service
  namespace: dev
  labels:
    monitor: "true"     # ← this line is required
    app: my-new-service
```

---

### Scenario E — Prometheus in `monitoring` Cannot Reach kube-apiserver (RBAC)

```
Situation: ServiceMonitor deployed but Prometheus shows error:
           "unable to list services in namespace dev: forbidden"

Root Cause: Prometheus ServiceAccount lacks permission to
            read resources in dev/test namespaces
```

Fix:
```bash
# Check current ClusterRoleBindings for prometheus
kubectl get clusterrolebindings | grep prometheus

# Verify the prometheus service account
kubectl get serviceaccount -n monitoring | grep prometheus

# Apply ClusterRole + ClusterRoleBinding from Fix 5 above
kubectl apply -f k8s/rbac-prometheus-cross-namespace.yaml
```

---

## 7. Cheat Sheet — Quick Reference

### Verify Cross-Namespace Connectivity

```bash
# Test DNS resolution from Prometheus pod to app in dev
kubectl exec -n monitoring deployment/kube-prometheus-stack-operator -- \
  nslookup api-gateway.dev.svc.cluster.local

# Test HTTP reachability from monitoring to dev
kubectl run test-pod --image=curlimages/curl -n monitoring --rm -it -- \
  curl http://api-gateway.dev.svc.cluster.local:8080/actuator/prometheus

# Check Prometheus targets
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring
# → http://localhost:9090/targets

# Check if NetworkPolicy exists in a namespace
kubectl get networkpolicy -n dev
kubectl get networkpolicy -n monitoring

# Describe a NetworkPolicy to see rules
kubectl describe networkpolicy <name> -n dev

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor ecommerce-all-services -n monitoring
```

### Decision Tree — Prometheus Not Scraping My App

```
Prometheus target shows DOWN?
    │
    ├─► Check NetworkPolicy in app's namespace
    │       kubectl get netpol -n dev
    │       → No netpol? Go to next check
    │       → NetPol exists? Apply allow-prometheus-scrape fix (Scenario B)
    │
    ├─► Check ServiceMonitor namespaceSelector includes app's namespace
    │       kubectl describe servicemonitor ecommerce-all-services -n monitoring
    │       → Namespace missing? Add it (Scenario C)
    │
    ├─► Check Service has label monitor="true"
    │       kubectl get svc -n dev --show-labels
    │       → Label missing? Add it (Scenario D)
    │
    ├─► Check RBAC permissions
    │       kubectl auth can-i list services -n dev \
    │         --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus
    │       → "no"? Apply ClusterRole fix (Scenario E / Fix 5)
    │
    └─► Check pod annotation (for annotation-based discovery)
            kubectl describe pod <pod-name> -n dev | grep prometheus
            → Missing annotations? Add them to pod spec
```

### Summary Table

| Situation | Default Behavior | With NetworkPolicy |
|-----------|-----------------|-------------------|
| Pod → Pod (same ns) | ✓ Allowed | Blocked unless explicitly allowed |
| Pod → Pod (diff ns) | ✓ Allowed | Blocked unless explicitly allowed |
| Prometheus → App metrics | ✓ Works | Need `allow-prometheus-scrape` NetworkPolicy |
| Grafana → Prometheus | ✓ Works | Need ingress rule on port 9090 |
| DNS resolution | ✓ Works | Need egress rule to kube-system port 53 |
| ServiceMonitor cross-ns | ✓ Works | Need RBAC ClusterRole for Prometheus SA |
