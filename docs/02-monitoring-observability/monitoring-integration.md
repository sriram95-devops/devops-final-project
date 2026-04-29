# Monitoring Integration Guide: Prometheus + Grafana + ELK + Jaeger

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Flow: Metrics vs Logs vs Traces](#2-data-flow-metrics-vs-logs-vs-traces)
3. [Correlation: Linking Traces to Logs to Metrics](#3-correlation-linking-traces-to-logs-to-metrics)
4. [Unified Alerting Strategy](#4-unified-alerting-strategy)
5. [Dashboard Strategy for K8s Operations](#5-dashboard-strategy-for-k8s-operations)
6. [When to Use Each Tool](#6-when-to-use-each-tool)
7. [End-to-End Deployment Guide](#7-end-to-end-deployment-guide)
8. [Unified Runbooks](#8-unified-runbooks)

---

## 1. Architecture Overview

### The Three Pillars of Observability

Modern observability is built on three pillars — metrics, logs, and traces — each answering a different question about system behavior:

| Pillar   | Tool          | Question Answered                     | Example                                    |
|----------|---------------|---------------------------------------|--------------------------------------------|
| Metrics  | Prometheus    | **What** is wrong? (at a high level)  | "Error rate is 5% on payment service"      |
| Logs     | ELK Stack     | **Why** is it wrong? (detailed events)| "NullPointerException in PaymentService.java:142" |
| Traces   | Jaeger        | **Where** is it wrong? (request path) | "Database query taking 2s on checkout flow" |
| Viz      | Grafana       | Unified view of all three pillars     | Single dashboard with all signals          |

No single tool replaces another. Together, they form a complete observability platform.

### Complete Architecture Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                         KUBERNETES CLUSTER                                      ║
║                                                                                  ║
║  ┌──────────────────────────────────────────────────────────────┐               ║
║  │                  APPLICATION LAYER                           │               ║
║  │                                                              │               ║
║  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │               ║
║  │  │  Frontend   │  │  Backend    │  │  DB Client  │        │               ║
║  │  │  Service    │  │  API        │  │  Service    │        │               ║
║  │  │             │  │             │  │             │        │               ║
║  │  │ [metrics]   │  │ [metrics]   │  │ [metrics]   │        │               ║
║  │  │ [logs]      │  │ [logs]      │  │ [logs]      │        │               ║
║  │  │ [traces]    │  │ [traces]    │  │ [traces]    │        │               ║
║  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │               ║
║  └─────────┼────────────────┼────────────────┼────────────────┘               ║
║            │                │                │                                  ║
║     ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐                        ║
║     │  /metrics   │  │  stdout/    │  │  Trace      │                        ║
║     │  endpoint   │  │  stderr     │  │  Spans      │                        ║
║     └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                        ║
║            │                │                │                                  ║
║  ┌─────────▼────────────────│────────────────│────────────────┐               ║
║  │         COLLECTION LAYER │                │                │               ║
║  │                          │                │                │               ║
║  │  ┌───────────────┐  ┌────▼──────────┐  ┌─▼─────────────┐ │               ║
║  │  │  Prometheus   │  │  Filebeat     │  │ Jaeger Agent  │ │               ║
║  │  │  (scrapes     │  │  DaemonSet    │  │ (or OTel      │ │               ║
║  │  │   /metrics)   │  │  (tails logs) │  │  Collector)   │ │               ║
║  │  └───────┬───────┘  └────┬──────────┘  └─┬─────────────┘ │               ║
║  └──────────┼───────────────┼───────────────┼────────────────┘               ║
║             │               │               │                                  ║
║  ┌──────────▼───────────────▼───────────────▼────────────────┐               ║
║  │                  STORAGE LAYER                             │               ║
║  │                                                            │               ║
║  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │               ║
║  │  │  Prometheus    │  │ Elasticsearch  │  │  Jaeger    │  │               ║
║  │  │  TSDB          │  │  (logs index)  │  │  (ES/mem)  │  │               ║
║  │  │  (metrics)     │  │                │  │  (traces)  │  │               ║
║  │  └────────┬───────┘  └───────┬────────┘  └──────┬─────┘  │               ║
║  └───────────┼──────────────────┼──────────────────┼─────────┘               ║
║              │                  │                  │                           ║
║  ┌───────────▼──────────────────▼──────────────────▼─────────┐               ║
║  │                  VISUALIZATION LAYER                       │               ║
║  │                                                            │               ║
║  │  ┌─────────────────────────────────────────────────────┐  │               ║
║  │  │                    GRAFANA                          │  │               ║
║  │  │   ┌───────────┐  ┌───────────┐  ┌──────────────┐  │  │               ║
║  │  │   │ Metrics   │  │   Logs    │  │   Traces     │  │  │               ║
║  │  │   │ Dashboard │  │  Panel    │  │  Panel       │  │  │               ║
║  │  │   │(Prometheus│  │(Elastic-  │  │  (Jaeger     │  │  │               ║
║  │  │   │ source)   │  │ search)   │  │  source)     │  │  │               ║
║  │  │   └───────────┘  └───────────┘  └──────────────┘  │  │               ║
║  │  └─────────────────────────────────────────────────────┘  │               ║
║  │                                                            │               ║
║  │  ┌────────────────┐      ┌────────────────────────────┐   │               ║
║  │  │  Kibana        │      │  Alertmanager              │   │               ║
║  │  │  (log search)  │      │  (Slack/PagerDuty/Teams)   │   │               ║
║  │  └────────────────┘      └────────────────────────────┘   │               ║
║  └────────────────────────────────────────────────────────────┘               ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

### Component Summary

| Component | Role | Port | Storage |
|-----------|------|------|---------|
| Prometheus | Metric collection & alerting | 9090 | TSDB (local) |
| Alertmanager | Alert routing & notification | 9093 | Memory |
| Grafana | Unified visualization | 3000 | SQLite/PostgreSQL |
| Elasticsearch | Log & trace storage | 9200 | Disk |
| Kibana | Log exploration UI | 5601 | Via Elasticsearch |
| Filebeat | Log collection agent | DaemonSet | N/A |
| Logstash | Log transformation pipeline | 5044 | N/A |
| Jaeger | Distributed tracing | 16686 (UI), 4317 (OTLP) | ES or memory |

---

## 2. Data Flow: Metrics vs Logs vs Traces

### Metrics Data Flow (Prometheus)

```
Application Pod                Prometheus              Grafana
     │                              │                     │
     │  expose /metrics             │                     │
     │──────────────────────────────│                     │
     │                              │                     │
     │            scrape every 15s  │                     │
     │◀─────────────────────────────│                     │
     │                              │                     │
     │  return time-series data     │                     │
     │─────────────────────────────▶│                     │
     │                              │   store in TSDB     │
     │                              │──────────────────   │
     │                              │                     │
     │                              │◀────PromQL query────│
     │                              │─────result──────────▶

Characteristics:
- Pull model (Prometheus initiates)
- 15-second granularity
- Lightweight: numbers only, no text
- Perfect for aggregations, SLIs, alerting
- Retained for days/weeks
```

### Logs Data Flow (ELK)

```
Application Pod    Filebeat (Node)   Elasticsearch      Kibana
     │                  │                 │                 │
     │  write to stdout │                 │                 │
     │──────────────────│                 │                 │
     │                  │                 │                 │
     │     tail log     │                 │                 │
     │     files        │                 │                 │
     │                  │─────bulk────────▶                │
     │                  │     index        │                │
     │                  │                 │◀──KQL query────│
     │                  │                 │──results───────▶

Characteristics:
- Push model (Filebeat pushes)
- Real-time streaming
- High volume: full text, structured JSON
- Perfect for debugging, audit trails
- Retained for 7-90 days
```

### Traces Data Flow (Jaeger)

```
Service A            Service B          Jaeger Collector    Jaeger Query
    │                    │                    │                   │
    │ Start span (req)   │                    │                   │
    │─────────────────────────────────────────│                   │
    │                    │                    │                   │
    │ Propagate trace ID │                    │                   │
    │───────────────────▶│                    │                   │
    │                    │ Start child span   │                   │
    │                    │────────────────────│                   │
    │                    │ End child span     │                   │
    │                    │────────────────────│                   │
    │ End root span      │                    │                   │
    │───────────────────────────────────────▶│                   │
    │                    │                    │   store trace     │
    │                    │                    │───────────────    │
    │                    │                    │                   │
    │                    │                    │◀──trace query─────│
    │                    │                    │───────────────────▶

Characteristics:
- Both push and pull aspects
- Sampled (typically 1-10% of requests)
- Structured: spans with timing and metadata
- Perfect for latency analysis, request flows
- Retained for 2-7 days
```

### Comparison Table

| Attribute        | Metrics (Prometheus)    | Logs (ELK)              | Traces (Jaeger)         |
|------------------|-------------------------|-------------------------|-------------------------|
| Data Type        | Numeric time-series     | Unstructured text/JSON  | Structured span trees   |
| Volume           | Low                     | Very High               | Medium (sampled)        |
| Cardinality      | Medium                  | Unlimited               | Medium                  |
| Real-time        | ~15 seconds             | Near real-time          | Near real-time          |
| Retention        | Days to weeks           | Weeks to months         | Days                    |
| Best For         | Alerting, trends, SLIs  | Debugging, audit        | Latency, request flow   |
| Cost             | Low                     | High (storage)          | Medium                  |
| Query Language   | PromQL                  | KQL / ES DSL            | Native UI / API         |
| Aggregation      | Excellent               | Good                    | Limited                 |

---

## 3. Correlation: Linking Traces to Logs to Metrics

### The Correlation Strategy

The key to effective debugging is correlating across the three pillars. The `trace_id` field acts as the linking key:

```
Prometheus Alert fires:
  payment-service error rate > 5%
        │
        ▼
Grafana shows:
  - Error rate spike started at 14:23:00
  - Specific endpoint: POST /api/checkout
        │
        ▼
ELK Search (time: 14:22-14:25, service: payment-service):
  - Found: "ERROR: Database connection pool exhausted at 14:23:05"
  - trace_id: "abc123def456"
        │
        ▼
Jaeger Trace (trace_id: abc123def456):
  - Shows: API Gateway (50ms) → Payment Service (4500ms!) → Database (timeout)
  - Root cause: database_query "SELECT * FROM orders" taking 4.4 seconds
```

### Implementation: Inject Trace ID into Logs

#### Java/Spring Boot

```java
// application.properties
logging.pattern.console=%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} traceId=%X{traceId} spanId=%X{spanId} - %msg%n

// With OpenTelemetry SDK:
// The traceId is automatically added to MDC (Mapped Diagnostic Context)
// when using otel-javaagent with Logback/Log4j2
```

#### Python / FastAPI

```python
import logging
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Custom logging formatter that injects trace context
class TraceContextFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span()
        if span.is_recording():
            ctx = span.get_span_context()
            record.trace_id = format(ctx.trace_id, '032x')
            record.span_id = format(ctx.span_id, '016x')
        else:
            record.trace_id = '0' * 32
            record.span_id = '0' * 16
        return super().format(record)

# Configure logging
handler = logging.StreamHandler()
handler.setFormatter(TraceContextFormatter(
    '%(asctime)s %(levelname)s %(name)s trace_id=%(trace_id)s span_id=%(span_id)s %(message)s'
))
logging.basicConfig(handlers=[handler], level=logging.INFO)
```

#### Node.js

```javascript
const { trace } = require('@opentelemetry/api');
const winston = require('winston');

const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ timestamp, level, message, ...meta }) => {
      const span = trace.getActiveSpan();
      const traceId = span ? span.spanContext().traceId : '0'.repeat(32);
      const spanId = span ? span.spanContext().spanId : '0'.repeat(16);
      return JSON.stringify({ timestamp, level, message, trace_id: traceId, span_id: spanId, ...meta });
    })
  ),
  transports: [new winston.transports.Console()]
});
```

### Grafana: Linking Metrics to Logs to Traces

> The full annotated datasource configuration YAML (Prometheus exemplar → Jaeger, Jaeger `tracesToLogsV2`, Elasticsearch `derivedFields`) is in:
> **[grafana-complete-guide.md — Section 4.1 Datasource Configuration](grafana-complete-guide.md)**

### Correlation Query Workflow

```bash
# Step 1: Prometheus alerts on high error rate
# Query: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05

# Step 2: Click through to Explore in Grafana, correlate with Elasticsearch logs
# In Grafana Explore split view:
# Left panel: Prometheus
#   rate(http_requests_total{service="payment", status=~"5.."}[5m])
# Right panel: Elasticsearch (auto-linked by service name)
#   kubernetes.labels.app: "payment" AND log.level: error

# Step 3: Find trace_id in log entry, click to open in Jaeger
# The derived field "TraceID" appears as a link in the log entry

# Step 4: Jaeger shows full request timeline
# Identifies slow span: database query in payment-service

# Step 5: Back in Prometheus, query database metrics
# mysql_global_status_slow_queries | pg_stat_statements_total
```

---

## 4. Unified Alerting Strategy

### Alert Tiers

Define clear severity tiers and routing:

```
CRITICAL (immediate response)
  → PagerDuty + Slack #alerts-critical
  → Repeat: every 1 hour
  → Examples:
    - Cluster node down
    - Service completely unavailable (0 replicas)
    - Database connection failure
    - Security breach detected

WARNING (respond within 4 hours)
  → Slack #alerts-warning
  → Repeat: every 4 hours
  → Examples:
    - High CPU/memory (>80%)
    - Error rate spike (>1%)
    - P99 latency degraded (>500ms)
    - Disk space low (>75%)

INFO (review during business hours)
  → Slack #alerts-info
  → Repeat: every 24 hours
  → Examples:
    - Deployment completed
    - Scale-up event
    - Certificate expiring in 30 days
```

### Alert Sources by Tool

```yaml
# Prometheus Alertmanager - infrastructure and application metrics
rules:
  # Infrastructure
  - NodeDown
  - NodeHighCPU
  - NodeHighMemory
  - NodeDiskFull
  - NodeNetworkSaturated
  
  # Kubernetes
  - PodCrashLoopBackOff
  - PodNotReady
  - DeploymentReplicasMismatch
  - PVCPending
  - JobFailed
  
  # Application SLIs
  - HighErrorRate
  - HighLatencyP99
  - LowSuccessRate

# Grafana Alerting - business metrics and composite alerts
rules:
  # SLA/SLO alerts that combine metrics from multiple sources
  - SLABreach
  - ErrorBudgetExhausted
  - CustomerImpactDetected
  
  # Cross-datasource alerts
  - HighErrorLogsWithoutMetricAlert

# Kibana/ELK Watcher - log-based alerts
rules:
  # Security
  - UnauthorizedAccessAttempts
  - PrivilegeEscalationDetected
  - AuditLogAnomaly
  
  # Application
  - ExceptionRateSpike
  - NewErrorPatternDetected
  - ServiceStartupFailure
```

### Alert Deduplication and Grouping

```yaml
# Alertmanager grouping to prevent notification storms
route:
  group_by: [alertname, cluster, namespace]
  group_wait: 30s       # Wait 30s for related alerts to group
  group_interval: 5m    # Wait 5m before sending same group again
  repeat_interval: 4h   # Resend every 4h if still firing

# Inhibition rules - suppress noisy child alerts when parent fires
inhibit_rules:
  # If a node is down, suppress all pod/service alerts on that node
  - source_matchers: [severity="critical", alertname="NodeDown"]
    target_matchers: [severity=~"warning|info"]
    equal: [node]
  
  # If cluster is unreachable, suppress individual service alerts
  - source_matchers: [alertname="ClusterUnreachable"]
    target_matchers: [alertname=~"Pod.*|Deployment.*|Service.*"]
    equal: [cluster]
```

### End-to-End Alert Example: Error Rate Spike

```
1. DETECTION (Prometheus, ~30 seconds after incident)
   Alert: HighErrorRate
   - service: checkout-api
   - error_rate: 8.5%
   - threshold: 5%
   - for: 2m

2. NOTIFICATION (Alertmanager)
   → PagerDuty: "CRITICAL - checkout-api error rate 8.5%"
   → Slack #alerts-critical:
     "🔴 CRITICAL: checkout-api error rate 8.5% (threshold: 5%)
      Namespace: production | Started: 2 minutes ago
      📚 Runbook: https://wiki/runbooks/high-error-rate
      📊 Dashboard: https://grafana/d/checkout-api"

3. INVESTIGATION (automated enrichment)
   Grafana dashboard auto-opens to affected service
   Shows: error spike started at 14:23, correlates with deployment at 14:20

4. ROOT CAUSE (ELK logs, ~2 minutes)
   Kibana search: service=checkout-api AND level=error AND timestamp>14:20
   Found: "NullPointerException: config.paymentGatewayUrl is null"
   trace_id: abc123def456

5. TRACE ANALYSIS (Jaeger, ~1 minute)
   Trace abc123def456:
   - checkout-api: 250ms
     └─ config-service: ERROR (config not found)
   Root cause: config-service deployed without payment gateway URL

6. RESOLUTION
   kubectl rollback deployment checkout-api
   Alert resolves in ~5 minutes
   Slack notification: "✅ RESOLVED - checkout-api error rate back to normal"
```

---

## 5. Dashboard Strategy for K8s Operations Team

### Dashboard Hierarchy

```
Level 1: Executive / SRE Overview
    │
    ├─ Cluster Health (Prometheus + Grafana)
    │   "Are all nodes and namespaces healthy?"
    │
    └─ SLA Dashboard (Prometheus + Grafana)
        "Are we meeting our availability/latency SLAs?"

Level 2: Service Overview
    │
    ├─ Service Health per Namespace (Prometheus + Grafana)
    │   "Which services have issues right now?"
    │
    ├─ Top-N Error Services (ELK + Grafana)
    │   "Which services are generating the most errors?"
    │
    └─ Active Traces (Jaeger UI)
        "What does traffic look like right now?"

Level 3: Deep Dive
    │
    ├─ Per-Service Metrics (Prometheus + Grafana)
    │   RED metrics: Rate, Errors, Duration
    │
    ├─ Per-Service Logs (Kibana / Grafana + ES)
    │   Full-text search, error patterns
    │
    └─ Per-Request Traces (Jaeger)
        Span breakdown, bottleneck identification
```

### Recommended Grafana Dashboards

```bash
# Install all recommended dashboards via Helm values
cat >> prometheus-values.yaml << 'EOF'
grafana:
  dashboards:
    kubernetes:
      # Tier 1: Cluster overview
      cluster-overview:
        gnetId: 315        # K8s cluster monitoring
        datasource: Prometheus
      node-exporter:
        gnetId: 1860       # Node Exporter Full
        datasource: Prometheus
      
      # Tier 2: Workload view
      k8s-resources-cluster:
        gnetId: 13770      # K8s Compute Resources
        datasource: Prometheus
      k8s-resources-namespace:
        gnetId: 6417       # K8s Resource Requests
        datasource: Prometheus
      k8s-deployments:
        gnetId: 8685       # Deployments/StatefulSets
        datasource: Prometheus
      
      # Tier 3: Network
      k8s-networking:
        gnetId: 12206      # K8s Networking
        datasource: Prometheus
      
      # Infrastructure: Node health
      node-disk-usage:
        gnetId: 11074      # Node Exporter
        datasource: Prometheus
EOF
```

### Custom SLI/SLO Dashboard

```json
{
  "title": "SLI/SLO Dashboard",
  "uid": "sli-slo",
  "tags": ["sli", "slo", "production"],
  "panels": [
    {
      "title": "Availability SLO (Target: 99.9%)",
      "type": "gauge",
      "targets": [
        {
          "expr": "(1 - sum(rate(http_requests_total{status=~\"5..\"}[30d])) / sum(rate(http_requests_total[30d]))) * 100",
          "legendFormat": "30-day Availability"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "min": 99,
          "max": 100,
          "thresholds": {
            "steps": [
              {"color": "red", "value": 0},
              {"color": "yellow", "value": 99.5},
              {"color": "green", "value": 99.9}
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
    },
    {
      "title": "Error Budget Remaining",
      "type": "bargauge",
      "targets": [
        {
          "expr": "(1 - (sum(rate(http_requests_total{status=~\"5..\"}[30d])) / sum(rate(http_requests_total[30d])))) / (1 - 0.999) * 100",
          "legendFormat": "Error Budget %"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "thresholds": {
            "steps": [
              {"color": "red", "value": 0},
              {"color": "yellow", "value": 25},
              {"color": "green", "value": 50}
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
    },
    {
      "title": "P99 Latency SLO (Target: <500ms)",
      "type": "timeseries",
      "targets": [
        {
          "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) * 1000",
          "legendFormat": "P99 Latency (ms)"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "ms",
          "custom": {
            "thresholdsStyle": {"mode": "line"}
          },
          "thresholds": {
            "steps": [
              {"color": "green", "value": null},
              {"color": "red", "value": 500}
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    }
  ]
}
```

### Kibana Dashboard for Operations

```bash
# Create Kibana dashboard for K8s operations
curl -X POST "http://localhost:5601/api/saved_objects/dashboard" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "attributes": {
      "title": "K8s Operations Log Overview",
      "description": "Centralized log overview for Kubernetes operations team",
      "panelsJSON": "[]",
      "timeRestore": true,
      "timeFrom": "now-1h",
      "timeTo": "now",
      "refreshInterval": {"pause": false, "value": 30000}
    }
  }'

# Create visualizations to add to the dashboard:
# 1. Error rate over time (line chart)
#    Aggregation: Date histogram, Metric: Count, Filter: log.level: error
#
# 2. Top error messages (data table)  
#    Aggregation: Terms on message.keyword, Metric: Count
#    Filter: log.level: (error OR fatal)
#
# 3. Log volume by namespace (bar chart)
#    Aggregation: Date histogram split by kubernetes.namespace
#
# 4. CrashLoopBackOff events (count)
#    Filter: message: "CrashLoopBackOff"
```

---

## 6. When to Use Each Tool

### Decision Framework

```
SYMPTOM                              → START WITH          → THEN USE
────────────────────────────────────────────────────────────────────
"Service is slow"                    → Prometheus (latency) → Jaeger (find slow span)
"High error rate"                    → Prometheus (rate)   → ELK (find error message)
"Pod keeps crashing"                 → Prometheus (alerts) → ELK (find crash logs)
"Deployment broke something"         → Prometheus (metrics)→ ELK (find error context)
"Random errors, hard to reproduce"   → ELK (search logs)   → Jaeger (find errored traces)
"Database slow"                      → Prometheus (DB metrics)→ Jaeger (query spans)
"Network issue"                      → Prometheus (network)→ ELK (network errors)
"Memory leak"                        → Prometheus (memory growth)→ ELK (GC logs)
"Security incident"                  → ELK (audit logs)    → Prometheus (traffic spike)
"Why is checkout taking 3 seconds?"  → Jaeger (trace)      → Prometheus (service metrics)
"Which service calls which?"         → Jaeger (dependencies)→ Prometheus (call rates)
"How many users affected?"           → Prometheus (request rate)→ ELK (error messages)
```

### Tool Selection Guide

#### Use Prometheus When:
- Setting up **alerts** based on numeric thresholds
- Tracking **SLI/SLO** metrics (availability, latency, error rate)
- Monitoring **infrastructure** (CPU, memory, disk, network)
- Analyzing **trends** over time (capacity planning)
- Checking **deployment impact** on performance metrics
- Monitoring **Kubernetes object state** (pod counts, replication)

```bash
# Prometheus is your first stop for:
# "Is the system healthy right now?"
# "What changed in the last hour?"
# "Are we meeting our SLAs?"

# Quick health check queries:
curl "http://localhost:9090/api/v1/query?query=up" | python3 -m json.tool
curl "http://localhost:9090/api/v1/query?query=ALERTS{alertstate='firing'}" | python3 -m json.tool
```

#### Use ELK When:
- **Debugging** a specific error with full context
- Searching for **patterns** across all services simultaneously
- Performing **security audits** (who accessed what, when)
- Investigating **past incidents** (logs are your audit trail)
- Monitoring **application business logic** events
- Correlating **user actions** to system behavior

```bash
# ELK is your first stop for:
# "Why did this request fail?"
# "What happened between 14:00 and 14:30?"
# "Find all NullPointerExceptions this week"

# Quick ELK searches in Kibana:
# log.level: error AND kubernetes.namespace: production
# message: "connection refused" AND @timestamp > now-1h
# kubernetes.pod.name: "payment-*" AND log.level: (error OR fatal)
```

#### Use Jaeger When:
- Analyzing **request latency** through multiple services
- Finding the **bottleneck** in a multi-service call chain
- Debugging **intermittent failures** that are hard to reproduce
- Understanding **service dependencies** and call patterns
- Optimizing **database query performance** within a request
- Debugging **distributed transactions** (saga pattern, etc.)

```bash
# Jaeger is your first stop for:
# "Which service is making this request slow?"
# "How many hops does checkout go through?"
# "This specific request ID failed - what happened?"

# Jaeger UI searches:
# Service: checkout-api | Operation: POST /checkout | Min Duration: 1s
# Service: payment-api | Tags: error=true | Lookback: 1h
```

#### Use Grafana When:
- Building **dashboards** for any of the above
- Creating **multi-panel** overviews combining metrics, logs, and traces
- Setting up **unified alerting** across multiple data sources
- Sharing observability data with **non-technical stakeholders**
- **Annotating** deployments on metric graphs

---

## 7. End-to-End Deployment Guide

### Deploy All Tools Together

```bash
#!/bin/bash
# deploy-monitoring-stack.sh

set -euo pipefail

NAMESPACE_MONITORING="monitoring"
NAMESPACE_ELASTIC="elastic"
NAMESPACE_TRACING="tracing"

echo "=== Step 1: Create namespaces ==="
kubectl create namespace $NAMESPACE_MONITORING --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $NAMESPACE_ELASTIC --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $NAMESPACE_TRACING --dry-run=client -o yaml | kubectl apply -f -

echo "=== Step 2: Install Prometheus + Grafana (kube-prometheus-stack) ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE_MONITORING \
  --set prometheus.prometheusSpec.retention=7d \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=32000 \
  --wait --timeout 5m

echo "✅ Prometheus + Grafana installed"

echo "=== Step 3: Install ECK Operator + Elasticsearch + Kibana ==="
kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml

kubectl wait --for=condition=Available \
  deployment/elastic-operator \
  -n elastic-system \
  --timeout=120s

kubectl apply -n $NAMESPACE_ELASTIC -f - << 'EOF'
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
spec:
  version: 8.12.0
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false
      podTemplate:
        spec:
          initContainers:
            - name: sysctl
              securityContext:
                privileged: true
                runAsUser: 0
              command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
          containers:
            - name: elasticsearch
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms512m -Xmx512m"
              resources:
                limits:
                  memory: 2Gi
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 10Gi
---
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
spec:
  version: 8.12.0
  count: 1
  elasticsearchRef:
    name: elasticsearch
  http:
    tls:
      selfSignedCertificate:
        disabled: true
EOF

echo "Waiting for Elasticsearch to be ready..."
kubectl wait --for=jsonpath='{.status.health}'=green \
  elasticsearch/elasticsearch \
  -n $NAMESPACE_ELASTIC \
  --timeout=300s

echo "✅ Elasticsearch + Kibana installed"

echo "=== Step 4: Install Jaeger ==="
kubectl apply -n $NAMESPACE_TRACING -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:1.53
          env:
            - name: COLLECTOR_OTLP_ENABLED
              value: "true"
          ports:
            - containerPort: 6831
              protocol: UDP
            - containerPort: 16686
            - containerPort: 4317
            - containerPort: 4318
          resources:
            limits:
              memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
spec:
  selector:
    app: jaeger
  ports:
    - name: ui
      port: 16686
    - name: otlp-grpc
      port: 4317
    - name: otlp-http
      port: 4318
    - name: agent-compact
      port: 6831
      protocol: UDP
EOF

kubectl wait --for=condition=Available \
  deployment/jaeger \
  -n $NAMESPACE_TRACING \
  --timeout=60s

echo "✅ Jaeger installed"

echo "=== Step 5: Configure Grafana datasources ==="
# Wait for Grafana
kubectl wait --for=condition=Available \
  deployment/prometheus-stack-grafana \
  -n $NAMESPACE_MONITORING \
  --timeout=120s

# Port-forward temporarily
kubectl port-forward -n $NAMESPACE_MONITORING \
  svc/prometheus-stack-grafana 3000:80 &
sleep 5

ES_PASSWORD=$(kubectl get secret -n $NAMESPACE_ELASTIC \
  elasticsearch-es-elastic-user \
  -o jsonpath="{.data.elastic}" | base64 --decode)

# Add Elasticsearch datasource
curl -s -X POST http://admin:admin123@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Elasticsearch\",
    \"type\": \"elasticsearch\",
    \"access\": \"proxy\",
    \"url\": \"http://elasticsearch-es-http.elastic.svc.cluster.local:9200\",
    \"database\": \"filebeat-*\",
    \"basicAuth\": true,
    \"basicAuthUser\": \"elastic\",
    \"secureJsonData\": {\"basicAuthPassword\": \"$ES_PASSWORD\"},
    \"jsonData\": {\"esVersion\": \"8.0.0\", \"timeField\": \"@timestamp\", \"logLevelField\": \"log.level\", \"logMessageField\": \"message\"}
  }" > /dev/null

# Add Jaeger datasource
curl -s -X POST http://admin:admin123@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Jaeger",
    "type": "jaeger",
    "access": "proxy",
    "url": "http://jaeger.tracing.svc.cluster.local:16686"
  }' > /dev/null

kill %1 2>/dev/null || true

echo "✅ All datasources configured"

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "Access URLs (run port-forward commands first):"
echo "  Grafana:       kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
echo "                 http://localhost:3000 | admin / admin123"
echo ""
echo "  Prometheus:    kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo "                 http://localhost:9090"
echo ""
echo "  Kibana:        kubectl port-forward -n elastic svc/kibana-kb-http 5601:5601"
echo "                 http://localhost:5601 | elastic / $ES_PASSWORD"
echo ""
echo "  Jaeger:        kubectl port-forward -n tracing svc/jaeger 16686:16686"
echo "                 http://localhost:16686"
```

---

## 8. Unified Runbooks

### Runbook: High Error Rate

```markdown
## Alert: HighErrorRate
**Severity:** Warning/Critical
**Source:** Prometheus

### Step 1: Identify affected service (Prometheus)
Query: `topk(5, rate(http_requests_total{status=~"5.."}[5m]))`
Look at the `job` or `service` label.

### Step 2: Check recent deployments (Prometheus)
Query: `changes(kube_deployment_status_observed_generation[30m]) > 0`
Compare timing with error spike.

### Step 3: Find error root cause (ELK)
Kibana: `kubernetes.labels.app: "<service>" AND log.level: error`
Time: correlate with alert time

### Step 4: Trace a failed request (Jaeger)
Find a trace_id from ELK log entry
Search Jaeger: Service=<affected-service> + Tags: error=true

### Step 5: Resolve
- If deployment related: `kubectl rollout undo deployment/<name>`
- If config related: fix and redeploy
- If infrastructure: escalate to platform team
```

### Runbook: Pod CrashLoopBackOff

```markdown
## Alert: PodCrashLoopBackOff
**Severity:** Critical
**Source:** Prometheus

### Step 1: Identify pod (Prometheus/kubectl)
```bash
kubectl get pods -A | grep CrashLoop
kubectl describe pod <pod-name> -n <namespace>
```

### Step 2: Get crash logs (ELK)
Kibana: `kubernetes.pod.name: "<pod-name>" AND @timestamp > now-30m`
Sort by @timestamp ASC to see startup sequence

### Step 3: Check previous container logs
```bash
kubectl logs <pod-name> -n <namespace> --previous
```

### Step 4: Common causes and fixes
- OOMKilled: increase memory limit
- Config missing: check ConfigMap/Secret exists
- Image pull error: check registry credentials
- Liveness probe failing: check probe configuration
```

---

*Last updated: 2024 | Maintained by DevOps Team*
