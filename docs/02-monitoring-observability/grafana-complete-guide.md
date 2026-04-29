# Grafana Complete Guide

## Table of Contents

1. [Overview & Why Grafana](#1-overview--why-grafana)
2. [Local Setup on Minikube](#2-local-setup-on-minikube)
3. [Online/Cloud Setup](#3-onlinecloud-setup)
4. [Configuration Deep Dive](#4-configuration-deep-dive)
5. [Integration with Existing Tools](#5-integration-with-existing-tools)
6. [Real-World Scenarios](#6-real-world-scenarios)
7. [Verification & Testing](#7-verification--testing)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [Grafana Cheat Sheet](#9-grafana-cheat-sheet)

---

## 1. Overview & Why Grafana

### What Is Grafana?

Grafana is an open-source analytics and interactive visualization platform that connects to a wide variety of data sources — metrics, logs, and traces — and displays them in richly configurable dashboards. Founded by Torkel Ödegaard in 2014, Grafana has grown into the de-facto standard dashboard solution for cloud-native operations, with over 800,000 active installations worldwide.

At its core, Grafana does not store data. Instead, it queries data sources and renders the results visually. This architecture makes it infinitely flexible — a single Grafana instance can show metrics from Prometheus, logs from Elasticsearch, traces from Jaeger, and business data from a PostgreSQL database, all side by side on the same dashboard.

### Core Concepts

#### Dashboards

A dashboard is a collection of panels arranged on a grid. Each panel is an independent visualization — a time-series graph, a stat number, a table, a heatmap, a pie chart, or a log viewer. Dashboards can be:
- **Parameterized** with template variables (e.g., `$namespace`, `$pod`) allowing a single dashboard to show data for any selection
- **Linked** to other dashboards for drill-down navigation
- **Provisioned as code** — stored as JSON and deployed via GitOps

#### Data Sources

Grafana supports 150+ data sources including:
- **Metrics:** Prometheus, InfluxDB, Graphite, Azure Monitor, Google Cloud Monitoring
- **Logs:** Elasticsearch, Loki, Splunk
- **Traces:** Jaeger, Zipkin, Tempo
- **Databases:** MySQL, PostgreSQL, MSSQL
- **Cloud:** CloudWatch, Azure Monitor, Datadog, Dynatrace

#### Alerting

Grafana Unified Alerting (GA since v9.0) allows creating alerts directly in dashboards:
- Multi-dimensional alerts (one rule can produce multiple alert instances)
- Contact points (Slack, PagerDuty, Teams, email)
- Notification policies with routing trees
- Silences and mute timings
- Alert history and state transitions

### Grafana vs Kibana

| Feature                  | Grafana                        | Kibana                          |
|--------------------------|--------------------------------|---------------------------------|
| Primary Use Case         | Metrics + multi-source viz     | Elasticsearch log exploration   |
| Data Sources             | 150+ sources                   | Elasticsearch only (native)     |
| Dashboard Language       | JSON + PromQL/SQL/etc          | JSON + KQL/ES-DSL               |
| Alerting                 | ✅ Unified alerting             | ✅ Via Elastic Alerts            |
| Log Correlation          | ✅ Via Loki/ES datasource       | ✅ Native                        |
| Trace Visualization      | ✅ Jaeger/Tempo/Zipkin          | ✅ APM                           |
| Metrics Visualization    | ✅ Excellent (built for it)     | ⚠️ Limited (via Elastic Metrics)|
| RBAC                     | ✅ Fine-grained                 | ✅ Role-based                    |
| Community Dashboards     | ✅ 5000+ on grafana.com         | Limited                         |
| GitOps/IaC               | ✅ JSON provisioning            | ✅ Saved objects API             |
| Cost                     | Free OSS / Grafana Enterprise  | Free OSS / Elastic paid         |

**Why choose Grafana in a DevOps project:**
- Unified view of metrics (Prometheus), logs (ELK/Loki), and traces (Jaeger)
- Massive library of pre-built community dashboards
- First-class Kubernetes dashboards with K8s-specific panel types
- Tight integration with Prometheus which is the K8s monitoring standard
- Grafana-as-code via JSON and Helm provisioning

---

## 2. Local Setup on Minikube

### Option A: Install with kube-prometheus-stack (Recommended)

If you followed the Prometheus guide and already have kube-prometheus-stack installed, Grafana is included. Skip to "Access Grafana UI."

```bash
# Verify Grafana is running
kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana
# NAME                                      READY   STATUS    RESTARTS   AGE
# prometheus-stack-grafana-5d4c9b8b7f-x9vkj 3/3     Running   0          10m

# Get admin password (if not set in values)
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

### Option B: Standalone Grafana via Helm

```bash
# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create values file
cat > grafana-standalone-values.yaml << 'EOF'
# Grafana standalone configuration
replicas: 1

# Admin credentials
adminUser: admin
adminPassword: "grafana123"

# Service configuration
service:
  type: NodePort
  nodePort: 32001

# Persistence
persistence:
  enabled: true
  size: 2Gi
  storageClassName: standard

# Grafana.ini overrides
grafana.ini:
  server:
    root_url: "%(protocol)s://%(domain)s:%(http_port)s/"
  auth:
    disable_login_form: false
  auth.anonymous:
    enabled: false
  security:
    allow_embedding: true
  unified_alerting:
    enabled: true
  
# Pre-configured datasources
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
        access: proxy
        isDefault: true
        editable: true
        jsonData:
          timeInterval: "15s"

# Pre-configured dashboard providers
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'kubernetes'
        orgId: 1
        folder: 'Kubernetes'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/kubernetes

# Import community dashboards from grafana.com
dashboards:
  kubernetes:
    k8s-cluster-overview:
      gnetId: 315        # Kubernetes cluster monitoring
      revision: 3
      datasource: Prometheus
    k8s-resource-requests:
      gnetId: 6417       # Kubernetes Resource Requests
      revision: 1
      datasource: Prometheus
    k8s-node-exporter:
      gnetId: 1860       # Node Exporter Full
      revision: 36
      datasource: Prometheus

# Resource limits
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
EOF

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-standalone-values.yaml \
  --wait

# Expected output:
# NAME: grafana
# LAST DEPLOYED: Mon Jan 15 10:00:00 2024
# NAMESPACE: monitoring
# STATUS: deployed
# REVISION: 1
# NOTES:
# 1. Get your 'admin' user password by running:
#    kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Access Grafana UI

```bash
# Method 1: Port-forward
kubectl port-forward -n monitoring svc/grafana 3000:80 &
# OR for kube-prometheus-stack:
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &

echo "Grafana available at: http://localhost:3000"
echo "Username: admin"
echo "Password: grafana123  (or admin123 for kube-prometheus-stack)"

# Method 2: Minikube NodePort
MINIKUBE_IP=$(minikube ip)
echo "Grafana available at: http://$MINIKUBE_IP:32001"

# Method 3: Minikube service (opens browser automatically)
minikube service grafana -n monitoring
```

### Default Credentials

```
URL:      http://localhost:3000
Username: admin
Password: (from values file or Secret - see above)
```

**First Login Steps:**
1. Navigate to http://localhost:3000
2. Login with admin credentials
3. Skip the "Add your first data source" wizard (already configured via provisioning)
4. Go to **Dashboards > Browse** to see pre-imported dashboards

---

## 3. Online/Cloud Setup

### Option A: Grafana Cloud Free Tier

Grafana Cloud offers a generous free tier:
- 10,000 active metrics series
- 50 GB logs
- 50 GB traces
- 14-day retention
- 3 users

```bash
# Step 1: Sign up at https://grafana.com/auth/sign-up/create-user

# Step 2: Create a free stack at https://grafana.com/products/cloud/

# Step 3: Install Grafana Agent on your Kubernetes cluster to ship metrics

# Create namespace
kubectl create namespace grafana-agent

# Create secret with Grafana Cloud credentials
kubectl create secret generic grafana-cloud-credentials \
  --namespace grafana-agent \
  --from-literal=metrics-username="<YOUR_METRICS_USERNAME>" \
  --from-literal=metrics-password="<YOUR_GRAFANA_CLOUD_API_KEY>" \
  --from-literal=logs-username="<YOUR_LOGS_USERNAME>" \
  --from-literal=logs-password="<YOUR_GRAFANA_CLOUD_API_KEY>"

# Install Grafana Agent via Helm
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

cat > grafana-agent-values.yaml << 'EOF'
agent:
  mode: 'flow'
  configMap:
    create: true
    content: |
      // Grafana Agent Flow configuration
      
      // Prometheus metrics collection from K8s
      prometheus.scrape "kubernetes_pods" {
        targets    = discovery.kubernetes.pods.targets
        forward_to = [prometheus.remote_write.grafana_cloud.receiver]
      }
      
      discovery.kubernetes "pods" {
        role = "pod"
      }
      
      // Remote write to Grafana Cloud
      prometheus.remote_write "grafana_cloud" {
        endpoint {
          url = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
          basic_auth {
            username = env("METRICS_USERNAME")
            password = env("METRICS_PASSWORD")
          }
        }
      }
EOF

helm install grafana-agent grafana/grafana-agent \
  --namespace grafana-agent \
  --values grafana-agent-values.yaml
```

### Option B: Azure Managed Grafana

```bash
# Create Azure Managed Grafana instance
az grafana create \
  --name devops-grafana \
  --resource-group devops-rg \
  --location eastus \
  --sku Standard

# Get the Grafana endpoint
az grafana show \
  --name devops-grafana \
  --resource-group devops-rg \
  --query "properties.endpoint" -o tsv
# https://devops-grafana-abc123.eus.grafana.azure.com

# Add Azure Monitor as data source (automatic for Azure Managed Grafana)
az grafana data-source create \
  --name devops-grafana \
  --resource-group devops-rg \
  --definition '{
    "name": "Azure Monitor",
    "type": "grafana-azure-monitor-datasource",
    "access": "proxy",
    "jsonData": {
      "subscriptionId": "<YOUR_SUBSCRIPTION_ID>"
    }
  }'

# Assign Grafana Admin role to a user
az grafana assign-role \
  --name devops-grafana \
  --resource-group devops-rg \
  --role Admin \
  --assignee user@company.com
```

---

## 4. Configuration Deep Dive

### 4.1 datasource.yaml for Multiple Sources

```yaml
# /etc/grafana/provisioning/datasources/datasources.yaml
# This file is loaded automatically by Grafana on startup

apiVersion: 1

deleteDatasources:
  - name: OldDatasource
    orgId: 1

datasources:
  # ── Prometheus datasource ─────────────────────────────────────────────
  - name: Prometheus                                          # ← GRAFANA: display name shown in UI
    type: prometheus                                          # ← GRAFANA: must be exactly "prometheus"
    access: proxy
    url: http://prometheus-stack-kube-prom-prometheus:9090    # ← GRAFANA: Prometheus service URL inside cluster
    isDefault: true                                           # ← GRAFANA: makes this the default datasource
    editable: false
    uid: prometheus                                           # ← GRAFANA: fixed UID used by dashboards to reference this source
    jsonData:
      timeInterval: "15s"                                     # ← GRAFANA: must match Prometheus scrape_interval
      queryTimeout: "60s"
      httpMethod: POST
      manageAlerts: true
      prometheusType: Prometheus
      prometheusVersion: "2.47.0"
      incrementalQuerying: true
      exemplarTraceIdDestinations:                            # ← GRAFANA+JAEGER: links Prometheus exemplars to Jaeger traces
        - name: traceID
          datasourceUid: jaeger                               # ← GRAFANA: must match the uid of the Jaeger datasource below
          urlDisplayLabel: "View trace"

  # ── Elasticsearch datasource ──────────────────────────────────────────
  - name: Elasticsearch                                       # ← GRAFANA: display name shown in UI
    type: elasticsearch                                       # ← GRAFANA: must be exactly "elasticsearch"
    access: proxy
    url: http://elasticsearch-es-http.elastic.svc.cluster.local:9200  # ← GRAFANA: Elasticsearch service URL
    uid: elasticsearch                                        # ← GRAFANA: fixed UID used by dashboards
    editable: false
    jsonData:
      index: "logstash-*"                                     # ← GRAFANA: index pattern to query
      timeField: "@timestamp"                                 # ← GRAFANA: field used for time filtering
      esVersion: "8.0.0"
      maxConcurrentShardRequests: 5
      logLevelField: "level"
      logMessageField: "message"
      includeFrozen: false
    # For secured Elasticsearch:
    # secureJsonData:
    #   basicAuthPassword: "elastic-password"
    # basicAuth: true
    # basicAuthUser: elastic

  # ── Jaeger datasource ─────────────────────────────────────────────────
  - name: Jaeger                                              # ← GRAFANA: display name shown in UI
    type: jaeger                                              # ← GRAFANA: must be exactly "jaeger"
    access: proxy
    url: http://jaeger-query.tracing.svc.cluster.local:16686  # ← GRAFANA: Jaeger query service URL
    uid: jaeger                                               # ← GRAFANA: fixed UID — must match what Prometheus datasource references
    editable: false
    jsonData:
      tracesToLogsV2:
        datasourceUid: elasticsearch                          # ← GRAFANA: links traces to logs in Elasticsearch
        filterByTraceID: true
        filterBySpanID: false
        tags:
          - key: "k8s.pod.name"
            value: "kubernetes_pod_name"
      tracesToMetrics:
        datasourceUid: prometheus                             # ← GRAFANA: links traces back to Prometheus metrics
        tags:
          - key: "service.name"
            value: "job"
      serviceMap:
        datasourceUid: prometheus
      nodeGraph:
        enabled: true

  # ── Loki datasource ────────────────────────────────────────────────────────
  - name: Loki                                                # ← GRAFANA: display name shown in UI
    type: loki                                                # ← GRAFANA: must be exactly "loki"
    access: proxy
    url: http://loki-gateway.monitoring.svc.cluster.local:80  # ← GRAFANA: Loki service URL inside cluster
    uid: loki                                                 # ← GRAFANA: fixed UID — must match what Jaeger datasource references
    editable: false
    jsonData:
      derivedFields:
        - datasourceUid: jaeger                               # ← GRAFANA: links log lines to Jaeger traces
          matcherRegex: "traceID=(\\w+)"                      # ← GRAFANA: regex to extract trace ID from log lines
          name: TraceID
          url: "$${__value.raw}"
          urlDisplayLabel: "View Trace in Jaeger"
      maxLines: 1000
```

**What DevOps MUST configure for Grafana datasources — the mandatory lines (out of the full YAML above):**

| Line | Datasource | Why it is needed |
|---|---|---|
| `type: prometheus` | Prometheus | Tells Grafana which plugin to use — must match exactly |
| `url: http://prometheus-stack-...:9090` | Prometheus | Where Grafana sends PromQL queries |
| `isDefault: true` | Prometheus | Makes this the pre-selected datasource in dashboards |
| `uid: prometheus` | Prometheus | Stable ID referenced by all dashboard JSON files |
| `timeInterval: "15s"` | Prometheus | Must match your Prometheus scrape interval or graphs show gaps |
| `exemplarTraceIdDestinations.datasourceUid: jaeger` | Prometheus | Links Prometheus metric exemplars to Jaeger traces |
| `type: elasticsearch` | Elasticsearch | Plugin type — must match exactly |
| `index: "logstash-*"` | Elasticsearch | Index pattern to search logs in |
| `timeField: "@timestamp"` | Elasticsearch | Field used for time-range filtering |
| `type: jaeger` | Jaeger | Plugin type — must match exactly |
| `url: http://jaeger-query...:16686` | Jaeger | Where Grafana fetches trace data from |
| `uid: jaeger` | Jaeger | Must match the `datasourceUid: jaeger` reference in Prometheus and Loki configs |
| `matcherRegex: "traceID=(\\w+)"` | Loki | Pattern that extracts a trace ID from a log line — enables "jump to trace" from logs |

Everything else (editable, maxLines, httpMethod) is tuning — not required for the tool to work.

```json
{
  "__inputs": [
    {
      "name": "DS_PROMETHEUS",
      "label": "Prometheus",
      "type": "datasource",
      "pluginId": "prometheus"
    }
  ],
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": { "type": "grafana", "uid": "-- Grafana --" },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      },
      {
        "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
        "enable": true,
        "expr": "changes(kube_deployment_status_replicas_updated[2m]) > 0",
        "iconColor": "blue",
        "name": "Deployments",
        "step": "60s",
        "titleFormat": "Deployment: {{deployment}}"
      }
    ]
  },
  "description": "Kubernetes cluster overview dashboard",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "collapsed": false,
      "gridPos": { "h": 1, "w": 24, "x": 0, "y": 0 },
      "id": 1,
      "title": "Cluster Overview",
      "type": "row"
    },
    {
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "fieldConfig": {
        "defaults": {
          "color": { "mode": "thresholds" },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 80 },
              { "color": "red", "value": 90 }
            ]
          },
          "unit": "percent",
          "mappings": []
        }
      },
      "gridPos": { "h": 4, "w": 4, "x": 0, "y": 1 },
      "id": 2,
      "options": {
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "orientation": "auto",
        "textMode": "auto",
        "colorMode": "background"
      },
      "pluginVersion": "10.2.0",
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
          "expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))) * 100",
          "legendFormat": "CPU Usage",
          "refId": "A"
        }
      ],
      "title": "Cluster CPU Usage",
      "type": "stat"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["kubernetes", "cluster"],
  "templating": {
    "list": [
      {
        "current": {},
        "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
        "definition": "label_values(kube_namespace_labels, namespace)",
        "hide": 0,
        "includeAll": true,
        "label": "Namespace",
        "multi": true,
        "name": "namespace",
        "options": [],
        "query": {
          "query": "label_values(kube_namespace_labels, namespace)",
          "refId": "StandardVariableQuery"
        },
        "refresh": 2,
        "regex": "",
        "sort": 1,
        "type": "query"
      },
      {
        "current": {},
        "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
        "definition": "label_values(kube_pod_info{namespace=~\"$namespace\"}, pod)",
        "hide": 0,
        "includeAll": true,
        "label": "Pod",
        "multi": true,
        "name": "pod",
        "options": [],
        "query": "label_values(kube_pod_info{namespace=~\"$namespace\"}, pod)",
        "refresh": 2,
        "type": "query"
      }
    ]
  },
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "Kubernetes Cluster Overview",
  "uid": "k8s-cluster-overview",
  "version": 1
}
```

### 4.3 Alerting Rules and Notification Channels

```yaml
# grafana-alert-provisioning.yaml
# Place in /etc/grafana/provisioning/alerting/

apiVersion: 1

# Contact points (where to send alerts)
contactPoints:
  - orgId: 1
    name: slack-ops-team
    receivers:
      - uid: slack-ops-team
        type: slack
        settings:
          url: "${SLACK_WEBHOOK_URL}"
          channel: "#alerts-grafana"
          username: "Grafana Alerting"
          iconEmoji: ":grafana:"
          title: |
            [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ len .Alerts.Firing }}{{ end }}]
            {{ .CommonLabels.alertname }}
          text: |
            {{ range .Alerts -}}
            **Alert:** {{ .Annotations.summary }}
            **Description:** {{ .Annotations.description }}
            **Severity:** {{ .Labels.severity }}
            {{ end }}
          color: |
            {{ if eq .Status "firing" -}}
              {{ if eq .CommonLabels.severity "critical" -}}danger{{- else -}}warning{{- end -}}
            {{- else -}}good{{- end }}
        disableResolveMessage: false

  - orgId: 1
    name: teams-devops
    receivers:
      - uid: teams-devops
        type: teams
        settings:
          url: "${TEAMS_WEBHOOK_URL}"
          title: "Grafana Alert: {{ .CommonLabels.alertname }}"
          message: |
            **Status:** {{ .Status }}
            {{ range .Alerts }}
            **Summary:** {{ .Annotations.summary }}
            {{ end }}

  - orgId: 1
    name: pagerduty-critical
    receivers:
      - uid: pagerduty-critical
        type: pagerduty
        settings:
          integrationKey: "${PAGERDUTY_INTEGRATION_KEY}"
          severity: critical
          class: "{{ .CommonLabels.alertname }}"
          component: kubernetes
          group: "{{ .CommonLabels.namespace }}"

# Notification policies - routing tree
policies:
  - orgId: 1
    receiver: slack-ops-team        # Default receiver
    group_by:
      - alertname
      - cluster
      - namespace
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      - receiver: pagerduty-critical
        matchers:
          - severity =~ "critical"
        group_wait: 0s
        repeat_interval: 1h
      - receiver: teams-devops
        matchers:
          - team = "devops"

# Mute timings
muteTimes:
  - orgId: 1
    name: maintenance-window
    time_intervals:
      - times:
          - start_time: "02:00"
            end_time: "04:00"
        weekdays:
          - sunday

# Alert rules
groups:
  - orgId: 1
    name: kubernetes-health
    folder: Kubernetes Alerts
    interval: 1m
    rules:
      - uid: k8s-pod-crash-loop
        title: Pod CrashLoopBackOff
        condition: A
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A
        for: 2m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is CrashLoopBackOff"
          description: "Container {{ $labels.container }} has been in CrashLoopBackOff for 2 minutes."
        noDataState: OK
        execErrState: Error
        isPaused: false
        notificationSettings:
          receiver: pagerduty-critical

      - uid: k8s-high-memory
        title: High Memory Usage
        condition: B
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
              refId: A
          - refId: B
            datasourceUid: __expr__
            model:
              conditions:
                - evaluator:
                    params: [85]
                    type: gt
                  operator:
                    type: and
                  query:
                    params: [A]
                  reducer:
                    type: last
              type: classic_conditions
              refId: B
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage: {{ humanizePercentage $values.A.Value }}"
```

### 4.4 RBAC and User Management

```yaml
# grafana-rbac.yaml
# Grafana supports three built-in org roles: Admin, Editor, Viewer
# Grafana Enterprise adds fine-grained RBAC

# provisioning/access-control/rbac.yaml (Enterprise only)
apiVersion: 1
roles:
  - name: custom:kubernetes:viewer
    description: "Read-only access to Kubernetes dashboards"
    version: 1
    orgId: 1
    permissions:
      - action: dashboards:read
        scope: folders:name:Kubernetes
      - action: datasources:read
        scope: datasources:name:Prometheus
      - action: datasources:query
        scope: datasources:name:Prometheus

  - name: custom:devops:editor
    description: "Edit dashboards and alerts for DevOps team"
    version: 1
    orgId: 1
    permissions:
      - action: dashboards:read
        scope: folders:*
      - action: dashboards:write
        scope: folders:name:DevOps
      - action: alert.rules:read
        scope: folders:*
      - action: alert.rules:write
        scope: folders:name:DevOps
```

```bash
# User management via Grafana CLI
# Create user
grafana-cli admin create-admin-user \
  --email admin@company.com \
  --login admin2 \
  --password "SecurePass123!"

# Manage via API
# Create user
curl -X POST http://admin:admin123@localhost:3000/api/admin/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "DevOps Engineer",
    "email": "devops@company.com",
    "login": "devops",
    "password": "devops123",
    "OrgId": 1,
    "role": "Editor"
  }'

# Update user role in organization
curl -X PATCH http://admin:admin123@localhost:3000/api/org/users/2 \
  -H "Content-Type: application/json" \
  -d '{"role": "Editor"}'

# Add user to team
curl -X POST http://admin:admin123@localhost:3000/api/teams/1/members \
  -H "Content-Type: application/json" \
  -d '{"userId": 2}'
```

### 4.5 Provisioning Dashboards as Code

```yaml
# /etc/grafana/provisioning/dashboards/provider.yaml

apiVersion: 1
providers:
  # Load dashboards from filesystem
  - name: kubernetes-dashboards
    orgId: 1
    folder: "Kubernetes"
    folderUid: kubernetes
    type: file
    disableDeletion: false       # Allow deletion from UI
    updateIntervalSeconds: 30    # Check for file changes every 30s
    allowUiUpdates: false        # Prevent UI changes (enforce GitOps)
    options:
      path: /var/lib/grafana/dashboards/kubernetes
      foldersFromFilesStructure: true  # Use subdirectory names as folder names

  - name: application-dashboards
    orgId: 1
    folder: "Applications"
    type: file
    options:
      path: /var/lib/grafana/dashboards/applications

  # Load dashboards from ConfigMap (for Kubernetes deployments)
  - name: configmap-dashboards
    orgId: 1
    folder: "Operations"
    type: file
    options:
      path: /tmp/dashboards
```

```bash
# Kubernetes ConfigMap for dashboard provisioning
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
  labels:
    grafana_dashboard: "1"    # Label that Grafana's sidecar container watches
data:
  kubernetes-overview.json: |
    {
      "title": "Kubernetes Overview",
      "uid": "k8s-overview",
      "tags": ["kubernetes"],
      "panels": [],
      "time": {"from": "now-1h", "to": "now"},
      "refresh": "30s"
    }
EOF
```

---

## 5. Integration with Existing Tools

### 5.1 Prometheus: Primary Data Source + K8s Dashboards

```bash
# Verify Prometheus datasource is connected
curl -s http://admin:admin123@localhost:3000/api/datasources | \
  python3 -c "
import json, sys
sources = json.load(sys.stdin)
for s in sources:
    print(f\"{s['name']}: {s['type']} - {s['url']}\")
"

# Test a Prometheus query through Grafana
curl -s "http://admin:admin123@localhost:3000/api/datasources/proxy/1/api/v1/query" \
  --data-urlencode 'query=up' | python3 -m json.tool | head -20
```

### 5.2 Kubernetes: Import Community Dashboards

```bash
# Import dashboard via API

# Dashboard ID 315: Kubernetes cluster monitoring (via Prometheus)
curl -X POST http://admin:admin123@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [{"name": "DS_PROMETHEUS", "type": "datasource", "pluginId": "prometheus", "value": "Prometheus"}],
    "folderId": 0,
    "overwrite": true,
    "dashboard": {"id": null}
  }'

# Better approach: Use Grafana CLI or the UI
# In Grafana UI: + > Import > Enter dashboard ID

# Popular Kubernetes dashboard IDs:
# 315   - Kubernetes cluster monitoring (original)
# 6417  - Kubernetes Resource Requests
# 13770 - K8s / Compute Resources / Namespace (Pods)
# 1860  - Node Exporter Full
# 7249  - Kubernetes Cluster
# 8685  - Kubernetes Deployment Statefulset Daemonset
# 11074 - Node Exporter for Prometheus Dashboard
# 14518 - CoreDNS

# Import multiple dashboards via Helm values (using kube-prometheus-stack):
cat >> prometheus-values.yaml << 'EOF'
grafana:
  dashboards:
    default:
      node-exporter:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6781
        revision: 1
        datasource: Prometheus
      kubernetes-resources:
        gnetId: 6417
        revision: 1
        datasource: Prometheus
EOF

helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --reuse-values
```

### 5.3 ELK: Elasticsearch Data Source for Log Correlation

```bash
# Add Elasticsearch datasource via API
curl -X POST http://admin:admin123@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Elasticsearch",
    "type": "elasticsearch",
    "access": "proxy",
    "url": "http://elasticsearch-es-http.elastic.svc.cluster.local:9200",
    "database": "logstash-*",
    "jsonData": {
      "esVersion": "8.0.0",
      "timeField": "@timestamp",
      "interval": "Daily",
      "maxConcurrentShardRequests": 5,
      "logLevelField": "level",
      "logMessageField": "message"
    }
  }'
```

### 5.4 Jaeger: Trace Visualization

```bash
# Add Jaeger datasource
curl -X POST http://admin:admin123@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Jaeger",
    "type": "jaeger",
    "access": "proxy",
    "url": "http://jaeger-query.tracing.svc.cluster.local:16686",
    "jsonData": {
      "tracesToLogsV2": {
        "datasourceUid": "elasticsearch",
        "filterByTraceID": true
      },
      "tracesToMetrics": {
        "datasourceUid": "prometheus"
      },
      "nodeGraph": {
        "enabled": true
      }
    }
  }'
```

### 5.5 Jenkins: Build Metrics Dashboard

```bash
# Create Grafana dashboard for Jenkins metrics
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-jenkins-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  jenkins.json: |
    {
      "title": "Jenkins CI/CD Metrics",
      "uid": "jenkins-metrics",
      "tags": ["jenkins", "ci/cd"],
      "panels": [
        {
          "title": "Build Success Rate",
          "type": "gauge",
          "targets": [
            {
              "expr": "rate(default_jenkins_builds_success_build_count_total[1h]) / rate(default_jenkins_builds_count_total[1h]) * 100",
              "legendFormat": "Success Rate"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "percent",
              "thresholds": {
                "steps": [
                  {"color": "red", "value": 0},
                  {"color": "yellow", "value": 70},
                  {"color": "green", "value": 90}
                ]
              }
            }
          },
          "gridPos": {"h": 6, "w": 4, "x": 0, "y": 0}
        },
        {
          "title": "Build Duration Over Time",
          "type": "timeseries",
          "targets": [
            {
              "expr": "default_jenkins_builds_duration_milliseconds_summary{quantile=\"0.5\"} / 1000",
              "legendFormat": "P50 Duration (s)"
            },
            {
              "expr": "default_jenkins_builds_duration_milliseconds_summary{quantile=\"0.95\"} / 1000",
              "legendFormat": "P95 Duration (s)"
            }
          ],
          "gridPos": {"h": 6, "w": 10, "x": 4, "y": 0}
        }
      ],
      "time": {"from": "now-24h", "to": "now"},
      "refresh": "5m"
    }
EOF
```

### 5.6 JFrog: Artifact Metrics

```bash
# Create JFrog metrics dashboard
cat > jfrog-dashboard.json << 'EOF'
{
  "title": "JFrog Artifactory Metrics",
  "uid": "jfrog-metrics",
  "panels": [
    {
      "title": "Artifact Downloads",
      "type": "timeseries",
      "targets": [
        {
          "expr": "rate(jfrog_rt_artifacts_count[5m])",
          "legendFormat": "Downloads/sec"
        }
      ]
    },
    {
      "title": "Storage Usage",
      "type": "gauge",
      "targets": [
        {
          "expr": "jfrog_rt_data_upload_total_bytes / (1024*1024*1024)",
          "legendFormat": "Storage (GB)"
        }
      ]
    }
  ]
}
EOF

# Import via API
curl -X POST http://admin:admin123@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat jfrog-dashboard.json), \"overwrite\": true, \"folderId\": 0}"
```

### 5.7 Slack and Teams Alert Notifications

```bash
# Configure Slack notification channel via API
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Slack DevOps",
    "type": "slack",
    "settings": {
      "url": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
      "channel": "#devops-alerts",
      "username": "Grafana",
      "icon_emoji": ":grafana:",
      "title": "{{ template \"slack.default.title\" . }}",
      "text": "{{ template \"slack.default.message\" . }}"
    }
  }'

# Configure Microsoft Teams
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Teams Platform",
    "type": "teams",
    "settings": {
      "url": "https://outlook.office.com/webhook/YOUR/TEAMS/WEBHOOK"
    }
  }'

# Test notification
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points/test \
  -H "Content-Type: application/json" \
  -d '{"name": "Slack DevOps"}'
```

---

## 6. Real-World Scenarios

### Scenario 1: Build a K8s Cluster Overview Dashboard

**Goal:** Create a single-pane-of-glass dashboard for the Kubernetes operations team.

```bash
# Step 1: Import the Node Exporter Full dashboard (ID: 1860)
# In Grafana UI: Dashboards > Import > ID: 1860 > Load > Select Prometheus datasource > Import

# Step 2: Import Kubernetes cluster monitoring (ID: 315)
# Dashboards > Import > ID: 315 > Load > Import

# Step 3: Create a custom overview dashboard via API
curl -X POST http://admin:admin123@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "K8s Cluster Health",
      "uid": "k8s-health",
      "tags": ["kubernetes", "ops"],
      "timezone": "browser",
      "refresh": "30s",
      "time": {"from": "now-3h", "to": "now"},
      "panels": [
        {
          "id": 1, "type": "stat",
          "title": "Cluster CPU %",
          "gridPos": {"h": 4, "w": 4, "x": 0, "y": 0},
          "targets": [{"expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))) * 100", "refId": "A"}],
          "fieldConfig": {"defaults": {"unit": "percent", "thresholds": {"steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 85}]}}}
        },
        {
          "id": 2, "type": "stat",
          "title": "Cluster Memory %",
          "gridPos": {"h": 4, "w": 4, "x": 4, "y": 0},
          "targets": [{"expr": "(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100", "refId": "A"}],
          "fieldConfig": {"defaults": {"unit": "percent", "thresholds": {"steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 75}, {"color": "red", "value": 90}]}}}
        },
        {
          "id": 3, "type": "stat",
          "title": "Running Pods",
          "gridPos": {"h": 4, "w": 4, "x": 8, "y": 0},
          "targets": [{"expr": "sum(kube_pod_status_phase{phase=\"Running\"})", "refId": "A"}],
          "fieldConfig": {"defaults": {"thresholds": {"steps": [{"color": "green", "value": null}]}}}
        },
        {
          "id": 4, "type": "stat",
          "title": "Failed Pods",
          "gridPos": {"h": 4, "w": 4, "x": 12, "y": 0},
          "targets": [{"expr": "sum(kube_pod_status_phase{phase=\"Failed\"})", "refId": "A"}],
          "fieldConfig": {"defaults": {"thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "red", "value": 1}]}}}
        }
      ]
    },
    "overwrite": true,
    "folderId": 0
  }'
```

### Scenario 2: Create a Custom Application Performance Dashboard

**Goal:** Track business-level SLIs (Service Level Indicators) for a microservices application.

```bash
# Deploy sample app with custom metrics
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  app-sli.json: |
    {
      "title": "Application SLI Dashboard",
      "uid": "app-sli",
      "tags": ["sli", "application"],
      "templating": {
        "list": [
          {
            "name": "service",
            "type": "query",
            "datasource": "Prometheus",
            "definition": "label_values(http_requests_total, job)",
            "refresh": 2
          }
        ]
      },
      "panels": [
        {
          "title": "Request Rate (RPS)",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"$service\"}[5m])) by (status_code)",
              "legendFormat": "Status {{ status_code }}"
            }
          ],
          "fieldConfig": {
            "defaults": {"unit": "reqps"},
            "overrides": [
              {"matcher": {"id": "byRegexp", "options": "5.*"}, "properties": [{"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}}]},
              {"matcher": {"id": "byRegexp", "options": "2.*"}, "properties": [{"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}}]}
            ]
          }
        },
        {
          "title": "P99 Latency",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "targets": [
            {
              "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job=\"$service\"}[5m])) by (le))",
              "legendFormat": "P99"
            },
            {
              "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job=\"$service\"}[5m])) by (le))",
              "legendFormat": "P95"
            },
            {
              "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{job=\"$service\"}[5m])) by (le))",
              "legendFormat": "P50"
            }
          ],
          "fieldConfig": {"defaults": {"unit": "s"}}
        },
        {
          "title": "Error Rate",
          "type": "gauge",
          "gridPos": {"h": 6, "w": 6, "x": 0, "y": 8},
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"$service\", status_code=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"$service\"}[5m])) * 100",
              "legendFormat": "Error %"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "percent",
              "thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "yellow", "value": 1}, {"color": "red", "value": 5}]}
            }
          }
        }
      ],
      "time": {"from": "now-1h", "to": "now"},
      "refresh": "15s"
    }
EOF
```

### Scenario 3: Setup Alerts for SLA Breach

**Goal:** Alert when error rate exceeds SLA threshold or latency P99 exceeds SLO.

```bash
# Create SLA breach alerts via Grafana API
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/alert-rules \
  -H "Content-Type: application/json" \
  -d '{
    "title": "SLA: Error Rate Breach",
    "ruleGroup": "sla-alerts",
    "folderUID": "sla",
    "condition": "B",
    "data": [
      {
        "refId": "A",
        "datasourceUid": "prometheus",
        "model": {
          "expr": "sum(rate(http_requests_total{status_code=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m])) * 100",
          "intervalMs": 1000,
          "maxDataPoints": 43200,
          "refId": "A"
        }
      },
      {
        "refId": "B",
        "datasourceUid": "__expr__",
        "model": {
          "conditions": [{"evaluator": {"params": [1], "type": "gt"}, "query": {"params": ["A"]}, "reducer": {"type": "last"}, "operator": {"type": "and"}}],
          "type": "classic_conditions",
          "refId": "B"
        }
      }
    ],
    "for": "5m",
    "labels": {"severity": "critical", "sla": "breach"},
    "annotations": {
      "summary": "SLA breach: error rate above 1%",
      "description": "Current error rate: {{ $values.A.Value }}%"
    }
  }'

# Create SLO latency alert
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/alert-rules \
  -H "Content-Type: application/json" \
  -d '{
    "title": "SLO: P99 Latency Breach",
    "ruleGroup": "sla-alerts",
    "folderUID": "sla",
    "condition": "B",
    "data": [
      {
        "refId": "A",
        "datasourceUid": "prometheus",
        "model": {
          "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 0.5",
          "refId": "A"
        }
      },
      {
        "refId": "B",
        "datasourceUid": "__expr__",
        "model": {
          "conditions": [{"evaluator": {"params": [0], "type": "gt"}, "query": {"params": ["A"]}, "reducer": {"type": "last"}, "operator": {"type": "and"}}],
          "type": "classic_conditions",
          "refId": "B"
        }
      }
    ],
    "for": "5m",
    "labels": {"severity": "warning", "slo": "latency"},
    "annotations": {
      "summary": "P99 latency exceeds 500ms SLO",
      "description": "P99 latency is {{ $values.A.Value }}s, which exceeds 500ms SLO threshold."
    }
  }'
```

---

## 7. Verification & Testing

### Verify Grafana is Running

```bash
# Check pod status
kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana
# NAME                                      READY   STATUS    RESTARTS   AGE
# prometheus-stack-grafana-5d4c9b8b7f-x9vkj 3/3     Running   0          1h

# Check Grafana health endpoint
curl -s http://localhost:3000/api/health | python3 -m json.tool
# {
#   "commit": "abc12345",
#   "database": "ok",
#   "version": "10.2.0"
# }

# Verify datasources
curl -s http://admin:admin123@localhost:3000/api/datasources | \
  python3 -c "
import json, sys
for s in json.load(sys.stdin):
    print(f\"{s['name']}: {s['type']} ({s['url']})\")
"

# Test Prometheus datasource
curl -s "http://admin:admin123@localhost:3000/api/datasources/1/health" | python3 -m json.tool

# List all dashboards
curl -s "http://admin:admin123@localhost:3000/api/search?type=dash-db" | \
  python3 -c "
import json, sys
for d in json.load(sys.stdin):
    print(f\"{d['uid']}: {d['title']}\")
"
```

### Verify Alerting Works

```bash
# List configured contact points
curl -s http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points | \
  python3 -m json.tool

# List active alert rules
curl -s http://admin:admin123@localhost:3000/api/v1/provisioning/alert-rules | \
  python3 -c "
import json, sys
for r in json.load(sys.stdin):
    print(f\"{r['title']}: {r['ruleGroup']}\")
"

# Send a test notification
curl -X POST http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points/test \
  -H "Content-Type: application/json" \
  -d '{"name": "Slack DevOps"}'
```

### Performance Testing

```bash
# Generate load to test dashboard metrics
kubectl run load-generator \
  --image=busybox \
  --restart=Never \
  -- sh -c "while true; do wget -O- http://myapp:8080/api/data; sleep 0.1; done"

# Check in Grafana that request rate increases in dashboard
# Navigate to: Application SLI Dashboard > Request Rate panel
```

---

## 8. Troubleshooting Guide

### Issue 1: Cannot Login to Grafana

**Symptoms:** "Invalid username or password" error

**Solution:**
```bash
# Check admin password from secret
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo

# Reset admin password via CLI
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- grafana-cli admin reset-admin-password "newpassword123"
```

### Issue 2: Dashboards Showing "No Data"

**Symptoms:** All panels show "No data" message

**Solution:**
```bash
# Check if datasource connection works
curl -s http://admin:admin123@localhost:3000/api/datasources/proxy/1/api/v1/query?query=up

# Verify the time range - set to "Last 1 hour"
# Check if there's a time zone mismatch

# Debug the specific panel query:
# Panel menu > Edit > Query inspector > Refresh
# Look for errors in the "Response" tab

# Verify Prometheus has data
curl http://localhost:9090/api/v1/query?query=up | python3 -m json.tool
```

### Issue 3: Provisioned Dashboards Not Loading

**Symptoms:** Dashboards added to ConfigMap don't appear in Grafana

**Solution:**
```bash
# Check Grafana sidecar container logs
kubectl logs -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -c grafana-sc-dashboard

# Verify ConfigMap has correct label
kubectl get configmap -n monitoring --show-labels | grep grafana_dashboard

# Check if sidecar is watching correct namespace
kubectl get deployment -n monitoring prometheus-stack-grafana -o yaml | \
  grep -A5 "LABEL_SELECTOR"

# Force dashboard reload
curl -X POST http://admin:admin123@localhost:3000/api/admin/provisioning/dashboards/reload
```

### Issue 4: Alerts Not Firing

**Symptoms:** Conditions are met but no alerts fire or notifications sent

**Solution:**
```bash
# Check alert state in Grafana UI
# Alerting > Alert rules > Check "State" column

# Check alert evaluation history
curl -s "http://admin:admin123@localhost:3000/api/v1/provisioning/alert-rules" | \
  python3 -m json.tool

# Check contact point configuration
curl -s "http://admin:admin123@localhost:3000/api/v1/provisioning/contact-points" | \
  python3 -m json.tool

# Check notification policy
curl -s "http://admin:admin123@localhost:3000/api/v1/provisioning/policies" | \
  python3 -m json.tool

# Verify the alert rule data query returns data
# In UI: Alerting > Alert rules > Edit rule > Preview

# Check Grafana logs for alert errors
kubectl logs -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -c grafana | grep -i "alert"
```

### Issue 5: Grafana OOMKilled

**Symptoms:** Grafana pod crashes with OOMKilled status

**Solution:**
```bash
# Increase memory limits in Helm values
cat >> grafana-values.yaml << 'EOF'
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 1Gi
    cpu: 500m
EOF

helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --reuse-values

# Find and fix dashboard queries causing high memory
# Check for queries with very large time ranges or no label filters
```

### Issue 6: Slow Dashboard Loading

**Symptoms:** Dashboards take >10 seconds to load

**Solution:**
```bash
# Enable query caching in grafana.ini
# Add to grafana values:
cat >> grafana-values.yaml << 'EOF'
grafana.ini:
  caching:
    enabled: true
    ttl: 1m
  database:
    cache_mode: "shared"
    conn_max_lifetime: 14400
EOF

# Optimize expensive queries - use recording rules in Prometheus
# Bad: sum(rate(container_cpu_usage_seconds_total[5m])) by (pod, namespace)
# Good: Use pre-computed recording rule: job:container_cpu_usage:rate5m

# Check for N+1 query problems in dashboards
# Each panel should query once, not once per row/metric
```

### Issue 7: Datasource "Bad Gateway" Error

**Symptoms:** 502 Bad Gateway when testing datasource

**Solution:**
```bash
# Test connectivity from Grafana pod
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- wget -O- http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090/-/ready

# Check service DNS
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- nslookup prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local

# Check NetworkPolicy
kubectl get networkpolicy -n monitoring
```

### Issue 8: Cannot Import Dashboard

**Symptoms:** Dashboard import fails with JSON validation error

**Solution:**
```bash
# Validate JSON
cat dashboard.json | python3 -m json.tool > /dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Common issues:
# 1. datasource UID mismatch - ensure datasource UID matches your instance
# 2. Panel plugin not installed - check if required visualization plugin exists
# 3. Schema version too new - older Grafana versions can't import newer schemas

# Import with datasource override
curl -X POST http://admin:admin123@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d "{
    \"dashboard\": $(cat dashboard.json),
    \"inputs\": [{\"name\": \"DS_PROMETHEUS\", \"type\": \"datasource\", \"pluginId\": \"prometheus\", \"value\": \"Prometheus\"}],
    \"overwrite\": true
  }"
```

### Issue 9: LDAP/SSO Authentication Issues

**Symptoms:** Users cannot log in via LDAP or SSO

**Solution:**
```bash
# Test LDAP configuration
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- grafana-cli admin user-manager check-ldap-credentials \
  --username testuser \
  --password testpass

# Enable LDAP debug logging
# Add to grafana.ini:
# [log]
# filters = ldap:debug

# Check LDAP config
kubectl get secret -n monitoring grafana-ldap-config -o yaml
```

### Issue 10: Grafana Upgrade Breaking Dashboards

**Symptoms:** After Grafana upgrade, dashboards show errors or panels disappear

**Solution:**
```bash
# Before upgrading, export all dashboards
mkdir -p grafana-backup
curl -s "http://admin:admin123@localhost:3000/api/search?type=dash-db" | \
  python3 -c "
import json, sys, urllib.request
dashboards = json.load(sys.stdin)
for d in dashboards:
    uid = d['uid']
    url = f'http://admin:admin123@localhost:3000/api/dashboards/uid/{uid}'
    with urllib.request.urlopen(url) as response:
        data = json.loads(response.read())
    with open(f'grafana-backup/{uid}.json', 'w') as f:
        json.dump(data, f, indent=2)
    print(f'Exported: {d[\"title\"]}')
"

# After upgrade, check changelog for breaking changes:
# https://grafana.com/docs/grafana/latest/release-notes/

# Restore dashboard if needed
curl -X POST http://admin:admin123@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat grafana-backup/<uid>.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[\"dashboard\"]))'), \"overwrite\": true}"
```

---

## 9. Grafana Cheat Sheet

### API Quick Reference

| Operation | Command |
|-----------|---------|
| List datasources | `curl http://admin:pass@localhost:3000/api/datasources` |
| List dashboards | `curl http://admin:pass@localhost:3000/api/search` |
| Get dashboard | `curl http://admin:pass@localhost:3000/api/dashboards/uid/<uid>` |
| Import dashboard | `POST /api/dashboards/import` |
| Delete dashboard | `DELETE /api/dashboards/uid/<uid>` |
| Create folder | `POST /api/folders` |
| List users | `GET /api/users` |
| Create user | `POST /api/admin/users` |
| Reload datasources | `POST /api/admin/provisioning/datasources/reload` |
| Reload dashboards | `POST /api/admin/provisioning/dashboards/reload` |

### Community Dashboard IDs

| ID    | Dashboard Name                                  | Tags              |
|-------|------------------------------------------------|-------------------|
| 315   | Kubernetes cluster monitoring                   | kubernetes        |
| 1860  | Node Exporter Full                              | node, prometheus  |
| 6417  | Kubernetes Resource Requests                    | kubernetes        |
| 7249  | Kubernetes Cluster                              | kubernetes        |
| 8685  | Kubernetes Deployment Statefulset Daemonset     | kubernetes        |
| 11074 | Node Exporter for Prometheus                    | node              |
| 13770 | K8s / Compute Resources / Namespace (Pods)      | kubernetes        |
| 14518 | CoreDNS                                         | kubernetes, dns   |
| 9965  | ArgoCD                                          | argocd, gitops    |
| 9524  | Jenkins                                         | jenkins, ci       |
| 11099 | Elasticsearch                                   | elasticsearch     |
| 14930 | JFrog Artifactory                               | jfrog             |

### Grafana Keyboard Shortcuts

| Shortcut      | Action                          |
|---------------|---------------------------------|
| `g h`         | Go to home dashboard            |
| `g d`         | Go to dashboard list            |
| `g e`         | Go to explore                   |
| `g a`         | Go to alerting                  |
| `g p`         | Go to profile                   |
| `Ctrl+S`      | Save dashboard (when in edit)   |
| `Ctrl+Z`      | Undo panel edit                 |
| `e`           | Edit panel (when hovering)      |
| `v`           | View panel (when hovering)      |
| `d`           | Duplicate panel (when hovering) |
| `r`           | Remove panel (when hovering)    |
| `Esc`         | Exit edit mode                  |
| `?`           | Show shortcuts help             |

### Dashboard Variable Examples

| Variable Type | Example Definition | Usage |
|--------------|-------------------|-------|
| Query | `label_values(kube_pod_info, namespace)` | `$namespace` |
| Query | `label_values(kube_pod_info{namespace="$namespace"}, pod)` | `$pod` |
| Interval | `1m,5m,10m,30m,1h,6h,12h,24h` | `$interval` |
| Datasource | Type: Prometheus | `$datasource` |
| Custom | `production,staging,development` | `$env` |
| Text box | (user types value) | `$search_term` |

### Common Panel Transformations

| Transformation | Purpose |
|---------------|---------|
| Reduce | Collapse time series to a single value |
| Filter by name | Show only specific fields |
| Rename by regex | Rename series labels |
| Organize fields | Reorder/rename table columns |
| Merge series | Combine multiple queries into one table |
| Calculate field | Add computed column to table |
| Group by | Group and aggregate table data |
| Join by field | SQL-like join of two queries |

### Grafana Variables in Queries

| Variable | Description |
|----------|-------------|
| `$__timeFilter(column)` | SQL time filter for current time range |
| `$__interval` | Auto-calculated step interval |
| `$__rate_interval` | Recommended for `rate()` functions |
| `$__timeFrom()` | Start of current time range (Unix ms) |
| `$__timeTo()` | End of current time range (Unix ms) |
| `$__range` | Duration string of current range |
| `${variable:regex}` | Variable with regex format |
| `${variable:csv}` | Variable as CSV |
| `${variable:pipe}` | Variable pipe-separated |

---

*Last updated: 2024 | Maintained by DevOps Team*
