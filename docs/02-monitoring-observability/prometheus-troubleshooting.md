# Prometheus Troubleshooting Guide

All issues here are real problems encountered and validated in this project (Prometheus via `kube-prometheus-stack` on Minikube, scraping apps in `dev` and `test` namespaces).

---

## Table of Contents

1. [Issue 1 — Target Shows DOWN After Pod Scaled to Zero](#issue-1--target-shows-down-after-pod-scaled-to-zero)
2. [Issue 2 — CrashLooping Pod Shows up=0 in Prometheus](#issue-2--crashlooping-pod-shows-up0-in-prometheus)
3. [Issue 3 — New Namespace Not Being Scraped](#issue-3--new-namespace-not-being-scraped)
4. [Issue 4 — Service Missing from Targets (Wrong Label)](#issue-4--service-missing-from-targets-wrong-label)
5. [Issue 5 — RBAC Forbidden Error on ServiceMonitor](#issue-5--rbac-forbidden-error-on-servicemonitor)
6. [Issue 6 — Prometheus Not Starting / OOMKilled](#issue-6--prometheus-not-starting--oomkilled)
7. [How to Simulate and Validate Pod Failures](#how-to-simulate-and-validate-pod-failures)
8. [Quick Reference — Useful Commands](#quick-reference)
9. [Best Practices — Prevent These Issues from Happening Again](#best-practices--prevent-these-issues-from-happening-again)

---

## Issue 1 — Target Shows DOWN After Pod Scaled to Zero

### Symptom
- `kubectl scale deployment product-service -n dev --replicas=0`
- Prometheus **completely removes** the target — it does not show as `up=0`, it disappears entirely
- Grafana shows **"No data"** for that service
- PromQL query `up{job="product-service"}` returns **no results**

### Why This Happens
Prometheus discovers targets via **Kubernetes Service endpoints**. When replicas = 0:
```
Replicas = 0
  → No pods running
  → Service has no Endpoints
  → Prometheus service discovery finds no targets
  → Target is removed from scrape list
  → up metric disappears completely (not 0, but absent)
```

### What IS Still Visible
`kube-state-metrics` still tracks the **deployment** even with 0 pods:
```promql
kube_deployment_status_replicas_available{namespace="dev", deployment="product-service"}
# Returns: 0  ← tells you it exists but has no running replicas
```

### Correct PromQL to Detect Scale-to-Zero
```promql
# Detect the service is completely absent
absent(up{namespace="dev", job="product-service"})
# Returns: 1 when product-service has no running pods

# Desired vs available replicas mismatch
kube_deployment_spec_replicas{namespace="dev"} 
  - kube_deployment_status_replicas_available{namespace="dev"}
# Returns: non-zero for product-service when scaled down
```

### Lesson Learned
> Scaling to 0 is **not** the right way to test Prometheus monitoring.
> Use **liveness probe failure** instead — pods stay visible to Prometheus while crashing (see [Issue 2](#issue-2--crashlooping-pod-shows-up0-in-prometheus)).

---

## Issue 2 — CrashLooping Pod Shows up=0 in Prometheus

### How We Reproduced It
Injected a bad liveness probe path into `product-service`:

```bash
# Save current deployment, change liveness probe path to a non-existent endpoint
$dep = kubectl get deployment product-service -n dev -o json | ConvertFrom-Json
$dep.spec.template.spec.containers[0].livenessProbe.httpGet.path = "/bad-path-does-not-exist"
$dep.spec.template.spec.containers[0].livenessProbe.failureThreshold = 2
$dep.spec.template.spec.containers[0].livenessProbe.periodSeconds = 5
$dep | ConvertTo-Json -Depth 20 | Out-File "$env:TEMP\product-patched.json"
kubectl apply -f "$env:TEMP\product-patched.json"
```

**What happened:**
- Kubelet starts pod → app starts on port 8080 → app is running
- Kubelet checks liveness: `GET /bad-path-does-not-exist` → HTTP 404 → **fails**
- After 2 failures → kubelet kills and restarts the pod
- Pod keeps restarting → `CrashLoopBackOff`
- **Prometheus scrapes during the brief "running" window** and sees the pod is not serving metrics → `up=0`

### What Prometheus Shows
```promql
up{namespace="dev", job="product-service"}
# Result: mixed 0 and 1 depending on whether pod is in crash window

# Restart counter climbing
kube_pod_container_status_restarts_total{namespace="dev", pod=~"product-service.*"}
# Returns: increasing counter every ~5 seconds

# Restarts in last 5 minutes
increase(kube_pod_container_status_restarts_total{namespace="dev", pod=~"product-service.*"}[5m])
```

### Alert Rule for CrashLoopBackOff
```yaml
alert: KubePodCrashLooping
expr: |
  increase(kube_pod_container_status_restarts_total[15m]) > 3
for: 5m
labels:
  severity: critical
annotations:
  summary: "Pod {{ $labels.pod }} is crash-looping"
  description: "Pod {{ $labels.pod }} in {{ $labels.namespace }} restarted {{ $value }} times in 15m"
```

### Rollback After Testing
```bash
kubectl rollout undo deployment/product-service -n dev
kubectl rollout status deployment/product-service -n dev
```

---

## Issue 3 — New Namespace Not Being Scraped

### Symptom
New namespace `staging` created, apps deployed with `monitor: "true"` label, but no metrics appear in Prometheus for those apps.

### Root Cause
The `ServiceMonitor` in the `monitoring` namespace only watches specific namespaces listed in `namespaceSelector.matchNames`. New namespaces are not added automatically.

```yaml
# servicemonitor-all.yaml — BEFORE (missing staging)
spec:
  namespaceSelector:
    matchNames:
      - dev
      - test
      # staging is missing → Prometheus ignores it
```

### Fix
Update `servicemonitor-all.yaml`:
```yaml
spec:
  namespaceSelector:
    matchNames:
      - dev
      - test
      - staging    # ← add new namespace here
```

Apply:
```bash
kubectl apply -f k8s/servicemonitor-all.yaml
```

Also label the new namespace so NetworkPolicy selectors work:
```bash
kubectl label namespace staging kubernetes.io/metadata.name=staging
kubectl label namespace staging monitored-by=prometheus environment=staging
```

### Verify
```bash
# Check ServiceMonitor is watching the new namespace
kubectl describe servicemonitor ecommerce-all-services -n monitoring | findstr -i namespace

# Check targets appear in Prometheus (within 30s)
# Open http://localhost:9090/targets → look for staging namespace
```

---

## Issue 4 — Service Missing from Targets (Wrong Label)

### Symptom
New service deployed in `dev` namespace but not appearing in Prometheus targets at all.

### Root Cause
The `ServiceMonitor` selector requires `monitor: "true"` label on the Kubernetes **Service** object. If the label is missing, Prometheus service discovery ignores it.

```yaml
# servicemonitor-all.yaml selector
spec:
  selector:
    matchLabels:
      monitor: "true"   # ← Service MUST have this label
```

### Diagnosis
```bash
# Check if the service has the required label
kubectl get svc -n dev --show-labels
# Look for monitor=true in the LABELS column

# If missing, you will NOT see it in:
kubectl get endpoints -n dev
```

### Fix
```bash
# Add label to existing service
kubectl label svc <service-name> monitor="true" -n dev

# Or add to the Service manifest permanently
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: dev
  labels:
    monitor: "true"     # ← Required for ServiceMonitor discovery
    app: my-service
```

### Verify
```bash
# After adding label, Prometheus will discover it within one scrape interval (15s)
Invoke-RestMethod "http://localhost:9090/api/v1/query?query=up%7Bnamespace%3D%22dev%22%7D"
# Should now include the new service
```

---

## Issue 5 — RBAC Forbidden Error on ServiceMonitor

### Symptom
Prometheus Operator logs show:
```
unable to list services in namespace dev: forbidden
unable to watch endpoints in namespace test: forbidden
```
ServiceMonitor exists but no targets are discovered.

### Root Cause
The Prometheus **ServiceAccount** lacks `ClusterRole` permission to read `Services`, `Endpoints`, and `Pods` in other namespaces.

### Diagnosis
```bash
# Test RBAC permissions for Prometheus service account
kubectl auth can-i list services -n dev \
  --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus
# Should return "yes" — if "no" → RBAC is the problem
```

### Fix
Apply a `ClusterRole` and `ClusterRoleBinding`:

```yaml
# k8s/rbac-prometheus-cross-namespace.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-cross-namespace-reader
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods", "namespaces"]
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

```bash
kubectl apply -f k8s/rbac-prometheus-cross-namespace.yaml
```

### Verify
```bash
kubectl auth can-i list services -n dev \
  --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus
# Returns: yes ✅
```

---

## Issue 6 — Prometheus Not Starting / OOMKilled

### Symptom
```
kubectl get pods -n monitoring
prometheus-kube-prometheus-stack-prometheus-0   0/2   OOMKilled   3
```

### Root Cause
Memory `limits` in Helm values too low for the amount of metrics data being collected.

### Fix
Increase memory in `prometheus-stack-values.yaml`:
```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi    # ← increase from 512Mi to 2Gi
```

Then upgrade:
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/prometheus-stack-values.yaml
```

---

## How to Simulate and Validate Pod Failures

### Method 1 — Bad Liveness Probe (Recommended)
This keeps the pod visible to Prometheus with `up=0` while crash-looping.

```bash
# Step 1: Save current deployment
kubectl get deployment <name> -n dev -o json | Out-File "$env:TEMP\dep.json"

# Step 2: Modify liveness probe path
$dep = Get-Content "$env:TEMP\dep.json" | ConvertFrom-Json
$dep.spec.template.spec.containers[0].livenessProbe.httpGet.path = "/bad-path"
$dep.spec.template.spec.containers[0].livenessProbe.failureThreshold = 2
$dep.spec.template.spec.containers[0].livenessProbe.periodSeconds = 5
$dep | ConvertTo-Json -Depth 20 | Out-File "$env:TEMP\dep-patched.json"

# Step 3: Apply
kubectl apply -f "$env:TEMP\dep-patched.json"

# Step 4: Watch pods enter crash loop
kubectl get pods -n dev -l app=<name> -w

# Step 5: Validate in Prometheus
# up{namespace="dev"} → shows 0 for the crashing pods
# increase(kube_pod_container_status_restarts_total[5m]) → shows restart count

# Step 6: Rollback
kubectl rollout undo deployment/<name> -n dev
```

### Method 2 — Scale to Zero (Shows Absence)
```bash
kubectl scale deployment <name> -n dev --replicas=0
# Prometheus removes target entirely
# Use absent(up{job="<name>"}) to detect
# Restore:
kubectl scale deployment <name> -n dev --replicas=2
```

### Comparison Table

| Method | Prometheus shows | Best for testing |
|--------|-----------------|-----------------|
| Scale to 0 | Target disappears (absent) | Deployment gone / team deleted namespace |
| Bad liveness probe | `up=0`, restart counter rises | App crash / OOMKill / bad config |
| Kill pod directly | Brief flap, new pod starts | Pod eviction scenario |
| Resource exhaustion | `up=1` but app metrics degrade | Performance / memory leak |

---

## Quick Reference

```bash
# Check all Prometheus targets
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring
# Open http://localhost:9090/targets

# Query Prometheus from CLI
Invoke-RestMethod "http://localhost:9090/api/v1/query?query=up"

# Check which services are UP in dev namespace
Invoke-RestMethod "http://localhost:9090/api/v1/query?query=up%7Bnamespace%3D%22dev%22%7D"

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor ecommerce-all-services -n monitoring

# Check Prometheus Operator logs
kubectl logs deployment/kube-prometheus-stack-operator -n monitoring --tail=50

# Check Prometheus pod logs
kubectl logs prometheus-kube-prometheus-stack-prometheus-0 -n monitoring -c prometheus --tail=50

# Check replica counts for all deployments in dev
kubectl get deployments -n dev

# Restart count for all pods in dev
kubectl get pods -n dev --sort-by='.status.containerStatuses[0].restartCount'

# Describe pod to see liveness probe events
kubectl describe pod <pod-name> -n dev | findstr -A 5 "Liveness\|Unhealthy\|Restarting"

# Rollback a deployment to previous version
kubectl rollout undo deployment/<name> -n dev

# Check rollout history
kubectl rollout history deployment/<name> -n dev
```

---

## Best Practices — Prevent These Issues from Happening Again

These rules come directly from problems we hit in this project. Follow them to avoid the most common Prometheus failures.

---

### 1. Never Use Scale-to-Zero to Test Monitoring

**Rule:** Do NOT scale deployments to 0 replicas to simulate a failure for Prometheus testing. The target disappears entirely — Prometheus cannot track what it cannot find.

| What you want to test | Correct method |
|----------------------|----------------|
| App is crashing / restarting | Bad liveness probe path |
| App is slow | Add `sleep()` to an endpoint |
| App is completely gone | Scale to 0 (but use `absent()` in PromQL) |
| App is out of memory | `stress-ng` inside the container |
| App is not scraped | Remove `monitor: "true"` label from Service |

```bash
# ✅ Right way to simulate a crash — pod stays visible, up=0 fires
kubectl set env deployment/<name> -n dev LIVENESS_PATH=/bad-path-does-not-exist

# ✅ After testing — always rollback immediately
kubectl rollout undo deployment/<name> -n dev
kubectl rollout status deployment/<name> -n dev
```

---

### 2. Always Label Services with monitor=true

**Rule:** Any service that must be scraped by Prometheus MUST have `monitor: "true"` label on the **Service** object (not just the Pod or Deployment).

```yaml
# ✅ Every service manifest must include this label
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: dev
  labels:
    app: my-service
    monitor: "true"    # ← Required for ServiceMonitor discovery
spec:
  ports:
    - name: http       # ← Port name must match ServiceMonitor endpoint port name
      port: 8080
```

Quick audit command:
```bash
# Find any service in dev/test that is MISSING the label
kubectl get svc -n dev -l '!monitor'
kubectl get svc -n test -l '!monitor'
# If these return results → those services are invisible to Prometheus
```

---

### 3. Update namespaceSelector When Adding New Namespaces

**Rule:** Every time a new namespace is added to the cluster for application workloads, update the `ServiceMonitor` to include it. Prometheus does NOT auto-discover new namespaces.

```yaml
# servicemonitor-all.yaml — keep this list up to date
spec:
  namespaceSelector:
    matchNames:
      - dev
      - test
      - staging    # ← add new namespace here immediately when created
```

Also label the new namespace:
```bash
kubectl label namespace <new-namespace> monitored-by=prometheus
```

---

### 4. Set Realistic Resource Limits — Prometheus Needs Memory

**Rule:** Prometheus stores all scraped time-series in memory. Set `memory: limits` to at least **2Gi** for any environment with more than 5 services.

```yaml
# prometheus-stack-values.yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi    # ← minimum for 5+ services with 15s scrape interval
    # Keep only 7 days of data locally — offload to remote storage if needed
    retention: 7d
```

---

### 5. Always Write PromQL Queries With rate() for Counters

**Rule:** Never graph a raw Prometheus counter. Counters only go up (until reset). Always wrap them in `rate()` or `increase()`.

```promql
# ❌ WRONG — shows ever-increasing counter that means nothing on a graph
http_requests_total{namespace="dev"}

# ✅ CORRECT — shows requests per second over the last 5 minutes
rate(http_requests_total{namespace="dev"}[5m])

# ✅ CORRECT — shows total increase over the last 15 minutes
increase(http_requests_total{namespace="dev"}[15m])
```

This also applies to restart counters, error counters, and byte counters.

---

### 6. Verify RBAC Permissions After Cluster Changes

**Rule:** Whenever a new namespace is created or a new ServiceAccount is used, verify Prometheus has permission to list/watch endpoints and services in that namespace.

```bash
# Run this check whenever Prometheus stops discovering a namespace
kubectl auth can-i list services -n <namespace> \
  --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus
# Must return: yes

kubectl auth can-i watch endpoints -n <namespace> \
  --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus
# Must return: yes
```

If either returns `no`, apply the ClusterRole fix from [Issue 5](#issue-5--rbac-forbidden-error-on-servicemonitor).

---

### 7. Write Alert Rules for Every Failure Pattern You Discover

**Rule:** Every time you diagnose a new failure, write an alert rule for it. If you fixed it once manually, automate the detection so it never silently fails again.

Minimum alert rules every project should have:

```yaml
# Add these under prometheus.additionalRulesForClusterRole or PrometheusRule CRD
groups:
  - name: ecommerce.microservices
    rules:

      # Pod is crash-looping
      - alert: PodCrashLooping
        expr: increase(kube_pod_container_status_restarts_total[15m]) > 3
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} is crash-looping"
          description: "{{ $labels.pod }} in {{ $labels.namespace }} restarted {{ $value }} times"

      # Service has no running instances
      - alert: ServiceScaledToZero
        expr: kube_deployment_status_replicas_available == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Deployment {{ $labels.deployment }} has 0 replicas"
          description: "{{ $labels.deployment }} in {{ $labels.namespace }} has no running pods"

      # Prometheus cannot scrape a target
      - alert: PrometheusTargetDown
        expr: up == 0
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "Target {{ $labels.job }} is down"
          description: "Prometheus cannot scrape {{ $labels.instance }} in {{ $labels.namespace }}"

      # Target disappeared completely
      - alert: PrometheusTargetMissing
        expr: absent(up{namespace="dev"})
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "A target in dev namespace has disappeared"
          description: "One or more expected targets in dev namespace are no longer visible to Prometheus"
```

---

### 8. Use a Consistent Port Name Convention

**Rule:** ServiceMonitor endpoints match by **port name**, not port number. Standardize on one port name across all services.

```yaml
# ✅ All services use port name "http" — ServiceMonitor can use one rule for all
apiVersion: v1
kind: Service
spec:
  ports:
    - name: http    # ← must match ServiceMonitor endpoint port name
      port: 8080
```

```yaml
# servicemonitor-all.yaml
endpoints:
  - port: http            # ← matches the name above
    path: /actuator/prometheus
    interval: 15s
```

If port names differ per service, you need a separate ServiceMonitor per service — much harder to maintain.

---

### 9. Tag Every Namespace and Label Every Resource From Day One

**Rule:** Apply labels when you create resources. Retro-labeling in production is risky and easy to miss.

```bash
# When creating a new namespace — do all three at once
kubectl create namespace staging
kubectl label namespace staging \
  kubernetes.io/metadata.name=staging \
  monitored-by=prometheus \
  environment=staging
```

```bash
# When deploying a new service — verify labels before pushing manifest
kubectl get svc -n staging --show-labels
# Check: monitor=true is present before assuming it will be scraped
```

---

### 10. Always Rollback After Testing — Never Leave a Broken State

**Rule:** After any failure simulation, always rollback immediately and verify health before moving on.

```bash
# After ANY test that modifies a deployment
kubectl rollout undo deployment/<name> -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>

# Verify pod is healthy again
kubectl get pods -n <namespace> -l app=<name>
# Should show: READY 2/2, STATUS Running, RESTARTS 0

# Verify Prometheus sees it as UP again
Invoke-RestMethod "http://localhost:9090/api/v1/query?query=up%7Bnamespace%3D%22dev%22%7D"
# Should show value: ["1"] for the restored service
```

---

### Quick Best Practices Checklist

When adding a new service:
- [ ] Service has `monitor: "true"` label
- [ ] Service port is named `http` (matches ServiceMonitor)
- [ ] Service exposes `/actuator/prometheus` (or equivalent metrics path)
- [ ] Namespace is listed in `servicemonitor-all.yaml` `namespaceSelector.matchNames`
- [ ] RBAC check: Prometheus can `list services` in that namespace

When running failure simulations:
- [ ] Used liveness probe failure (not scale-to-zero) to keep target visible
- [ ] Confirmed `up=0` or restart counter in Prometheus
- [ ] Rolled back after testing
- [ ] Confirmed `up=1` after rollback

After any infrastructure change:
- [ ] All pods in `monitoring` and `dev`/`test` are `Running`
- [ ] No unexpected restarts (`kubectl get pods --all-namespaces | grep -v Running`)
- [ ] Prometheus `/targets` shows all expected services as UP
- [ ] At least one Grafana dashboard shows live data

---

## Related Guides
- [grafana-troubleshooting.md](grafana-troubleshooting.md)
- [cross-namespace-networking.md](cross-namespace-networking.md)
- [prometheus-beginner-to-practitioner.md](prometheus-beginner-to-practitioner.md)
- [prometheus-complete-guide.md](prometheus-complete-guide.md)
