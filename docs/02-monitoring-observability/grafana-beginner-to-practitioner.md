# Grafana: Beginner to Practitioner Guide
## From Zero Knowledge → Kubernetes Pods → Azure VMs → 10 Real-World Scenarios

> **Who this guide is for:** You know how to deploy apps on Kubernetes using Helm, but you have never used Grafana before. This guide starts from absolute basics and takes you all the way to production-ready monitoring setups.

---

## Table of Contents

1. [What is Grafana? (Explained Simply)](#1-what-is-grafana-explained-simply)
2. [How Monitoring Works — The Big Picture](#2-how-monitoring-works--the-big-picture)
3. [Install Grafana on Kubernetes Using Helm (Step-by-Step)](#3-install-grafana-on-kubernetes-using-helm-step-by-step)
4. [Your First Login — Grafana UI Walkthrough](#4-your-first-login--grafana-ui-walkthrough)
5. [Monitor Kubernetes Pods with Grafana](#5-monitor-kubernetes-pods-with-grafana)
6. [Setup Grafana on Azure VMs](#6-setup-grafana-on-azure-vms)
7. [10 Real-Time Monitoring Scenarios on Azure VMs](#7-10-real-time-monitoring-scenarios-on-azure-vms)
8. [Common Beginner Mistakes & Fixes](#8-common-beginner-mistakes--fixes)
9. [Quick Reference Cheat Sheet](#9-quick-reference-cheat-sheet)

---

## 1. What is Grafana? (Explained Simply)

### Think of it like this

Imagine your Kubernetes cluster or Azure VM is a factory floor. Machines are running, workers are doing jobs, and things might go wrong.

- **Prometheus** = the factory's sensor network. It collects numbers (metrics) — like "machine #3 is using 80% power" — every few seconds.
- **Grafana** = the control room with big screens. It takes those numbers from Prometheus and draws them as beautiful graphs, charts, and dashboards so you can instantly SEE what is happening.

Grafana does **not collect data itself**. It only **visualizes data** from other sources.

### What can Grafana show you?

| What you want to see | Grafana can show it from |
|---|---|
| CPU / Memory / Disk usage of pods | Prometheus |
| Application logs | Elasticsearch or Loki |
| Request traces (how long each service took) | Jaeger or Tempo |
| Azure VM metrics | Azure Monitor |
| Database query times | Prometheus + exporters |
| Error rates, response times | Your app's metrics |

### Key Terms (Beginner Dictionary)

| Term | What it means in plain English |
|---|---|
| **Data Source** | Where Grafana reads data from (e.g., Prometheus) |
| **Dashboard** | A page with multiple graphs/charts |
| **Panel** | One single graph/chart on a dashboard |
| **Query** | The question you ask the data source (e.g., "give me CPU usage of pod X") |
| **PromQL** | The language used to query Prometheus (you'll learn this gradually) |
| **Alert** | A notification sent to Slack/Email when something goes wrong |
| **Variable** | A dropdown filter on a dashboard (e.g., select which namespace to view) |
| **Datasource UID** | A unique ID that links dashboards to a specific data source |

---

## 2. How Monitoring Works — The Big Picture

```
YOUR KUBERNETES CLUSTER / AZURE VM
│
├── Your App (pod/VM process)
│     └── exposes metrics on /metrics endpoint (if instrumented)
│
├── Node Exporter (runs on every VM/node)
│     └── exposes OS-level metrics: CPU, memory, disk, network
│
├── kube-state-metrics (K8s only)
│     └── exposes K8s object metrics: pod status, deployments, etc.
│
└── Prometheus
      └── scrapes /metrics from all above every 15 seconds
            └── stores them in time-series database
                  │
                  └── Grafana
                        └── queries Prometheus using PromQL
                              └── draws dashboards in your browser
```

### The monitoring stack you will install

```
kube-prometheus-stack (one Helm chart installs everything below)
├── Prometheus          → collects & stores metrics
├── Alertmanager        → sends alerts to Slack/email
├── Grafana             → visualizes metrics
├── Node Exporter       → OS metrics from each node
└── kube-state-metrics  → Kubernetes object metrics
```

---

## 3. Install Grafana on Kubernetes Using Helm (Step-by-Step)

> **Prerequisite:** You have a working Kubernetes cluster (minikube, AKS, EKS, or GKE) and `kubectl` + `helm` installed.

### Step 1: Add the Prometheus community Helm repo

```bash
# Add the repo that contains kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Also add the Grafana repo (for standalone installs later)
helm repo add grafana https://grafana.github.io/helm-charts

# Update repos to get latest chart versions
helm repo update
```

**What just happened?** You told Helm where to download charts from, just like `apt-get update` in Linux.

### Step 2: Create a namespace for monitoring tools

```bash
# Create a dedicated namespace
kubectl create namespace monitoring

# Verify it was created
kubectl get namespace monitoring
```

### Step 3: Create your Helm values file

This file customizes what gets installed. Create a file called `monitoring-values.yaml`:

```yaml
# monitoring-values.yaml
# This installs Prometheus + Grafana + Alertmanager + Node Exporter + kube-state-metrics

prometheus:
  prometheusSpec:
    retention: 15d          # Keep metrics for 15 days
    resources:
      requests:
        memory: 400Mi
        cpu: 100m
      limits:
        memory: 1Gi
        cpu: 500m

grafana:
  # Login credentials
  adminUser: admin
  adminPassword: "YourSecurePassword123!"   # Change this!
  
  # How to access Grafana from your browser
  service:
    type: NodePort          # Use LoadBalancer on cloud clusters (AKS, EKS)
    nodePort: 32000

  # Grafana settings
  grafana.ini:
    server:
      root_url: "http://localhost:3000"
    security:
      allow_embedding: true
    unified_alerting:
      enabled: true

  # Pre-configure Prometheus as data source automatically
  # (you don't need to manually add it in the UI)
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          isDefault: true
          access: proxy
          editable: true

  # Pre-import popular Kubernetes dashboards
  dashboards:
    default:
      # Dashboard ID 1860: Node Exporter Full (OS-level metrics per node)
      node-exporter-full:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      # Dashboard ID 315: Kubernetes Cluster Monitoring
      k8s-cluster:
        gnetId: 315
        revision: 3
        datasource: Prometheus
      # Dashboard ID 13770: Kubernetes Pods monitoring
      k8s-pods:
        gnetId: 13770
        revision: 1
        datasource: Prometheus

  # Dashboard providers configuration
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: "Kubernetes"
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 64Mi
        cpu: 10m
      limits:
        memory: 256Mi

nodeExporter:
  enabled: true   # This installs Node Exporter on every K8s node

kubeStateMetrics:
  enabled: true   # This exposes K8s object state as metrics
```

### Step 4: Install the stack

```bash
# Install everything with one command
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml \
  --wait

# The --wait flag waits until all pods are Running before returning
# This may take 2-3 minutes
```

**Expected output:**
```
NAME: kube-prometheus-stack
LAST DEPLOYED: ...
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
```

### Step 5: Verify everything is running

```bash
# Check all pods in monitoring namespace
kubectl get pods -n monitoring

# You should see pods like:
# kube-prometheus-stack-grafana-xxxx-xxxx          3/3  Running  0  2m
# kube-prometheus-stack-kube-state-metrics-xxxx    1/1  Running  0  2m
# kube-prometheus-stack-operator-xxxx              1/1  Running  0  2m
# kube-prometheus-stack-prometheus-node-exporter   1/1  Running  0  2m  (one per node)
# prometheus-kube-prometheus-stack-prometheus-0    2/2  Running  0  2m
# alertmanager-kube-prometheus-stack-alertmanager  2/2  Running  0  2m

# Check services
kubectl get svc -n monitoring
```

### Step 6: Access Grafana in your browser

```bash
# Option A: Port-forward (works on any cluster, including minikube)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Now open: http://localhost:3000
# Username: admin
# Password: YourSecurePassword123!

# Option B: Minikube NodePort
minikube service kube-prometheus-stack-grafana -n monitoring

# Option C: Get the LoadBalancer IP (for cloud clusters)
kubectl get svc kube-prometheus-stack-grafana -n monitoring
# Look for EXTERNAL-IP column
```

---

## 4. Your First Login — Grafana UI Walkthrough

### Login screen

Navigate to `http://localhost:3000` and log in with `admin` / `YourSecurePassword123!`

### Navigation sidebar (left side)

```
☰ (burger menu)
├── 🏠 Home               → Your home dashboard
├── 🔍 Explore            → Write queries and explore data raw
├── 🔔 Alerting           → Set up and manage alerts
├── ⚙️  Administration     → Users, orgs, plugins, data sources
└── ☁️  Connections        → Add new data sources
```

### Finding the pre-imported dashboards

1. Click the **grid icon** (Dashboards) in the left sidebar
2. Click **Browse**
3. You will see a folder called **"Kubernetes"** (created by our Helm values)
4. Click it and you'll see the three dashboards we imported

### Exploring a dashboard

1. Click **"Node Exporter Full"** dashboard
2. At the top, you'll see:
   - **Time picker** (top right): Change the time range (e.g., Last 1 hour)
   - **Refresh button**: Auto-refresh every 30s
   - **Variables** (dropdowns): Filter by node, job, etc.
3. Scroll down to see panels like:
   - CPU Usage
   - Memory Usage
   - Disk I/O
   - Network Traffic

### Adding Prometheus as a data source (if not auto-configured)

1. Go to **Administration** → **Data sources**
2. Click **Add data source**
3. Choose **Prometheus**
4. Set URL to: `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
5. Click **Save & Test** — you should see "Data source is working"

---

## 5. Monitor Kubernetes Pods with Grafana

This section shows you exactly how to monitor pods — their CPU, memory, restarts, logs, and health.

### 5.1 Understanding what metrics are available for pods

When you installed kube-state-metrics and Node Exporter, Prometheus started collecting these pod metrics automatically:

| Metric Name | What it tells you |
|---|---|
| `kube_pod_status_phase` | Is the pod Running, Pending, Failed, Succeeded? |
| `kube_pod_container_status_restarts_total` | How many times has this container restarted? |
| `kube_pod_container_status_waiting_reason` | Why is this container not running? (CrashLoopBackOff, etc.) |
| `container_cpu_usage_seconds_total` | How much CPU is the container using? |
| `container_memory_working_set_bytes` | How much memory is the container using? |
| `kube_pod_container_resource_limits` | What are the CPU/memory limits set? |
| `kube_pod_container_resource_requests` | What are the CPU/memory requests set? |

### 5.2 Import the best Kubernetes pod dashboards

```bash
# Via Grafana UI: Dashboards > New > Import

# Dashboard ID 13770 — K8s / Compute Resources / Namespace (Pods)
# Shows: CPU usage, memory usage, network per pod in a namespace
# Best for: Seeing all pods in a namespace at once

# Dashboard ID 6781 — Kubernetes Pod Monitoring  
# Shows: Pod restarts, CPU/memory usage, container states
# Best for: Tracking individual pod health

# Dashboard ID 8685 — Kubernetes Deployment Statefulset Daemonset metrics
# Shows: Deployment rollout status, replica counts
# Best for: Watching deployments and rollouts
```

**How to import via UI:**
1. Go to **Dashboards** → **New** → **Import**
2. Enter the dashboard ID (e.g., `13770`)
3. Click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

### 5.3 Explore pod metrics using Grafana Explore

The **Explore** tab lets you write raw PromQL queries to understand your data.

```bash
# Open Grafana Explore: Left sidebar → Explore icon (compass)
# Select "Prometheus" as the data source at the top

# --- BASIC QUERIES TO TRY ---

# 1. See all running pods (count per namespace)
sum(kube_pod_status_phase{phase="Running"}) by (namespace)

# 2. See pods that are NOT running
kube_pod_status_phase{phase!="Running"}

# 3. See CPU usage for all pods (in cores)
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod, namespace)

# 4. See memory usage for a specific pod
container_memory_working_set_bytes{pod="your-pod-name", container!=""}

# 5. See pods with restarts
kube_pod_container_status_restarts_total > 0

# 6. See pods in CrashLoopBackOff
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1

# 7. See CPU usage as a percentage of request
(
  sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod)
  /
  sum(kube_pod_container_resource_requests{resource="cpu"}) by (pod)
) * 100

# 8. See memory usage vs limit
(
  container_memory_working_set_bytes{container!=""}
  /
  kube_pod_container_resource_limits{resource="memory"}
) * 100
```

### 5.4 Create your own pod monitoring dashboard

**Step 1: Create a new dashboard**
1. Dashboards → New → New Dashboard
2. Click **Add visualization**

**Step 2: Add a "Running Pods Count" stat panel**

| Setting | Value |
|---|---|
| Panel type | Stat |
| Query | `sum(kube_pod_status_phase{phase="Running"})` |
| Title | Running Pods |
| Color mode | Background |
| Thresholds | Green always |

**Step 3: Add a "Failed Pods" alert stat panel**

| Setting | Value |
|---|---|
| Panel type | Stat |
| Query | `sum(kube_pod_status_phase{phase="Failed"}) OR vector(0)` |
| Title | Failed Pods |
| Thresholds | Green at 0, Red at 1 |

**Step 4: Add a "Pod CPU Usage" time series panel**

| Setting | Value |
|---|---|
| Panel type | Time series |
| Query | `sum(rate(container_cpu_usage_seconds_total{container!="", namespace=~"$namespace"}[5m])) by (pod)` |
| Title | Pod CPU Usage |
| Unit | Cores |

**Step 5: Add a namespace variable**
1. Click **Dashboard settings** (gear icon, top right)
2. Click **Variables** → **New variable**
3. Settings:
   - Name: `namespace`
   - Type: Query
   - Query: `label_values(kube_pod_info, namespace)`
   - Multi-value: ON
   - Include All: ON
4. Click **Apply**

Now your query `{namespace=~"$namespace"}` will filter by whatever namespace you select.

**Step 6: Save the dashboard**
- Press `Ctrl+S`, give it a name like "My Pod Monitoring Dashboard"

### 5.5 Set up alerts for pod issues

**Alert 1: Pod CrashLoopBackOff**

1. Go to **Alerting** → **Alert rules** → **New alert rule**
2. Configure:

```yaml
# Alert rule settings
Name: Pod CrashLoopBackOff
Folder: Kubernetes Alerts
Group: pod-health

# Query (Section 2 - Define query)
Data source: Prometheus
Expression: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1

# Condition (Section 3)
Evaluate every: 1m
For: 2m
# This means: alert fires only if the condition stays true for 2 minutes
# (avoids false alarms during brief restarts)

# Annotations
Summary: Pod {{ $labels.pod }} is in CrashLoopBackOff
Description: Container {{ $labels.container }} in namespace {{ $labels.namespace }} is crash-looping.
```

**Alert 2: High Memory Usage**

```yaml
Name: Pod High Memory Usage
Expression: (container_memory_working_set_bytes{container!=""} / kube_pod_container_resource_limits{resource="memory"}) * 100 > 90
For: 5m
Summary: Pod {{ $labels.pod }} memory usage is above 90%
```

**Alert 3: Pod Restart Count Spike**

```yaml
Name: Pod Restart Spike
Expression: increase(kube_pod_container_status_restarts_total[1h]) > 5
For: 1m
Summary: Pod {{ $labels.pod }} has restarted {{ $value }} times in the last hour
```

### 5.6 Add notification channel (Slack example)

1. Go to **Alerting** → **Contact points** → **Add contact point**
2. Choose **Slack**
3. Enter your Slack webhook URL
4. Click **Test** to verify it works
5. Click **Save contact point**

**To get a Slack webhook URL:**
1. Go to https://api.slack.com/apps
2. Create app → Incoming Webhooks → Add New Webhook to Workspace
3. Copy the webhook URL

---

## 6. Setup Grafana on Azure VMs

This section covers deploying the full monitoring stack on Azure Virtual Machines (not Kubernetes).

### 6.1 Architecture on Azure VMs

```
Azure VM 1 (Monitoring Server)
├── Grafana        (port 3000)  ← you view dashboards here
├── Prometheus     (port 9090)  ← collects & stores metrics
└── Alertmanager   (port 9093)  ← sends alerts

Azure VM 2, 3, 4... (Application Servers)
└── Node Exporter  (port 9100)  ← exposes VM OS metrics to Prometheus
└── Your App                    ← optionally exposes app metrics
```

### 6.2 Prerequisites

```bash
# On your local machine or Azure Cloud Shell:
# - Azure CLI installed and logged in
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 6.3 Create Azure VMs

> VM creation (resource group, Monitoring VM, App VM, port rules) is identical to the Prometheus VM setup.
> Follow **[prometheus-beginner-to-practitioner.md — Section 5.2](prometheus-beginner-to-practitioner.md)**, using resource group name `grafana-monitoring-rg`, then return here.

### 6.4 Install Node Exporter on Application VM(s)

> Follow **[prometheus-beginner-to-practitioner.md — Section 5.3](prometheus-beginner-to-practitioner.md)** to install Node Exporter on your App VM, then return here.

### 6.5 Install Prometheus on Monitoring VM

> Follow **[prometheus-beginner-to-practitioner.md — Section 5.4](prometheus-beginner-to-practitioner.md)** to install and configure Prometheus on your Monitoring VM, then return here.

### 6.6 Install Grafana on Monitoring VM

> Still on **monitoring-server** VM.

```bash
# Install Grafana via apt (easiest on Ubuntu)
sudo apt-get install -y apt-transport-https software-properties-common wget

# Add Grafana GPG key
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

# Add Grafana repository
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee -a /etc/apt/sources.list.d/grafana.list

# Update and install
sudo apt-get update
sudo apt-get install -y grafana

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
sudo systemctl status grafana-server

# ---- Configure Grafana ----

# Edit Grafana config
sudo tee /etc/grafana/grafana.ini << 'EOF'
[server]
http_port = 3000
root_url = http://0.0.0.0:3000/

[security]
admin_user = admin
admin_password = YourSecurePassword123!    # Change this!
allow_embedding = true

[unified_alerting]
enabled = true

[auth.anonymous]
enabled = false
EOF

# Add Prometheus as a data source via provisioning
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
    uid: prometheus
EOF

sudo chown -R grafana:grafana /etc/grafana/provisioning/
sudo systemctl restart grafana-server

# Access Grafana at http://<MONITORING_IP>:3000
echo "Open Grafana at: http://$MONITORING_IP:3000"
echo "Username: admin"
echo "Password: YourSecurePassword123!"
```

### 6.7 Import Node Exporter Full Dashboard

Once logged into Grafana:
1. Go to **Dashboards** → **New** → **Import**
2. Enter ID: **1860** (Node Exporter Full)
3. Click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

You will immediately see CPU, memory, disk, and network for all your Azure VMs.

---

## 7. 10 Real-Time Monitoring Scenarios on Azure VMs

> These scenarios simulate real production problems. For each scenario, you will:
> 1. **Trigger** the problem on the VM
> 2. **Observe** the spike in Grafana
> 3. **Resolve** the problem
> 4. **Create an alert** so you are notified next time

---

### Scenario 1: CPU Spike — Simulate High CPU Usage

**What you will learn:** How to detect runaway processes consuming CPU.

**Trigger the problem on App VM:**
```bash
ssh azureuser@$APP_IP

# Simulate 100% CPU on 2 cores for 60 seconds
stress-ng --cpu 2 --timeout 60s &
# If stress-ng is not installed: sudo apt-get install -y stress-ng
```

**What to observe in Grafana:**
1. Open **Node Exporter Full** dashboard
2. Select `app-server-01` from the **instance** dropdown
3. Watch **CPU Usage** panel — it should spike to near 100%
4. Check **CPU by Mode** panel — you'll see `user` mode spike

**PromQL query to explore:**
```promql
# CPU usage percentage per instance
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Create the alert:**
```yaml
Alert Name: High CPU Usage
Query: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
For: 5m
Summary: CPU on {{ $labels.instance }} is {{ $value | printf "%.1f" }}%
```

---

### Scenario 2: Memory Exhaustion — Simulate Memory Leak

**What you will learn:** How to catch memory leaks before the VM crashes (OOM).

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Gradually consume memory (allocate 500MB over 30 seconds)
stress-ng --vm 1 --vm-bytes 500M --timeout 30s &
```

**What to observe in Grafana:**
- **Node Exporter Full** → **Memory Used** panel rises sharply
- **Available Memory** drops rapidly
- The Grafana dashboard color changes to yellow/red based on thresholds

**PromQL queries to explore:**
```promql
# Memory used percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Available memory in GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Memory used by page cache (can be reclaimed)
node_memory_Cached_bytes / 1024 / 1024 / 1024
```

**Create the alert:**
```yaml
Alert Name: High Memory Usage
Query: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
For: 5m
Summary: Memory on {{ $labels.instance }} is {{ $value | printf "%.1f" }}% used
```

---

### Scenario 3: Disk Full — Simulate Disk Space Exhaustion

**What you will learn:** Catch disk full situations before services crash (disks filling up crashes databases, log writers, etc.).

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Create a 2GB dummy file to consume disk space
# WARNING: Do this on a test VM only, not production!
fallocate -l 2G /tmp/dummy-large-file.dat
```

**What to observe in Grafana:**
- **Node Exporter Full** → **Disk Space Used** panel shows increase
- **Disk Space % Used** shows the percentage climbing

**PromQL queries to explore:**
```promql
# Disk usage percentage per mount point
(1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100

# How many hours until disk is full (based on current fill rate)
predict_linear(node_filesystem_avail_bytes{fstype!="tmpfs"}[6h], 24*3600) < 0

# Free space in GB
node_filesystem_avail_bytes{fstype!="tmpfs", mountpoint="/"} / 1024 / 1024 / 1024
```

**Cleanup:**
```bash
rm /tmp/dummy-large-file.dat
```

**Create the alert:**
```yaml
Alert Name: Disk Almost Full
Query: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint="/"} / node_filesystem_size_bytes{fstype!="tmpfs",mountpoint="/"})) * 100 > 80
For: 5m
Summary: Disk on {{ $labels.instance }} ({{ $labels.mountpoint }}) is {{ $value | printf "%.1f" }}% full
```

---

### Scenario 4: High Disk I/O — Simulate Disk Saturation

**What you will learn:** Detect when a disk is a bottleneck (heavy read/write operations slow down databases and apps).

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Generate heavy disk I/O for 60 seconds
stress-ng --io 4 --hdd 2 --timeout 60s &
```

**What to observe in Grafana:**
- **Node Exporter Full** → **Disk I/O** panel shows bytes read/written per second
- **Disk Utilization** shows % time disk is busy
- Look for **iowait** in **CPU by Mode** panel — high iowait means CPU is waiting for disk

**PromQL queries to explore:**
```promql
# Disk read rate (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024

# Disk write rate (MB/s)
rate(node_disk_written_bytes_total[5m]) / 1024 / 1024

# Disk utilization (% time busy)
rate(node_disk_io_time_seconds_total[5m]) * 100

# Average I/O wait time (ms) — how long processes wait for disk
rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m]) * 1000
```

**Create the alert:**
```yaml
Alert Name: High Disk I/O
Query: rate(node_disk_io_time_seconds_total[5m]) * 100 > 80
For: 5m
Summary: Disk on {{ $labels.instance }} is {{ $value | printf "%.1f" }}% saturated
```

---

### Scenario 5: Network Traffic Spike — Simulate DDoS or Data Exfiltration

**What you will learn:** Detect abnormal network traffic which could indicate an attack, misconfiguration, or a bug causing excessive API calls.

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Generate outbound network traffic for 30 seconds
# (downloads /dev/null from the internet)
for i in {1..5}; do
  wget -O /dev/null http://speedtest.tele2.net/100MB.zip &
done
wait
```

**What to observe in Grafana:**
- **Node Exporter Full** → **Network Traffic** panel shows outbound traffic spike
- Look for unusual patterns in **receive** vs **transmit** bytes

**PromQL queries to explore:**
```promql
# Network receive rate (MB/s) per interface
rate(node_network_receive_bytes_total{device!="lo"}[5m]) / 1024 / 1024

# Network transmit rate (MB/s) per interface
rate(node_network_transmit_bytes_total{device!="lo"}[5m]) / 1024 / 1024

# Total network errors
rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m])

# Dropped packets
rate(node_network_receive_drop_total[5m]) + rate(node_network_transmit_drop_total[5m])
```

**Create the alert:**
```yaml
Alert Name: Unusual Network Outbound Traffic
Query: rate(node_network_transmit_bytes_total{device!="lo"}[5m]) / 1024 / 1024 > 100
For: 5m
Summary: {{ $labels.instance }} sending {{ $value | printf "%.1f" }} MB/s — possible data exfiltration
```

---

### Scenario 6: Service Down — Simulate Application Crash

**What you will learn:** Instantly detect when a service/process stops running.

**Setup a sample service to monitor:**
```bash
ssh azureuser@$APP_IP

# Install a simple web service for testing
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Install the Prometheus blackbox exporter for HTTP endpoint probing
wget https://github.com/prometheus/blackbox_exporter/releases/download/v0.24.0/blackbox_exporter-0.24.0.linux-amd64.tar.gz
tar xvfz blackbox_exporter-0.24.0.linux-amd64.tar.gz
sudo mv blackbox_exporter-0.24.0.linux-amd64/blackbox_exporter /usr/local/bin/

sudo tee /etc/blackbox_exporter.yml << 'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []  # Defaults to 2xx
      method: GET
EOF

# Start blackbox exporter
sudo tee /etc/systemd/system/blackbox_exporter.service << 'EOF'
[Unit]
Description=Blackbox Exporter
[Service]
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter.yml
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable blackbox_exporter
sudo systemctl start blackbox_exporter
```

**Add blackbox scrape to Prometheus (on Monitoring VM):**
```bash
ssh azureuser@$MONITORING_IP

# Edit prometheus.yml to add blackbox probing
sudo tee -a /etc/prometheus/prometheus.yml << 'EOF'

  # HTTP endpoint probing via Blackbox Exporter
  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - http://<APP_IP>:80     # nginx on App VM
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: <APP_IP>:9115   # Blackbox exporter address
EOF

sudo systemctl restart prometheus
```

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Stop nginx to simulate service crash
sudo systemctl stop nginx
```

**What to observe in Grafana:**
```promql
# Check if HTTP probe succeeds (1 = up, 0 = down)
probe_success{job="blackbox-http"}

# HTTP status code
probe_http_status_code

# HTTP response time
probe_duration_seconds
```

**Create the alert:**
```yaml
Alert Name: Service Down
Query: probe_success{job="blackbox-http"} == 0
For: 1m
Summary: Service {{ $labels.instance }} is DOWN
```

**Restore service:**
```bash
sudo systemctl start nginx
```

---

### Scenario 7: Process Died — Detect Critical Process Restart/Death

**What you will learn:** Detect when a critical process (like a database, app server) unexpectedly dies.

**PromQL queries for process monitoring:**
```promql
# Check if a process is running (requires --collector.processes flag on Node Exporter)
node_processes_state{state="running"}

# Number of zombie processes (processes that died but parent hasn't cleaned up)
node_processes_state{state="zombie"}

# Total number of processes
node_processes_threads

# Specific process detection (using systemd collector)
node_systemd_unit_state{name="nginx.service", state="active"}
```

**Create the alert:**
```yaml
Alert Name: Critical Service Not Active
Query: node_systemd_unit_state{name=~"nginx.service|postgresql.service|myapp.service", state="active"} == 0
For: 2m
Summary: Service {{ $labels.name }} on {{ $labels.instance }} is not active
```

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP
sudo systemctl stop nginx
```

**In Grafana Explore, run:**
```promql
node_systemd_unit_state{name="nginx.service"}
# You will see state="active" drop to 0 and state="inactive" become 1
```

---

### Scenario 8: Certificate Expiry — Monitor TLS Certificate Expiration

**What you will learn:** Get alerted before SSL certificates expire (this causes service outages if missed!).

**Setup — Add cert monitoring to Prometheus:**
```bash
# On Monitoring VM: Add HTTPS endpoint to blackbox probing
sudo tee -a /etc/prometheus/prometheus.yml << 'EOF'

  - job_name: 'blackbox-ssl'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://your-domain.com    # Replace with your actual HTTPS endpoint
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
EOF

sudo systemctl restart prometheus
```

**PromQL queries for certificate monitoring:**
```promql
# Days until certificate expires
(probe_ssl_earliest_cert_expiry - time()) / 86400

# Alert if cert expires in less than 30 days
(probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
```

**Create the alert:**
```yaml
Alert Name: SSL Certificate Expiring Soon
Query: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
For: 1h
Labels:
  severity: warning
Summary: Certificate for {{ $labels.instance }} expires in {{ $value | printf "%.0f" }} days
```

**Create a critical alert for very soon:**
```yaml
Alert Name: SSL Certificate Expiring CRITICAL
Query: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 7
For: 1h
Labels:
  severity: critical
Summary: CRITICAL — Certificate for {{ $labels.instance }} expires in {{ $value | printf "%.0f" }} days!
```

---

### Scenario 9: High Load Average — System Overloaded

**What you will learn:** Load average is the number of processes waiting to run. High load = system is overwhelmed (more work than capacity).

**Trigger the problem:**
```bash
ssh azureuser@$APP_IP

# Simulate high system load (8 workers competing for CPU)
stress-ng --cpu 8 --timeout 60s &
```

**What to observe in Grafana:**
```promql
# Load average (1 minute, 5 minute, 15 minute)
node_load1    # 1-minute load average
node_load5    # 5-minute load average
node_load15   # 15-minute load average

# Load average relative to CPU count (> 1.0 means overloaded)
node_load1 / count without(cpu, mode)(node_cpu_seconds_total{mode="idle"})
```

**How to read load average:**
- Load of `1.0` on a 2-core machine = 50% utilized (normal)
- Load of `2.0` on a 2-core machine = 100% utilized (at capacity)
- Load of `4.0` on a 2-core machine = 200% (severely overloaded, queue building)

**Create the alert:**
```yaml
Alert Name: High System Load
Query: node_load5 / count without(cpu,mode)(node_cpu_seconds_total{mode="idle"}) > 2
For: 10m
Summary: {{ $labels.instance }} load average is {{ $value | printf "%.2f" }}x CPU count — system overloaded
```

---

### Scenario 10: Security Scenario — Detect Brute Force Login Attempts

**What you will learn:** Detect suspicious authentication failures that could indicate a brute force attack.

**Setup — Configure SSH log monitoring:**

For this scenario you need Loki (log aggregation) or use Prometheus with the `systemd` and `journal` log exporter. Here we use the **Prometheus fail2ban exporter** approach which is simpler.

```bash
ssh azureuser@$APP_IP

# Install fail2ban (protects against brute force)
sudo apt-get install -y fail2ban

# Enable SSH jail
sudo tee /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 600
findtime = 600
EOF

sudo systemctl restart fail2ban

# Install fail2ban exporter for Prometheus
pip3 install prometheus-fail2ban-exporter 2>/dev/null || \
  sudo apt-get install -y python3-pip && pip3 install prometheus-fail2ban-exporter
```

**Trigger the problem (from your local machine or another VM):**
```bash
# Simulate multiple failed SSH logins (use a fake username)
for i in {1..10}; do
  ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
    fakeuser@$APP_IP 2>/dev/null || true
done
```

**Check in Grafana (using Node Exporter systemd or log metrics):**
```promql
# If using fail2ban exporter
fail2ban_banned_ips{jail="sshd"}

# Check for failed auth attempts via auth.log (needs log exporter)
# Alternative: Monitor with Azure Security Center (Azure Defender)
```

**Using Azure Monitor for security monitoring:**
```bash
# On Monitoring VM: Query Azure Monitor for failed logins via Azure CLI
az monitor metrics list \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/grafana-monitoring-rg/providers/Microsoft.Compute/virtualMachines/app-server-01" \
  --metric "Disk Read Bytes" \
  --interval PT1M \
  --output table
```

**Create the alert (via Grafana + Azure Monitor datasource):**
```yaml
Alert Name: Brute Force Attack Detected
Query: increase(fail2ban_banned_ips{jail="sshd"}[10m]) > 0
For: 1m
Labels:
  severity: critical
  type: security
Summary: Possible brute force attack on {{ $labels.instance }} — {{ $value }} IPs banned
```

---

### Summary Table: All 10 Scenarios

| # | Scenario | How to Trigger | Key Metric | Alert Threshold |
|---|---|---|---|---|
| 1 | CPU Spike | `stress-ng --cpu 2` | `node_cpu_seconds_total` | > 85% for 5m |
| 2 | Memory Exhaustion | `stress-ng --vm 1 --vm-bytes 500M` | `node_memory_MemAvailable_bytes` | > 85% used for 5m |
| 3 | Disk Full | `fallocate -l 2G /tmp/test` | `node_filesystem_avail_bytes` | > 80% full for 5m |
| 4 | High Disk I/O | `stress-ng --io 4 --hdd 2` | `node_disk_io_time_seconds_total` | > 80% busy for 5m |
| 5 | Network Spike | `wget -O /dev/null <big-file>` | `node_network_transmit_bytes_total` | > 100 MB/s for 5m |
| 6 | Service Down | `systemctl stop nginx` | `probe_success` | == 0 for 1m |
| 7 | Process Died | `systemctl stop nginx` | `node_systemd_unit_state` | inactive for 2m |
| 8 | Cert Expiry | (time-based) | `probe_ssl_earliest_cert_expiry` | < 30 days |
| 9 | High Load Avg | `stress-ng --cpu 8` | `node_load5` | > 2x CPU for 10m |
| 10 | Brute Force | Multiple failed SSH | `fail2ban_banned_ips` | > 0 increase in 10m |

---

## 8. Common Beginner Mistakes & Fixes

### Mistake 1: Dashboard shows "No data"

**Cause:** Wrong time range, wrong datasource URL, or Prometheus has no data yet.

```bash
# Fix 1: Check Prometheus has data
curl http://localhost:9090/api/v1/query?query=up
# Should show your targets with value=1

# Fix 2: Verify datasource URL in Grafana
# Go to: Administration > Data sources > Prometheus > Test

# Fix 3: Change time range in dashboard
# Top right > Select "Last 1 hour" or "Last 15 minutes"
```

### Mistake 2: Alerts configured but never fire

**Cause:** Alert rule has wrong condition, or no notification policy is set.

```bash
# Steps to debug:
# 1. Go to Alerting > Alert rules
# 2. Find your rule, check the "State" column
#    - "Normal" = condition is not met
#    - "Pending" = condition met, waiting for "For" duration
#    - "Firing" = alert is active and notifications are sent

# 3. Click the rule > Preview to see query results
# 4. Go to Alerting > Notification policies
#    Make sure there is a policy that routes to your contact point
```

### Mistake 3: Node Exporter port not reachable

```bash
# Check if Node Exporter is running
sudo systemctl status node_exporter

# Check if port 9100 is open in firewall
sudo ufw status
# or check Azure NSG rules

# Test from Monitoring VM
curl http://<APP_PRIVATE_IP>:9100/metrics | head -5
```

### Mistake 4: Prometheus not scraping targets

```bash
# Check Prometheus targets page
# Open browser: http://<MONITORING_IP>:9090/targets
# All targets should show "UP" state

# If a target shows DOWN:
# - Check Node Exporter is running on that VM
# - Check network connectivity (ping, curl)
# - Check firewall rules allow port 9100
# - Check prometheus.yml has the correct IP

# Validate prometheus.yml syntax
promtool check config /etc/prometheus/prometheus.yml

# Reload config without restart
curl -X POST http://localhost:9090/-/reload
```

### Mistake 5: Grafana password forgotten

```bash
# Reset admin password via CLI on the VM
grafana-cli admin reset-admin-password "NewPassword123!"

# Restart Grafana after reset
sudo systemctl restart grafana-server
```

---

## 9. Quick Reference Cheat Sheet

### Helm Commands

```bash
# Install monitoring stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --values monitoring-values.yaml

# Upgrade with new values
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --values monitoring-values.yaml --reuse-values

# Check release status
helm status kube-prometheus-stack -n monitoring

# Uninstall
helm uninstall kube-prometheus-stack -n monitoring
```

### kubectl Commands for Monitoring

```bash
# Watch all monitoring pods
kubectl get pods -n monitoring -w

# Get Grafana admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Check what Prometheus is scraping
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl http://localhost:9090/api/v1/targets | python3 -m json.tool
```

### Essential PromQL Queries

```promql
# ---- KUBERNETES ----

# Running pods per namespace
sum(kube_pod_status_phase{phase="Running"}) by (namespace)

# Pod CPU usage (cores)
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod)

# Pod memory usage (MB)
container_memory_working_set_bytes{container!=""} / 1024 / 1024

# Pod restart count in last hour
increase(kube_pod_container_status_restarts_total[1h])

# Pods in CrashLoopBackOff
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1

# ---- AZURE VM / NODE ----

# Node CPU usage %
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory available (GB)
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Node disk usage %
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Node network receive (MB/s)
rate(node_network_receive_bytes_total{device!="lo"}[5m]) / 1024 / 1024

# System load vs CPU count
node_load5 / count without(cpu,mode)(node_cpu_seconds_total{mode="idle"})
```

### Grafana Dashboard IDs to Import

| Dashboard ID | Name | Use Case |
|---|---|---|
| 1860 | Node Exporter Full | OS metrics for VMs and K8s nodes |
| 315 | Kubernetes Cluster Monitoring | Overall K8s cluster health |
| 13770 | K8s Compute Resources / Namespace (Pods) | Pod-level resource usage |
| 6781 | Kubernetes Pod Monitoring | Individual pod health |
| 8685 | K8s Deployment / Statefulset / Daemonset | Deployment rollout monitoring |
| 7249 | Kubernetes Cluster Overview | Executive summary view |
| 14518 | CoreDNS | DNS health in K8s |
| 9965 | ArgoCD | GitOps deployment status |

### Grafana API Quick Commands

```bash
# Test connection
curl http://admin:admin@localhost:3000/api/health

# List all dashboards
curl http://admin:admin@localhost:3000/api/search

# List datasources
curl http://admin:admin@localhost:3000/api/datasources

# Import dashboard by ID
curl -X POST http://admin:admin@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {"id": null},
    "inputs": [{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}],
    "folderId": 0,
    "overwrite": true
  }'
```

---

## Learning Path: What to Do Next

Now that you have the basics, here is what to do next in order:

```
Step 1 (You are here): ✅ Install Grafana + Prometheus
Step 2: Learn PromQL basics — spend 1 hour in the Explore tab writing queries
Step 3: Build 2-3 custom dashboards for your own apps
Step 4: Set up alerts for the most critical issues (CrashLoopBackOff, disk full, service down)
Step 5: Add log monitoring → read the elk-stack-guide.md to add Elasticsearch/Loki
Step 6: Add trace monitoring → read the jaeger-tracing-guide.md
Step 7: Correlate metrics + logs + traces in a single Grafana dashboard
Step 8: Automate dashboard provisioning via ConfigMaps (GitOps approach)
Step 9: Advanced alerting → read the monitoring-integration.md for Alertmanager routing
Step 10: Grafana as code → version control all dashboards as JSON in Git
```

**Related guides in this project:**
- [prometheus-complete-guide.md](prometheus-complete-guide.md) — Deep dive into Prometheus and PromQL
- [elk-stack-guide.md](elk-stack-guide.md) — Add log monitoring to Grafana
- [jaeger-tracing-guide.md](jaeger-tracing-guide.md) — Add distributed tracing
- [monitoring-integration.md](monitoring-integration.md) — Tie everything together
- [grafana-complete-guide.md](grafana-complete-guide.md) — Advanced Grafana reference

---

*Guide written for DevOps beginners who know Helm. Covers Kubernetes pod monitoring and Azure VM monitoring with 10 real-world scenarios.*
