# Prometheus Complete Guide

## Table of Contents

1. [Overview & Why Prometheus](#1-overview--why-prometheus)
2. [Local Setup on Minikube](#2-local-setup-on-minikube)
3. [Online/Cloud Setup](#3-onlinecloud-setup)
4. [Configuration Deep Dive](#4-configuration-deep-dive)
5. [Integration with Existing Tools](#5-integration-with-existing-tools)
6. [Real-World Scenarios](#6-real-world-scenarios)
7. [Verification & Testing](#7-verification--testing)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [PromQL Cheat Sheet](#9-promql-cheat-sheet)

---

## 1. Overview & Why Prometheus

### What Is Prometheus?

Prometheus is an open-source systems monitoring and alerting toolkit originally built at SoundCloud in 2012 and donated to the Cloud Native Computing Foundation (CNCF) in 2016. It is now a graduated CNCF project alongside Kubernetes, becoming the de-facto standard for monitoring cloud-native applications.

Prometheus collects and stores its metrics as **time-series data** — numerical values recorded with a timestamp and optional key-value labels. Every metric in Prometheus is identified by a metric name and a set of labels.

### Core Concepts

#### Time-Series Metrics

A time-series is a stream of timestamped values sharing the same metric name and label set:

```
http_requests_total{method="GET", status="200", handler="/api/v1/pods"} 1234 @1705000000
http_requests_total{method="POST", status="500", handler="/api/v1/pods"} 12   @1705000000
```

Each unique combination of `{metric_name + labels}` forms one time-series.

#### Metric Types

| Type      | Description                                                     | Example                            |
|-----------|-----------------------------------------------------------------|------------------------------------|
| Counter   | Monotonically increasing value, never decreases                 | `http_requests_total`              |
| Gauge     | Can go up or down, snapshot of current state                    | `node_memory_MemAvailable_bytes`   |
| Histogram | Samples observations into configurable buckets                  | `http_request_duration_seconds`    |
| Summary   | Similar to histogram but calculates quantiles on client side    | `go_gc_duration_seconds`           |

#### Pull Model vs Push Model

Prometheus uses a **pull model** — it scrapes HTTP endpoints (`/metrics`) at regular intervals. This is fundamentally different from tools like StatsD or InfluxDB that use a push model.

**Advantages of Pull:**
- Prometheus controls the scrape interval — no data loss if a target is momentarily unavailable
- Easy to check if a target is up (if scrape fails, Prometheus knows immediately)
- Targets do not need to know where Prometheus is located
- Works well with service discovery — Prometheus finds targets dynamically

**When Push is needed:** For short-lived jobs (batch jobs, cron jobs), Prometheus provides the **Pushgateway** component to accept pushed metrics and expose them for scraping.

#### PromQL

PromQL (Prometheus Query Language) is a functional language for querying time-series data. It allows:
- Instant vectors: current value of a metric
- Range vectors: values over a time window
- Aggregations: sum, avg, min, max, count across labels
- Functions: rate(), irate(), increase(), histogram_quantile()

### Prometheus vs Commercial Alternatives

| Feature                  | Prometheus          | Datadog               | New Relic             |
|--------------------------|---------------------|-----------------------|-----------------------|
| Cost                     | Free, open-source   | ~$15-27/host/month    | Consumption-based     |
| Deployment               | Self-hosted         | SaaS                  | SaaS                  |
| Data Retention           | Configurable (local)| 15 months (paid)      | 8 days (free)         |
| Query Language           | PromQL              | Proprietary           | NRQL                  |
| Kubernetes Native        | ✅ First-class       | ✅ Agent required      | ✅ Agent required      |
| Cardinality Limits       | Hardware dependent  | Paid feature limits   | Strict limits         |
| Long-term Storage        | Needs Thanos/Cortex | Built-in              | Built-in              |
| Custom Metrics           | ✅ Unlimited         | Limited by cost        | Limited by cost        |
| Alertmanager             | Built-in            | Built-in              | Built-in              |
| OpenTelemetry Support    | ✅ Via OTLP          | ✅                     | ✅                     |
| CNCF Project             | ✅ Graduated         | ❌                     | ❌                     |

**Why choose Prometheus in a DevOps project:**
- Zero licensing cost — suitable for learning and production
- First-class Kubernetes integration via kube-prometheus-stack
- Industry-standard for cloud-native environments
- Rich ecosystem: exporters for everything (databases, message queues, hardware)
- Grafana natively uses Prometheus as a data source

---

## 2. Local Setup on Minikube

### Prerequisites

```bash
# Verify tools
minikube version
# minikube version: v1.32.0

kubectl version --client
# Client Version: v1.29.0

helm version
# version.BuildInfo{Version:"v3.14.0"}
```

### Step 1: Start Minikube with Adequate Resources

```bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=20g \
  --driver=docker \
  --kubernetes-version=v1.29.0

# Expected output:
# 😄  minikube v1.32.0 on Linux (amd64)
# ✨  Using the docker driver based on user configuration
# 📌  Using Docker driver with root privileges
# 👍  Starting control plane node minikube in cluster minikube
# 🚜  Pulling base image ...
# 🔥  Creating docker container (CPUs=4, Memory=8192MB) ...
# 🐳  Preparing Kubernetes v1.29.0 on Docker 25.0.2 ...
# 🔗  Configuring bridge CNI (Container Networking Interface) ...
# 🔎  Verifying Kubernetes components...
# 🌟  Enabled addons: storage-provisioner, default-storageclass
# 🏄  Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default
```

### Step 2: Enable Required Minikube Addons

```bash
minikube addons enable metrics-server
# 💡  metrics-server is an addon maintained by Kubernetes. For any concerns contact minikube on GitHub.
# 🌟  The 'metrics-server' addon is enabled

minikube addons enable ingress
# 🔎  Verifying ingress addon...
# 🌟  The 'ingress' addon is enabled
```

### Step 3: Add the Prometheus Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add stable https://charts.helm.sh/stable
helm repo update

# Expected output:
# "prometheus-community" has been added to your repositories
# Hang tight while we grab the latest from your chart repositories...
# ...Successfully got an update from the "prometheus-community" chart repository
# Update Complete. ⎈Happy Helming!⎈
```

### Step 4: Create Monitoring Namespace

```bash
kubectl create namespace monitoring
# namespace/monitoring created
```

### Step 5: Create Custom Values File

```bash
cat > prometheus-values.yaml << 'EOF'
# kube-prometheus-stack values for Minikube

# Prometheus configuration
prometheus:
  prometheusSpec:
    # Retention period
    retention: 7d
    retentionSize: "5GB"
    
    # Resource limits appropriate for Minikube
    resources:
      requests:
        memory: 400Mi
        cpu: 100m
      limits:
        memory: 1Gi
        cpu: 500m
    
    # Storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

    # Scrape all ServiceMonitors across all namespaces
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}
    
    # Scrape all PodMonitors
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector: {}

# Grafana configuration
grafana:
  enabled: true
  adminPassword: "<REPLACE_WITH_SECURE_PASSWORD>"  # Use a strong password; never commit real passwords to git
  service:
    type: NodePort
    nodePort: 32000
  persistence:
    enabled: true
    size: 2Gi
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
          path: /var/lib/grafana/dashboards/default

# Alertmanager configuration
alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 100Mi
        cpu: 50m
      limits:
        memory: 200Mi
        cpu: 100m

# Node exporter - collects host-level metrics
nodeExporter:
  enabled: true

# kube-state-metrics - collects K8s object state
kubeStateMetrics:
  enabled: true

# Prometheus Operator
prometheusOperator:
  resources:
    requests:
      memory: 100Mi
      cpu: 50m
    limits:
      memory: 200Mi
      cpu: 100m
EOF
```

### Step 6: Install kube-prometheus-stack

```bash
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --version 56.6.2 \
  --wait \
  --timeout 10m

# Expected output:
# NAME: prometheus-stack
# LAST DEPLOYED: Mon Jan 15 10:00:00 2024
# NAMESPACE: monitoring
# STATUS: deployed
# REVISION: 1
# NOTES:
# kube-prometheus-stack has been installed. Check its status by running:
#   kubectl --namespace monitoring get pods -l "release=prometheus-stack"
```

### Step 7: Verify All Pods Are Running

```bash
kubectl get pods -n monitoring

# Expected output:
# NAME                                                        READY   STATUS    RESTARTS   AGE
# alertmanager-prometheus-stack-kube-prom-alertmanager-0      2/2     Running   0          3m
# prometheus-prometheus-stack-kube-prom-prometheus-0          2/2     Running   0          3m
# prometheus-stack-grafana-5d4c9b8b7f-x9vkj                  3/3     Running   0          3m
# prometheus-stack-kube-prom-operator-7c9f8b4d9c-p2r8n       1/1     Running   0          3m
# prometheus-stack-kube-state-metrics-6c8f9d8b7f-z4w2x       1/1     Running   0          3m
# prometheus-stack-prometheus-node-exporter-4xk9p             1/1     Running   0          3m
```

### Step 8: Access Prometheus UI

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &

# Access at: http://localhost:9090
echo "Prometheus UI available at http://localhost:9090"

# Verify Prometheus is up
curl -s http://localhost:9090/api/v1/status/config | python3 -m json.tool | head -20
```

### Step 9: Access Grafana UI

```bash
# Get Grafana NodePort
kubectl get svc -n monitoring prometheus-stack-grafana
# NAME                       TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
# prometheus-stack-grafana   NodePort   10.100.200.100   <none>        80:32000/TCP   5m

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Grafana available at http://$MINIKUBE_IP:32000"
echo "Username: admin / Password: admin123"

# Or use port-forward
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &
echo "Grafana available at http://localhost:3000"
```

### Step 10: Verify Targets Are Being Scraped

```bash
# Check Prometheus targets via API
curl -s http://localhost:9090/api/v1/targets | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets'][:5]:
    print(f\"{t['labels']['job']}: {t['health']}\")
"

# Expected output:
# apiserver: up
# kube-state-metrics: up
# node-exporter: up
# prometheus: up
# alertmanager: up
```

---

## 3. Online/Cloud Setup

### Option A: Azure Monitor with Prometheus

Azure Monitor managed service for Prometheus is a fully managed, scalable solution with 18 months data retention.

#### Enable Azure Monitor on AKS

```bash
# Login to Azure
az login

# Set variables
RESOURCE_GROUP="devops-rg"
CLUSTER_NAME="devops-aks"
WORKSPACE_NAME="devops-monitor-workspace"
LOCATION="eastus"

# Create Azure Monitor Workspace
az monitor account create \
  --name $WORKSPACE_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Enable Prometheus on existing AKS cluster
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id \
    $(az monitor account show --name $WORKSPACE_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

# Verify
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query "azureMonitorProfile" -o json
```

#### Access Azure Managed Grafana

```bash
# Create Azure Managed Grafana
az grafana create \
  --name devops-grafana \
  --resource-group $RESOURCE_GROUP

# Link Grafana to Azure Monitor workspace
az grafana update \
  --name devops-grafana \
  --resource-group $RESOURCE_GROUP
```

### Option B: Killercoda (Free Online Lab)

Killercoda provides free Ubuntu environments with Kubernetes already installed.

1. Visit [https://killercoda.com/prometheus](https://killercoda.com/prometheus)
2. Launch "Prometheus Fundamentals" scenario
3. The environment includes:
   - A running Kubernetes cluster
   - Helm pre-installed
   - kubectl configured

```bash
# In Killercoda terminal - install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set server.service.type=NodePort \
  --set server.service.nodePort=30090

# Access via provided URL pattern:
# https://<session-id>-30090.spch.r.killercoda.com
```

### Option C: Prometheus + Grafana Cloud

```bash
# Install Grafana Agent on Kubernetes to forward metrics to Grafana Cloud
kubectl create namespace grafana-agent

cat > grafana-agent-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-agent-config
  namespace: grafana-agent
data:
  agent.yaml: |
    metrics:
      global:
        scrape_interval: 60s
        remote_write:
          - url: https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push
            basic_auth:
              username: "<YOUR_GRAFANA_CLOUD_METRICS_USERNAME>"
              password: "<YOUR_GRAFANA_CLOUD_API_KEY>"
      configs:
        - name: default
          scrape_configs:
            - job_name: kubernetes-pods
              kubernetes_sd_configs:
                - role: pod
EOF

kubectl apply -f grafana-agent-config.yaml
```

---

## 4. Configuration Deep Dive

### 4.1 prometheus.yaml Configuration Explained

The main Prometheus configuration file controls scraping behavior, alerting rules, and remote storage.

```yaml
# prometheus.yaml - Full configuration with explanations

# Global configuration applies to all scrape jobs unless overridden
global:
  # How frequently to scrape targets by default
  scrape_interval: 15s        # Scrape every 15 seconds
  
  # How long to wait for a scrape request before timing out
  scrape_timeout: 10s         # Must be <= scrape_interval
  
  # How frequently to evaluate alerting rules
  evaluation_interval: 15s    # Check alert conditions every 15 seconds
  
  # Labels added to all time-series and alerts
  external_labels:
    cluster: "minikube-dev"   # Identify cluster in federation/remote storage
    environment: "development"

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "alertmanager:9093"   # Alertmanager service address
      # Optional TLS for secure communication
      # tls_config:
      #   ca_file: /etc/prometheus/tls/ca.crt

# Rule files location - glob pattern supported
rule_files:
  - "/etc/prometheus/rules/*.yaml"    # Load all rule files
  - "/etc/prometheus/alerts/*.yaml"

# Remote write - send metrics to long-term storage (Thanos, Cortex, Mimir)
remote_write:
  - url: "http://thanos-receive:10908/api/v1/receive"
    queue_config:
      max_samples_per_send: 10000
      max_shards: 200
      capacity: 2500

# Scrape configurations
scrape_configs:
  # Scrape Prometheus itself
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
    # Relabeling - modify labels before ingestion
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # Kubernetes API server
  - job_name: "kubernetes-apiservers"
    kubernetes_sd_configs:
      - role: endpoints    # Discover via K8s endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      # Only keep the kubernetes apiserver endpoints
      - source_labels:
          - __meta_kubernetes_namespace
          - __meta_kubernetes_service_name
          - __meta_kubernetes_endpoint_port_name
        action: keep
        regex: default;kubernetes;https

  # Node exporter - host metrics
  - job_name: "kubernetes-nodes"
    kubernetes_sd_configs:
      - role: node
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/${1}/proxy/metrics

  # Kubernetes pods with prometheus.io annotations
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # Only scrape pods with annotation prometheus.io/scrape: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # Use custom port if specified
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: (\d+)
        replacement: $1
        target_label: __meta_kubernetes_pod_container_port_number
      # Use custom path if specified
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      # Copy pod labels to metric labels
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      # Add namespace label
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      # Add pod name label
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
```

### 4.2 ServiceMonitor CRD

The ServiceMonitor CRD is provided by the Prometheus Operator and is the recommended way to configure scraping in Kubernetes.

```yaml
# servicemonitor-example.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-servicemonitor
  namespace: monitoring           # Must be in monitoring namespace (or where Prometheus is)
  labels:
    release: prometheus-stack     # Must match Prometheus's serviceMonitorSelector
spec:
  # Which namespaces to watch for matching services
  namespaceSelector:
    matchNames:
      - default
      - production
  
  # Label selector to find the Service to scrape
  selector:
    matchLabels:
      app: myapp
      monitoring: "true"
  
  # Endpoints to scrape
  endpoints:
    - port: metrics               # Port name on the Service
      interval: 30s               # Scrape every 30 seconds
      path: /metrics              # Metrics endpoint path
      scheme: http
      
      # Optional: Basic auth
      # basicAuth:
      #   username:
      #     name: myapp-secret
      #     key: username
      #   password:
      #     name: myapp-secret
      #     key: password
      
      # Optional: TLS configuration
      # tlsConfig:
      #   ca:
      #     secret:
      #       name: myapp-tls
      #       key: ca.crt
      
      # Relabeling applied after scraping
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
      
      # Metric relabeling - drop high-cardinality or unused metrics
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: "go_.*"          # Drop Go runtime metrics to save space
          action: drop

---
# The corresponding Service that ServiceMonitor selects
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
    monitoring: "true"            # Must match ServiceMonitor selector
spec:
  selector:
    app: myapp
  ports:
    - name: metrics               # Must match ServiceMonitor endpoint port name
      port: 8080
      targetPort: 8080
```

### 4.3 PrometheusRule for Alerting

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kubernetes-alerts
  namespace: monitoring
  labels:
    release: prometheus-stack     # Must match Prometheus ruleSelector
spec:
  groups:
    # CPU Alerts
    - name: cpu.alerts
      interval: 30s               # Evaluation interval for this group
      rules:
        - alert: HighCPUUsage
          # node_cpu_seconds_total tracks CPU time in different modes
          # rate() calculates per-second rate over 5 minutes
          # 1 - idle_rate = usage_rate
          expr: |
            (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (node)) * 100 > 80
          for: 5m                 # Must be true for 5 minutes before firing
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "High CPU usage on node {{ $labels.node }}"
            description: "CPU usage is {{ printf \"%.2f\" $value }}% on node {{ $labels.node }}, which is above 80% threshold."
            runbook: "https://wiki.company.com/runbooks/high-cpu"

        - alert: CriticalCPUUsage
          expr: |
            (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (node)) * 100 > 95
          for: 2m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Critical CPU usage on node {{ $labels.node }}"
            description: "CPU usage is {{ printf \"%.2f\" $value }}% on node {{ $labels.node }}"

    # Memory Alerts
    - name: memory.alerts
      rules:
        - alert: HighMemoryUsage
          expr: |
            (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage on node {{ $labels.node }}"
            description: "Memory usage is {{ printf \"%.2f\" $value }}% on node {{ $labels.node }}"

        - alert: NodeMemoryPressure
          expr: |
            kube_node_status_condition{condition="MemoryPressure", status="true"} == 1
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ $labels.node }} is under memory pressure"
            description: "Kubernetes reports MemoryPressure condition on node {{ $labels.node }}"

    # Pod Health Alerts
    - name: pod.alerts
      rules:
        - alert: PodCrashLoopBackOff
          expr: |
            kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is in CrashLoopBackOff"
            description: "Container {{ $labels.container }} in pod {{ $labels.pod }} is CrashLoopBackOff."

        - alert: PodNotReady
          expr: |
            kube_pod_status_ready{condition="true"} == 0
            and
            kube_pod_status_phase{phase=~"Running|Pending"} == 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is not ready"
            description: "Pod {{ $labels.pod }} has been not-ready for more than 5 minutes."

        - alert: PodRestartingTooOften
          expr: |
            rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 5
          for: 0m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is restarting frequently"
            description: "Pod {{ $labels.pod }} container {{ $labels.container }} restarted {{ $value }} times in 15 minutes."

        - alert: PodOOMKilled
          expr: |
            kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
          for: 0m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} was OOMKilled"
            description: "Container {{ $labels.container }} was killed due to out-of-memory."

    # Deployment Alerts
    - name: deployment.alerts
      rules:
        - alert: DeploymentReplicasMismatch
          expr: |
            kube_deployment_spec_replicas != kube_deployment_status_available_replicas
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} replica mismatch"
            description: "Deployment {{ $labels.deployment }} has {{ $value }} available replicas but spec requires {{ $labels.replicas }}."

        - alert: DeploymentRolloutStuck
          expr: |
            kube_deployment_status_observed_generation
              != kube_deployment_metadata_generation
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} rollout is stuck"

    # Disk Alerts
    - name: disk.alerts
      rules:
        - alert: DiskSpaceWarning
          expr: |
            (1 - node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"}) * 100 > 75
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Low disk space on {{ $labels.instance }}"
            description: "Disk {{ $labels.device }} on {{ $labels.instance }} is {{ printf \"%.2f\" $value }}% full."

        - alert: DiskSpaceCritical
          expr: |
            (1 - node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"}) * 100 > 90
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Critical disk space on {{ $labels.instance }}"
```

### 4.4 Alertmanager Configuration

```yaml
# alertmanager-config.yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: slack-alerting
  namespace: monitoring
spec:
  # Routing tree
  route:
    # Default receiver for all alerts
    receiver: "slack-notifications"
    
    # Group alerts by these labels to reduce noise
    groupBy:
      - alertname
      - cluster
      - namespace
    
    # Wait for new alerts to group before sending (reduce alert spam)
    groupWait: 30s
    
    # Wait between sending alerts for same group
    groupInterval: 5m
    
    # Resend if alert is still firing
    repeatInterval: 4h
    
    # Child routes for specific conditions
    routes:
      # Critical alerts go to pagerduty
      - receiver: "pagerduty-critical"
        matchers:
          - name: severity
            value: critical
        groupWait: 0s             # Send critical alerts immediately
        repeatInterval: 1h
      
      # Warning alerts to Slack
      - receiver: "slack-warnings"
        matchers:
          - name: severity
            value: warning
      
      # Silence deployment alerts outside business hours
      - receiver: "null"
        matchers:
          - name: alertname
            value: DeploymentReplicasMismatch
        activeTimeIntervals:
          - nights-and-weekends

  # Inhibition rules - suppress child alerts when parent fires
  inhibitRules:
    - sourceMatchers:
        - name: severity
          value: critical
      targetMatchers:
        - name: severity
          value: warning
      equal:
        - alertname
        - cluster
        - namespace

  # Receivers
  receivers:
    - name: "slack-notifications"
      slackConfigs:
        - apiURL:
            name: alertmanager-secrets
            key: slack-api-url
          channel: "#alerts-monitoring"
          sendResolved: true
          title: |-
            [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] 
            {{ .CommonLabels.alertname }}
          text: |-
            {{ range .Alerts }}
            *Alert:* {{ .Annotations.summary }}
            *Description:* {{ .Annotations.description }}
            *Severity:* {{ .Labels.severity }}
            *Namespace:* {{ .Labels.namespace }}
            *Started:* {{ .StartsAt | since }}
            {{ end }}
          color: |-
            {{ if eq .Status "firing" -}}
              {{ if eq .CommonLabels.severity "critical" -}}danger
              {{- else if eq .CommonLabels.severity "warning" -}}warning
              {{- else -}}#439FE0
              {{- end -}}
            {{ else -}}good
            {{- end }}
          actions:
            - type: button
              text: "Runbook :books:"
              url: "{{ (index .Alerts 0).Annotations.runbook }}"

    - name: "slack-warnings"
      slackConfigs:
        - apiURL:
            name: alertmanager-secrets
            key: slack-api-url
          channel: "#alerts-warnings"
          sendResolved: true
          title: "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
          text: "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"

    - name: "pagerduty-critical"
      pagerdutyConfigs:
        - routingKey:
            name: alertmanager-secrets
            key: pagerduty-routing-key
          description: "{{ .CommonAnnotations.summary }}"
          severity: "{{ .CommonLabels.severity }}"

    - name: "null"   # Discard alerts

  # Time intervals
  timeIntervals:
    - name: nights-and-weekends
      timeIntervals:
        - times:
            - startTime: "00:00"
              endTime: "09:00"
            - startTime: "18:00"
              endTime: "24:00"
          weekdays:
            - monday:friday
        - weekdays:
            - saturday
            - sunday

---
# Secret for alertmanager credentials
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-secrets
  namespace: monitoring
type: Opaque
stringData:
  slack-api-url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
  pagerduty-routing-key: "YOUR_PAGERDUTY_ROUTING_KEY"
```

### 4.5 PersistentVolume for Data Retention

```yaml
# prometheus-pv.yaml - For local Minikube storage
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-data-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain  # Keep data after PVC deletion
  storageClassName: standard
  hostPath:
    path: /data/prometheus                # Minikube host path

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

---

## 5. Integration with Existing Tools

### 5.1 Kubernetes Integration

#### node_exporter Metrics

node_exporter provides hardware and OS-level metrics from K8s nodes:

```bash
# Key node_exporter metrics
node_cpu_seconds_total             # CPU time breakdown by mode (idle, user, system, iowait)
node_memory_MemTotal_bytes         # Total RAM
node_memory_MemAvailable_bytes     # Available RAM
node_filesystem_size_bytes         # Filesystem size
node_filesystem_avail_bytes        # Filesystem available space
node_network_receive_bytes_total   # Network bytes received
node_network_transmit_bytes_total  # Network bytes transmitted
node_disk_read_bytes_total         # Disk read bytes
node_disk_written_bytes_total      # Disk write bytes
node_load1                         # 1-minute load average
node_load5                         # 5-minute load average
node_load15                        # 15-minute load average
```

#### kube-state-metrics

kube-state-metrics exposes the state of Kubernetes objects:

```bash
# Key kube-state-metrics metrics
kube_pod_status_phase              # Pod phase (Running, Pending, Failed, Succeeded, Unknown)
kube_pod_status_ready              # Pod readiness condition
kube_pod_container_status_restarts_total  # Container restart count
kube_deployment_spec_replicas      # Desired replicas
kube_deployment_status_available_replicas  # Available replicas
kube_node_status_condition         # Node conditions (Ready, MemoryPressure, DiskPressure)
kube_namespace_status_phase        # Namespace phase
kube_persistentvolumeclaim_status_phase  # PVC phase
```

#### cAdvisor Metrics

cAdvisor is built into kubelet and provides container resource usage metrics:

```bash
# Key cAdvisor metrics  
container_cpu_usage_seconds_total          # Container CPU usage
container_memory_usage_bytes               # Container memory usage (RSS + cache)
container_memory_working_set_bytes         # Container working set memory
container_network_receive_bytes_total      # Container network rx
container_network_transmit_bytes_total     # Container network tx
container_fs_usage_bytes                   # Container filesystem usage
```

### 5.2 Jenkins Integration

```bash
# Install Prometheus plugin in Jenkins
# Go to: Manage Jenkins > Plugin Manager > Available > Search "Prometheus metrics"
# Or install via Jenkins CLI:
java -jar jenkins-cli.jar -s http://localhost:8080/ install-plugin prometheus

# Jenkins exposes metrics at: http://jenkins:8080/prometheus
# Key Jenkins metrics:
# default_jenkins_builds_duration_milliseconds_summary
# default_jenkins_builds_failed_builds_total
# default_jenkins_queue_size_value
# default_jenkins_executors_available
```

```yaml
# ServiceMonitor for Jenkins
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins-metrics
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - jenkins
  selector:
    matchLabels:
      app.kubernetes.io/name: jenkins
  endpoints:
    - port: http
      path: /prometheus
      interval: 60s
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: jenkins_pod
```

### 5.3 JFrog Artifactory Integration

```yaml
# JFrog exposes metrics at /artifactory/api/v1/metrics
# Enable via: Admin > Artifactory > Advanced > Metrics

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jfrog-metrics
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - jfrog
  selector:
    matchLabels:
      app: artifactory
  endpoints:
    - port: router
      path: /artifactory/api/v1/metrics
      interval: 60s
      bearerTokenSecret:
        name: jfrog-admin-token
        key: token
```

### 5.4 SonarQube Integration

```yaml
# SonarQube exposes Prometheus metrics via sonar-prometheus-exporter plugin
# Download: https://github.com/dmeiners88/sonarqube-prometheus-exporter

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sonarqube-metrics
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - sonarqube
  selector:
    matchLabels:
      app: sonarqube
  endpoints:
    - port: http
      path: /api/monitoring/metrics
      interval: 60s
      basicAuth:
        username:
          name: sonarqube-monitoring-creds
          key: username
        password:
          name: sonarqube-monitoring-creds
          key: password
```

### 5.5 Grafana Integration as Data Source

```yaml
# grafana-datasource.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-stack-kube-prom-prometheus:9090
        isDefault: true
        editable: false
        jsonData:
          timeInterval: "15s"
          queryTimeout: "60s"
          httpMethod: POST
          exemplarTraceIdDestinations:
            - name: traceID
              datasourceUid: jaeger
```

---

## 6. Real-World Scenarios

### Scenario 1: Monitor K8s Cluster CPU/Memory/Pod Health

**Goal:** Build a comprehensive cluster health overview.

```bash
# Step 1: Run these PromQL queries in Prometheus UI (http://localhost:9090)

# Overall cluster CPU usage percentage
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# Per-node CPU usage
(1 - avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# Cluster memory usage percentage
(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100

# Count pods by phase
sum by (phase) (kube_pod_status_phase)

# Count running pods per namespace
sum by (namespace) (kube_pod_status_phase{phase="Running"})

# Pods with high restart count
topk(10, sum by (namespace, pod) (kube_pod_container_status_restarts_total))

# Nodes that are not Ready
kube_node_status_condition{condition="Ready", status="true"} == 0
```

```bash
# Step 2: Create an alert for critical pod health
kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-health
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
    - name: cluster-health
      rules:
        - alert: ClusterLowPodCapacity
          expr: |
            (sum(kube_pod_status_phase{phase="Running"}) / 
             sum(kube_node_status_allocatable{resource="pods"})) > 0.85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Cluster pod capacity above 85%"
            description: "{{ $value | humanizePercentage }} of pod capacity is being used."
EOF
```

### Scenario 2: Alert When Pod Is Down or CrashLoopBackOff

```bash
# Step 1: Deploy a test application
kubectl create deployment test-app --image=nginx --replicas=3
kubectl expose deployment test-app --port=80 --name=test-app

# Step 2: Annotate for Prometheus scraping
kubectl annotate deployment test-app \
  prometheus.io/scrape="true" \
  prometheus.io/port="80"

# Step 3: Simulate a crash by using bad image
kubectl set image deployment/test-app nginx=nginx:nonexistent-tag

# Step 4: Watch for CrashLoopBackOff alert in Prometheus
# Query: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}

# Step 5: Create specific alert
kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pod-down-alerts
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
    - name: pod-availability
      rules:
        - alert: DeploymentUnavailable
          expr: |
            kube_deployment_status_available_replicas == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has 0 available replicas"
            description: "All replicas of {{ $labels.deployment }} are unavailable."
        
        - alert: ImagePullBackOff
          expr: |
            kube_pod_container_status_waiting_reason{reason=~"ImagePullBackOff|ErrImagePull"} == 1
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Image pull failure for {{ $labels.namespace }}/{{ $labels.pod }}"
            description: "Container {{ $labels.container }} cannot pull its image."
EOF

# Step 6: Restore the deployment
kubectl set image deployment/test-app nginx=nginx:latest
```

### Scenario 3: Monitor Application Custom Metrics

```bash
# Step 1: Create a Python Flask app that exposes custom Prometheus metrics

cat > app.py << 'EOF'
from flask import Flask
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import time

app = Flask(__name__)

# Define custom metrics
REQUEST_COUNT = Counter(
    'myapp_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'myapp_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint'],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
)

ACTIVE_USERS = Gauge(
    'myapp_active_users',
    'Currently active users'
)

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/data')
def get_data():
    start = time.time()
    # Simulate processing
    time.sleep(0.1)
    duration = time.time() - start
    
    REQUEST_COUNT.labels(method='GET', endpoint='/api/data', status='200').inc()
    REQUEST_LATENCY.labels(method='GET', endpoint='/api/data').observe(duration)
    
    return {"data": "example"}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

# Step 2: Create Kubernetes deployment with ServiceMonitor
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: python:3.11-slim
        ports:
        - containerPort: 8080
          name: metrics
        command: ["/bin/sh", "-c"]
        args: ["pip install flask prometheus_client && python app.py"]
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
    monitoring: "true"
spec:
  selector:
    app: myapp
  ports:
  - name: metrics
    port: 8080
    targetPort: 8080
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  namespaceSelector:
    matchNames:
    - default
  selector:
    matchLabels:
      monitoring: "true"
  endpoints:
  - port: metrics
    interval: 15s
EOF

# Step 3: Query custom metrics in Prometheus
# Total requests per second by endpoint:
# rate(myapp_requests_total[5m])

# 99th percentile request latency:
# histogram_quantile(0.99, rate(myapp_request_duration_seconds_bucket[5m]))

# Error rate:
# rate(myapp_requests_total{status=~"5.."}[5m]) / rate(myapp_requests_total[5m])
```

---

## 7. Verification & Testing

### Using promtool

```bash
# promtool is included in the Prometheus binary

# Test rule file syntax
promtool check rules /etc/prometheus/rules/alerts.yaml
# Checking /etc/prometheus/rules/alerts.yaml
#   SUCCESS: 12 rules found

# Test PromQL query
promtool query instant http://localhost:9090 \
  'up{job="kubernetes-pods"}'

# Query range
promtool query range http://localhost:9090 \
  --start=2024-01-15T09:00:00Z \
  --end=2024-01-15T10:00:00Z \
  --step=1m \
  'rate(http_requests_total[5m])'

# Validate config file
promtool check config /etc/prometheus/prometheus.yaml
# Checking /etc/prometheus/prometheus.yaml
#   SUCCESS: 3 rule files found
#  SUCCESS

# Run unit tests for alerting rules
# Create test file:
cat > rules_test.yaml << 'EOF'
rule_files:
  - /etc/prometheus/rules/alerts.yaml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'node_cpu_seconds_total{mode="idle", node="node1"}'
        values: '0.9 0.85 0.8 0.75 0.7 0.6'
    alert_rule_test:
      - eval_time: 5m
        alertname: HighCPUUsage
        exp_alerts:
          - exp_labels:
              node: node1
              severity: warning
            exp_annotations:
              summary: "High CPU usage on node node1"
EOF
promtool test rules rules_test.yaml
```

### kubectl port-forward for Access

```bash
# Access Prometheus
kubectl port-forward -n monitoring \
  svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Access Alertmanager
kubectl port-forward -n monitoring \
  svc/prometheus-stack-kube-prom-alertmanager 9093:9093

# Access Grafana
kubectl port-forward -n monitoring \
  svc/prometheus-stack-grafana 3000:80

# Access node-exporter directly
kubectl port-forward -n monitoring \
  daemonset/prometheus-stack-prometheus-node-exporter 9100:9100

# Test node exporter metrics
curl -s http://localhost:9100/metrics | grep "node_cpu_seconds_total" | head -5
```

### Key PromQL Verification Queries

```bash
# Verify Prometheus is scraping targets
up

# Count total scrape targets
count(up)

# Count healthy targets
count(up == 1)

# See all active alerts
ALERTS{alertstate="firing"}

# Check scrape duration (identify slow targets)
scrape_duration_seconds > 1

# Verify recording rules exist
:node_memory_MemAvailable_bytes:sum

# Check for scrape errors
scrape_samples_post_metric_relabeling
```

---

## 8. Troubleshooting Guide

### Issue 1: Targets Showing as "Down" in Prometheus

**Symptoms:** Targets in Prometheus UI show `State: DOWN` or `Error: connection refused`

**Solution:**
```bash
# Check if the service exists and has correct labels
kubectl get svc -n <namespace> -l <selector>

# Check the service endpoint
kubectl get endpoints -n <namespace> <service-name>

# Test connectivity from Prometheus pod
kubectl exec -n monitoring -it prometheus-stack-kube-prom-prometheus-0 -- \
  wget -O- http://<service>.<namespace>.svc.cluster.local:<port>/metrics

# Check firewall/NetworkPolicy
kubectl get networkpolicy -n <namespace>
```

### Issue 2: ServiceMonitor Not Being Picked Up

**Symptoms:** New ServiceMonitor added but targets don't appear in Prometheus

**Solution:**
```bash
# Verify ServiceMonitor labels match Prometheus serviceMonitorSelector
kubectl get prometheus -n monitoring prometheus-stack-kube-prom-prometheus -o yaml | \
  grep -A5 serviceMonitorSelector

# Check ServiceMonitor has correct labels
kubectl get servicemonitor -n monitoring <name> -o yaml | grep -A5 labels

# Add the required label to ServiceMonitor
kubectl label servicemonitor <name> -n monitoring release=prometheus-stack

# Check Prometheus operator logs for errors
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator | tail -20
```

### Issue 3: High Cardinality Causing Memory Issues

**Symptoms:** Prometheus uses excessive memory, OOMKilled

**Solution:**
```bash
# Find high-cardinality metrics
curl -s http://localhost:9090/api/v1/status/tsdb | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
series = data['data']['seriesCountByMetricName'][:10]
for s in series:
    print(f\"{s['name']}: {s['value']} series\")
"

# Add metric relabeling to drop problematic labels or metrics
# In ServiceMonitor:
metricRelabelings:
  - sourceLabels: [le]
    regex: '.+'
    action: drop
    # Drops all histogram bucket labels
  - sourceLabels: [__name__]
    regex: 'some_high_cardinality_metric'
    action: drop
```

### Issue 4: Alertmanager Not Sending Notifications

**Symptoms:** Alerts fire in Prometheus but no Slack/PagerDuty messages received

**Solution:**
```bash
# Check alertmanager status
curl http://localhost:9093/api/v2/status

# Check active alerts in alertmanager
curl http://localhost:9093/api/v2/alerts | python3 -m json.tool

# Check alertmanager config
kubectl get secret -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager -o yaml | \
  base64 -d

# Check alertmanager logs
kubectl logs -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager-0 -c alertmanager

# Send a test alert to alertmanager
curl -XPOST http://localhost:9093/api/v1/alerts -d '[{
  "labels": {"alertname": "TestAlert", "severity": "warning"},
  "annotations": {"summary": "This is a test alert"}
}]'
```

### Issue 5: Prometheus Running Out of Disk Space

**Symptoms:** `no space left on device` errors, Prometheus crash

**Solution:**
```bash
# Check current storage usage
kubectl exec -n monitoring prometheus-stack-kube-prom-prometheus-0 -- \
  df -h /prometheus

# Reduce retention
kubectl patch prometheus -n monitoring prometheus-stack-kube-prom-prometheus \
  --type=merge -p '{"spec":{"retention":"3d"}}'

# Enable retention size limit
kubectl patch prometheus -n monitoring prometheus-stack-kube-prom-prometheus \
  --type=merge -p '{"spec":{"retentionSize":"4GB"}}'

# Check which metrics use most storage
curl http://localhost:9090/api/v1/status/tsdb | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print('Head blocks:', data['data']['headStats'])
"
```

### Issue 6: PromQL Query Returning Empty Results

**Symptoms:** Query returns `no data` in Grafana or empty `[]` in API

**Solution:**
```bash
# Verify the metric exists
curl "http://localhost:9090/api/v1/label/__name__/values" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
metrics = [m for m in data['data'] if 'cpu' in m]
print('\n'.join(metrics))
"

# Check metric labels
curl "http://localhost:9090/api/v1/series?match[]=node_cpu_seconds_total" | \
  python3 -m json.tool | head -30

# Broaden the time range
curl "http://localhost:9090/api/v1/query_range" \
  --data-urlencode 'query=up' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=60'
```

### Issue 7: Prometheus Operator CRDs Not Installed

**Symptoms:** `no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"`

**Solution:**
```bash
# Check if CRDs exist
kubectl get crd | grep monitoring.coreos.com

# Install CRDs manually if missing
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

# Or reinstall via Helm
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --reuse-values
```

### Issue 8: Recording Rules Not Working

**Symptoms:** Recording rule metrics not available for querying

**Solution:**
```bash
# Check rule evaluation status
curl http://localhost:9090/api/v1/rules | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for group in data['data']['groups']:
    for rule in group['rules']:
        if rule.get('lastError'):
            print(f\"ERROR in {rule['name']}: {rule['lastError']}\")
"

# Validate rule file
promtool check rules /path/to/rules.yaml

# Check PrometheusRule is loaded
kubectl get prometheusrule -n monitoring
kubectl describe prometheusrule -n monitoring <name>
```

### Issue 9: Slow Query Performance

**Symptoms:** PromQL queries timing out or taking too long

**Solution:**
```bash
# Use recording rules for expensive queries
# Instead of: sum(rate(http_requests_total[5m])) by (job, method)
# Create recording rule:
kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: recording-rules
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
  - name: http.rules
    interval: 30s
    rules:
    - record: job_method:http_requests_total:rate5m
      expr: sum(rate(http_requests_total[5m])) by (job, method)
EOF

# Optimize query with label matchers to reduce series scanned
# Bad:  rate(container_cpu_usage_seconds_total[5m])
# Good: rate(container_cpu_usage_seconds_total{namespace="production"}[5m])

# Increase query timeout
kubectl patch configmap -n monitoring prometheus-stack-kube-prom-prometheus \
  --type=merge \
  -p '{"data":{"query.timeout":"2m"}}'
```

### Issue 10: Grafana Shows "No Data" for Prometheus Datasource

**Symptoms:** Grafana panels show "No data" even though Prometheus has data

**Solution:**
```bash
# Test datasource connection in Grafana UI
# Configuration > Data Sources > Prometheus > Save & Test

# Check Grafana can reach Prometheus
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- wget -O- http://prometheus-stack-kube-prom-prometheus:9090/api/v1/query?query=up

# Check time range - ensure "Last 5 minutes" has data
# Sometimes timezone mismatch causes issues

# Verify datasource URL in Grafana ConfigMap
kubectl get configmap -n monitoring grafana-datasources -o yaml
```

---

## 9. PromQL Cheat Sheet

### Basic Queries

| Query | Description |
|-------|-------------|
| `up` | All targets and their status (1=up, 0=down) |
| `up{job="kubernetes-pods"}` | Targets in specific job |
| `count(up == 1)` | Count of healthy targets |
| `scrape_duration_seconds` | How long each scrape took |

### CPU Metrics

| Query | Description |
|-------|-------------|
| `rate(node_cpu_seconds_total{mode="idle"}[5m])` | CPU idle rate per second |
| `(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100` | Cluster CPU usage % |
| `(1 - avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100` | Per-node CPU % |
| `rate(container_cpu_usage_seconds_total{container!=""}[5m])` | Container CPU usage |
| `topk(5, rate(container_cpu_usage_seconds_total[5m]))` | Top 5 CPU containers |

### Memory Metrics

| Query | Description |
|-------|-------------|
| `node_memory_MemAvailable_bytes` | Available memory bytes |
| `(1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes) * 100` | Memory usage % |
| `container_memory_working_set_bytes{container!=""}` | Container working set |
| `sum by(pod)(container_memory_usage_bytes{container!=""})` | Memory per pod |

### Kubernetes Pod Metrics

| Query | Description |
|-------|-------------|
| `kube_pod_status_phase` | Pod phases |
| `sum by(phase)(kube_pod_status_phase)` | Count pods by phase |
| `kube_pod_container_status_restarts_total` | Container restart counts |
| `rate(kube_pod_container_status_restarts_total[15m]) * 900 > 3` | Pods restarting > 3 times in 15m |
| `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` | CrashLoopBackOff pods |
| `kube_deployment_status_available_replicas / kube_deployment_spec_replicas` | Deployment health ratio |

### Network Metrics

| Query | Description |
|-------|-------------|
| `rate(node_network_receive_bytes_total[5m])` | Network receive rate |
| `rate(node_network_transmit_bytes_total[5m])` | Network transmit rate |
| `sum(rate(container_network_receive_bytes_total[5m])) by(pod)` | Pod network rx |

### Disk Metrics

| Query | Description |
|-------|-------------|
| `(1 - node_filesystem_avail_bytes/node_filesystem_size_bytes) * 100` | Disk usage % |
| `predict_linear(node_filesystem_avail_bytes[1h], 4*3600) < 0` | Disk fills in 4h |
| `rate(node_disk_read_bytes_total[5m])` | Disk read rate |
| `rate(node_disk_written_bytes_total[5m])` | Disk write rate |

### HTTP Application Metrics

| Query | Description |
|-------|-------------|
| `rate(http_requests_total[5m])` | Request rate |
| `rate(http_requests_total{status=~"5.."}[5m])` | Error rate |
| `sum(rate(http_requests_total[5m])) by (status)` | Requests grouped by status |
| `histogram_quantile(0.99, rate(http_duration_seconds_bucket[5m]))` | P99 latency |
| `histogram_quantile(0.50, rate(http_duration_seconds_bucket[5m]))` | Median latency |

### Aggregation Functions

| Function | Description |
|----------|-------------|
| `sum()` | Sum all values |
| `avg()` | Average of all values |
| `min()` | Minimum value |
| `max()` | Maximum value |
| `count()` | Count of series |
| `topk(n, expr)` | Top N series by value |
| `bottomk(n, expr)` | Bottom N series by value |
| `quantile(φ, expr)` | φ-quantile over dimensions |

### Time Functions

| Function | Description |
|----------|-------------|
| `rate(metric[5m])` | Per-second rate over 5 minutes (use with counters) |
| `irate(metric[5m])` | Instant rate (last two data points) |
| `increase(metric[1h])` | Total increase over 1 hour |
| `delta(metric[1h])` | Delta over 1 hour (use with gauges) |
| `deriv(metric[5m])` | Per-second derivative |
| `predict_linear(metric[1h], 4*3600)` | Predict value in 4 hours |

### Label Operations

| Operation | Description |
|-----------|-------------|
| `metric{label="value"}` | Filter by exact label match |
| `metric{label=~"val.*"}` | Filter by regex match |
| `metric{label!="value"}` | Exclude label match |
| `metric{label!~"val.*"}` | Exclude regex match |
| `sum by(label)(metric)` | Aggregate keeping specific label |
| `sum without(label)(metric)` | Aggregate dropping specific label |
| `label_replace()` | Add/modify labels via regex |

---

*Last updated: 2024 | Maintained by DevOps Team*
