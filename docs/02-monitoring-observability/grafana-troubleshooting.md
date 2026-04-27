# Grafana Troubleshooting Guide

All issues here are real problems encountered and fixed in this project (Grafana 12.x on Minikube with `kube-prometheus-stack`).

---

## Table of Contents

1. [Issue 1 — CrashLoopBackOff: Duplicate Default Datasource](#issue-1--crashloopbackoff-duplicate-default-datasource)
2. [Issue 2 — Dashboards Not Showing After Upgrade](#issue-2--dashboards-not-showing-after-upgrade)
3. [Issue 3 — Grafana Not Accessible (LoadBalancer Pending on Minikube)](#issue-3--grafana-not-accessible-loadbalancer-pending-on-minikube)
4. [Issue 4 — "No Data" on Dashboard Panels](#issue-4--no-data-on-dashboard-panels)
5. [Quick Reference — Useful Commands](#quick-reference)
6. [Best Practices — Prevent These Issues from Happening Again](#best-practices--prevent-these-issues-from-happening-again)

---

## Issue 1 — CrashLoopBackOff: Duplicate Default Datasource

### Symptom
```
kubectl get pods -n monitoring
NAME                                         READY   STATUS             RESTARTS
kube-prometheus-stack-grafana-698bd6fc6c-...  0/3    Error              7
```

Events on the pod:
```
Warning  Unhealthy   kubelet  Readiness probe failed: Get "http://10.244.0.71:3000/api/health": connection refused
Warning  BackOff     kubelet  Back-off restarting failed container grafana
```

### Root Cause
Grafana 12.x **crashes on startup** if more than one datasource in the provisioning config is marked `isDefault: true`.

In this project, two sources both set `isDefault: true`:
1. The **Helm chart auto-generated** ConfigMap `kube-prometheus-stack-grafana-datasource`
2. A **manual `grafana.datasources` block** inside `prometheus-stack-values.yaml`

```
Grafana startup sequence:
  → reads /etc/grafana/provisioning/datasources/*.yaml
  → finds TWO datasources with isDefault: true
  → throws fatal error
  → container exits
  → kubelet restarts → repeat → CrashLoopBackOff
```

### Diagnosis
```bash
# Check the crash logs from the previous container run
kubectl logs <grafana-pod> -n monitoring --previous | tail -20

# Look for this error line:
# Datasource provisioning error: datasource.yaml config is invalid.
# Only one datasource per organization can be marked as default
```

### Fix
Remove the manual `grafana.datasources` block from your Helm values file — the Helm chart already creates the correct datasource automatically.

**In `prometheus-stack-values.yaml`, delete this block:**
```yaml
# DELETE THIS ENTIRE BLOCK
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://kube-prometheus-stack-prometheus.monitoring...
          isDefault: true   # ← this conflicts with the auto-generated one
          access: proxy
```

Then upgrade:
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/prometheus-stack-values.yaml
```

### Verify Fix
```bash
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring
# → deployment "kube-prometheus-stack-grafana" successfully rolled out

kubectl get pods -n monitoring | Select-String grafana
# → 3/3 Running
```

---

## Issue 2 — Dashboards Not Showing After Upgrade

### Symptom
- Grafana is `3/3 Running`
- Prometheus datasource health check passes
- But **Dashboards menu is empty** — no dashboards visible
- Dashboard JSON files exist in the container at `/var/lib/grafana/dashboards/default/`

### Root Cause
Path mismatch between where the init container **downloads** dashboards and where Grafana's provisioning config **looks** for them.

```
Init container (download-dashboards):
  → downloads k8s-cluster.json, k8s-pods.json, node-exporter-full.json
  → saves to: /var/lib/grafana/dashboards/default/     ← HERE

Grafana provisioning (sc-dashboardproviders.yaml):
  → watches: /tmp/dashboards                           ← DIFFERENT PATH

Result: Grafana never sees the downloaded files → empty dashboards list
```

### Diagnosis
```bash
# Step 1: Confirm dashboard files exist in the pod
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana \
  -c grafana -- ls /var/lib/grafana/dashboards/default/
# Output: k8s-cluster.json  k8s-pods.json  node-exporter-full.json

# Step 2: Check what path Grafana's provisioning config watches
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana \
  -c grafana -- cat /etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml
# Look for: path: /tmp/dashboards  ← mismatch!

# Step 3: Verify via API (Grafana 12 uses new unified storage endpoint)
$headers = @{Authorization="Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:password"))}
Invoke-RestMethod -Uri "http://localhost:3001/api/search?type=dash-db" -Headers $headers
# Returns empty → confirms no dashboards loaded
```

### Fix
Add a `dashboardProviders` entry in `prometheus-stack-values.yaml` that tells Grafana to also read from `/var/lib/grafana/dashboards/default/`:

```yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default   # ← match the actual path
```

Then upgrade:
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/prometheus-stack-values.yaml
```

### Verify Fix
```bash
# Check both provider files now exist in the pod
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana \
  -c grafana -- ls /etc/grafana/provisioning/dashboards/
# Output: dashboardproviders.yaml  sc-dashboardproviders.yaml

# Check Grafana logs show dashboards provisioned
kubectl logs deployment/kube-prometheus-stack-grafana -n monitoring -c grafana \
  | Select-String "finished to provision dashboards"
# Output: msg="finished to provision dashboards"

# Check via new Grafana 12 unified storage API
$headers = @{Authorization="Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:password"))}
Invoke-RestMethod -Uri "http://localhost:3001/apis/dashboard.grafana.app/v1beta1/namespaces/default/dashboards" -Headers $headers
# Returns full dashboard JSON → confirmed loaded
```

---

## Issue 3 — Grafana Not Accessible (LoadBalancer Pending on Minikube)

### Symptom
```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring
NAME                            TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
kube-prometheus-stack-grafana   LoadBalancer   10.104.106.39  <pending>     80:31663/TCP
```
Browser cannot open Grafana — `EXTERNAL-IP` never gets assigned.

### Root Cause
On **Minikube**, `LoadBalancer` type services never get an external IP automatically. Minikube does not have a cloud load balancer provider. The service stays `<pending>` forever.

### Fix — Use port-forward (local dev)
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring
# Then open: http://localhost:3001
```

> Use port 3001 if 3000 is already in use by another process.

### Fix — Use NodePort (persistent access without port-forward)
```bash
kubectl patch svc kube-prometheus-stack-grafana -n monitoring \
  -p '{"spec": {"type": "NodePort"}}'

# Get the assigned NodePort
kubectl get svc kube-prometheus-stack-grafana -n monitoring
# Then get minikube IP
minikube ip
# Open: http://<minikube-ip>:<nodeport>
```

### Fix — minikube tunnel (exposes LoadBalancer)
```bash
# Run in a separate terminal (must stay open)
minikube tunnel

# EXTERNAL-IP will now be assigned (usually 127.0.0.1)
kubectl get svc kube-prometheus-stack-grafana -n monitoring
# Open: http://127.0.0.1:80
```

---

## Issue 4 — "No Data" on Dashboard Panels

### Symptom
Grafana is running, datasource health check passes, but dashboard panels show **"No data"** or **"N/A"**.

### Possible Causes and Fixes

| Cause | How to Check | Fix |
|-------|-------------|-----|
| Wrong time range | Check top-right time picker | Set to "Last 15 minutes" or "Last 1 hour" |
| Datasource URL wrong | Connections → Data sources → Test | Correct URL to `http://kube-prometheus-stack-prometheus.monitoring:9090` |
| Metric does not exist yet | Run query in Explore | Wait for first scrape interval (15–30s) |
| Dashboard variable not set | Check dropdown filters at top of dashboard | Select correct namespace / pod / instance |
| Prometheus not scraping target | Check Prometheus Targets page | See [prometheus-troubleshooting.md](prometheus-troubleshooting.md) |

### Validate Datasource via UI

1. **☰** → **Connections** → **Data sources**
2. Click **Prometheus**
3. Scroll to bottom → **Save & test**
4. Expected result:
```
✅ Successfully queried the Prometheus API.
```

### Validate Live Data via Explore

1. **☰** → **Explore**
2. Select datasource: **Prometheus**
3. Run:
```promql
up{namespace="dev"}
```
If this returns data → Prometheus is working. If panels still show No data → the specific metric in the dashboard panel does not exist yet.

---

## Quick Reference

```bash
# Get Grafana admin password
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring

# Check Grafana pod logs
kubectl logs deployment/kube-prometheus-stack-grafana -n monitoring -c grafana --tail=50

# Check previous container crash logs
kubectl logs deployment/kube-prometheus-stack-grafana -n monitoring -c grafana --previous --tail=30

# Check datasource ConfigMaps
kubectl get configmap -n monitoring | findstr grafana
kubectl describe configmap kube-prometheus-stack-grafana-datasource -n monitoring

# Restart Grafana pod (force redeploy)
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring

# Test datasource health via API
$h = @{Authorization="Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:YourGrafanaPassword123!"))}
Invoke-RestMethod -Uri "http://localhost:3001/api/datasources/uid/prometheus/health" -Headers $h

# List all dashboards via API (Grafana 12)
Invoke-RestMethod -Uri "http://localhost:3001/apis/dashboard.grafana.app/v1beta1/namespaces/default/dashboards" -Headers $h

# Helm upgrade after config change
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/prometheus-stack-values.yaml
```

---

## Best Practices — Prevent These Issues from Happening Again

These are rules learned from real failures in this project. Follow them and you will avoid most Grafana problems.

---

### 1. Never Manually Define the Prometheus Datasource When Using kube-prometheus-stack

**Rule:** Do NOT add a `grafana.datasources` block in `prometheus-stack-values.yaml`.

The Helm chart creates the Prometheus datasource automatically via the `kube-prometheus-stack-grafana-datasource` ConfigMap. Adding it again causes the duplicate-default crash.

```yaml
# ❌ WRONG — causes CrashLoopBackOff in Grafana 12.x
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          isDefault: true
          ...

# ✅ CORRECT — let the Helm chart create the datasource automatically
grafana:
  adminUser: admin
  adminPassword: "YourPassword"
  # No datasources block here
```

---

### 2. Always Declare dashboardProviders Together with dashboards

**Rule:** If you define `grafana.dashboards` (to auto-import community dashboards), you must also define `grafana.dashboardProviders` with the **exact same path** that the sidecar places files.

The default sidecar path is `/tmp/dashboards`. If you override it in `dashboardProviders`, the sidecar must also know.

```yaml
# ✅ Correct pattern — paths must match
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          type: file
          options:
            path: /var/lib/grafana/dashboards/default   # ← your custom path
  dashboards:
    default:
      node-exporter-full:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
```

---

### 3. Always Verify After Every helm upgrade

**Rule:** After every `helm upgrade`, run these three checks before declaring success.

```bash
# Check 1 — All pods running
kubectl get pods -n monitoring

# Check 2 — Grafana has no restarts
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check 3 — Grafana logs are clean
kubectl logs deployment/kube-prometheus-stack-grafana -n monitoring -c grafana --tail=20
# Should NOT contain: "config is invalid", "fatal", "error starting"
```

---

### 4. Use Port-Forward for Minikube — Never Rely on LoadBalancer

**Rule:** On Minikube, `LoadBalancer` services will always stay in `<pending>` state. Use `kubectl port-forward` for local access.

```bash
# ✅ Always use port-forward on Minikube
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# ❌ LoadBalancer EXTERNAL-IP stays <pending> forever on Minikube
kubectl get svc -n monitoring
# kube-prometheus-stack-grafana  LoadBalancer  10.96.x.x  <pending>  80:30xxx/TCP
```

In production (AKS, EKS, GKE), LoadBalancer works correctly. On Minikube, always use port-forward or `minikube service <name> -n <namespace>`.

---

### 5. Store Grafana Values in Version Control — Never Change via UI Only

**Rule:** Every Grafana configuration change (datasources, dashboards, alert contacts) must be reflected in `prometheus-stack-values.yaml` in git. UI-only changes are lost on the next `helm upgrade`.

| Configuration Type | Where to Define It |
|--------------------|-------------------|
| Datasources | Auto-created by Helm chart (do not touch) |
| Community dashboards | `grafana.dashboards` in values file |
| Custom dashboards | ConfigMaps with `grafana_dashboard: "1"` label |
| Alert contact points | `grafana.alerting` in values file |
| Admin password | `grafana.adminPassword` in values file |

---

### 6. Test Grafana Datasource Health After Every Upgrade

**Rule:** After every `helm upgrade`, validate the Prometheus datasource is connected and returning data.

```bash
# Forward Grafana port
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# Test datasource via API (replace UID if different)
Invoke-RestMethod -Uri "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" `
  -Headers @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:YourGrafanaPassword123!"))}
# Expected: {"status":"success", ...}
```

---

### 7. Grafana 12+ — Use the Unified Storage API for Dashboard Queries

**Rule:** The legacy `/api/search` endpoint returns empty results in Grafana 12+. Use the unified storage API instead.

```bash
# ❌ Old way — returns empty in Grafana 12
Invoke-RestMethod "http://localhost:3000/api/search" -Headers $headers

# ✅ New way — Grafana 12+ unified storage API
Invoke-RestMethod "http://localhost:3000/apis/dashboard.grafana.app/v1beta1/namespaces/default/dashboards" `
  -Headers $headers
```

---

### 8. Use a Dedicated Helm Values File Per Environment

**Rule:** Keep separate Helm values files for different environments. Never edit the production values file for debugging.

```
k8s/
  prometheus-stack-values.yaml          ← production values (committed)
  prometheus-stack-values-local.yaml    ← local/dev overrides (gitignored)
```

```bash
# Apply local overrides on top of base values
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/prometheus-stack-values.yaml \
  -f k8s/prometheus-stack-values-local.yaml   # ← local overrides last = highest priority
```

---

### Quick Best Practices Checklist

Before every `helm upgrade`:
- [ ] Did I add a `grafana.datasources` block? → **Remove it**
- [ ] Did I add `dashboards` without `dashboardProviders`? → **Add providers too**
- [ ] Do the `dashboardProviders` paths match the sidecar mount paths?
- [ ] Is the admin password committed in plain text to a public repo? → **Use a Secret instead**
- [ ] Did I test the change locally before upgrading production?

After every `helm upgrade`:
- [ ] All pods in `monitoring` are `Running` with `0` restarts
- [ ] Grafana logs show no fatal errors
- [ ] Prometheus datasource health check returns OK
- [ ] At least one dashboard is loading data

---

## Related Guides
- [prometheus-troubleshooting.md](prometheus-troubleshooting.md)
- [cross-namespace-networking.md](cross-namespace-networking.md)
- [prometheus-beginner-to-practitioner.md](prometheus-beginner-to-practitioner.md)
- [grafana-beginner-to-practitioner.md](grafana-beginner-to-practitioner.md)
