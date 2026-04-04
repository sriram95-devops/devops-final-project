# Jaeger Distributed Tracing Guide

## Table of Contents

1. [Overview & Why Jaeger](#1-overview--why-jaeger)
2. [Local Setup on Minikube](#2-local-setup-on-minikube)
3. [Online/Cloud Setup](#3-onlinecloud-setup)
4. [Configuration Deep Dive](#4-configuration-deep-dive)
5. [Integration with Existing Tools](#5-integration-with-existing-tools)
6. [Real-World Scenarios](#6-real-world-scenarios)
7. [Verification & Testing](#7-verification--testing)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [Jaeger Cheat Sheet](#9-jaeger-cheat-sheet)

---

## 1. Overview & Why Jaeger

### What Is Distributed Tracing?

In a microservices architecture, a single user request often flows through dozens of services. When something goes wrong — a slow response, an error, or unexpected behavior — traditional monitoring tools struggle to answer: **which service caused the problem?**

Distributed tracing solves this by attaching a unique **trace ID** to every request at the entry point, then propagating this ID through every service call. Each service records a **span** (a unit of work with start time, end time, and metadata), and all spans with the same trace ID form a **trace** — a complete timeline of the request's journey.

```
User Request
│
├─ [Span 1: API Gateway - 250ms]
│   ├─ [Span 2: Auth Service - 45ms]
│   ├─ [Span 3: Product Service - 180ms]
│   │   ├─ [Span 4: Database Query - 120ms]  ← BOTTLENECK
│   │   └─ [Span 5: Cache Lookup - 5ms]
│   └─ [Span 6: Cart Service - 20ms]
│
Total: 250ms
```

### What Is Jaeger?

Jaeger is an open-source end-to-end distributed tracing system originally built by Uber Technologies and donated to the CNCF (where it is now a graduated project). It follows the OpenTracing/OpenTelemetry standards.

Jaeger provides:
- **Distributed context propagation** — trace ID flows across service boundaries via HTTP headers (`uber-trace-id`) or gRPC metadata
- **Distributed transaction monitoring** — visualize the full lifecycle of a request
- **Root cause analysis** — identify which service introduced latency or errors
- **Service dependency analysis** — understand how services relate to each other
- **Performance optimization** — find the slowest operations to optimize

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Trace** | The complete end-to-end journey of a request; identified by a unique Trace ID |
| **Span** | A single named, timed operation within a trace (e.g., "query database", "call auth API") |
| **Span Context** | The propagation context: trace ID, span ID, sampling flags |
| **Baggage** | Key-value pairs propagated alongside the trace context |
| **Tags** | Key-value metadata attached to a span (HTTP method, status code, DB query) |
| **Logs** | Timestamped events within a span (stack traces, events) |
| **Sampling** | Decision of whether to record a trace (head-based or tail-based) |
| **Instrumentation** | Code that creates spans — can be automatic or manual |

### Jaeger Architecture

```
Application Services
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Frontend    │    │  Backend API │    │  Database    │
│              │───▶│              │───▶│   Client     │
│  [tracer]    │    │  [tracer]    │    │  [tracer]    │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────────────────────────────────────────┐
│                Jaeger Agent                     │
│     (UDP listener, batches spans locally)        │
└───────────────────┬─────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│              Jaeger Collector                    │
│  (validates, indexes, stores spans via pipeline) │
└───────────────────┬─────────────────────────────┘
                    │
          ┌─────────▼────────┐
          │    Storage       │
          │ (Elasticsearch / │
          │  Cassandra /     │
          │  BadgerDB)       │
          └─────────┬────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│              Jaeger Query                       │
│  (REST API + Jaeger UI for trace exploration)   │
└─────────────────────────────────────────────────┘
```

### Jaeger vs Zipkin

| Feature                  | Jaeger                          | Zipkin                          |
|--------------------------|---------------------------------|---------------------------------|
| Origin                   | Uber (CNCF graduated)           | Twitter                         |
| OpenTelemetry Support    | ✅ Native                        | ✅ Via bridge                    |
| UI Quality               | ✅ Excellent (DAG, flamegraph)   | ✅ Good                          |
| Storage Backends         | ES, Cassandra, Kafka, BadgerDB  | ES, Cassandra, MySQL, in-memory |
| Adaptive Sampling        | ✅ Built-in                      | ❌                               |
| Service Dependency Graph | ✅ Built-in                      | ✅                               |
| Kubernetes Operator      | ✅ Official operator             | ❌                               |
| Grafana Integration      | ✅ Native data source            | ✅ Via plugin                    |
| Istio Integration        | ✅ First-class                   | ✅                               |
| Sampling Strategies      | Probabilistic, rate-limiting, adaptive | Probabilistic, rate-limiting |
| Language SDKs            | All major languages             | All major languages             |

---

## 2. Local Setup on Minikube

### Option A: All-in-One Deployment (Quickstart)

The all-in-one image bundles all Jaeger components with an in-memory storage backend. Perfect for development and testing.

```bash
# Create tracing namespace
kubectl create namespace tracing

# Deploy Jaeger all-in-one
kubectl apply -n tracing -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: tracing
  labels:
    app: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "14269"
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:1.53
          args:
            - "--memory.max-traces=50000"   # Keep last 50k traces in memory
            - "--query.base-path=/jaeger"   # Optional URL prefix
          env:
            - name: COLLECTOR_OTLP_ENABLED
              value: "true"                 # Enable OpenTelemetry protocol
            - name: SPAN_STORAGE_TYPE
              value: "memory"
          ports:
            - containerPort: 5775           # UDP agent: Zipkin compact thrift
              protocol: UDP
            - containerPort: 6831           # UDP agent: Jaeger compact thrift
              protocol: UDP
            - containerPort: 6832           # UDP agent: Jaeger binary thrift
              protocol: UDP
            - containerPort: 5778           # HTTP config server
            - containerPort: 16686          # Jaeger UI
            - containerPort: 14268          # HTTP collector: accept jaeger.thrift
            - containerPort: 14269          # Admin port: health check, metrics
            - containerPort: 4317           # OTLP gRPC receiver
            - containerPort: 4318           # OTLP HTTP receiver
          resources:
            requests:
              memory: 256Mi
              cpu: 100m
            limits:
              memory: 512Mi
              cpu: 500m
          livenessProbe:
            httpGet:
              path: /
              port: 14269
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 14269

---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-all-in-one
  namespace: tracing
  labels:
    app: jaeger
spec:
  selector:
    app: jaeger
  ports:
    - name: agent-compact-thrift
      port: 6831
      protocol: UDP
      targetPort: 6831
    - name: collector-http
      port: 14268
      targetPort: 14268
    - name: query-http
      port: 16686
      targetPort: 16686
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
    - name: otlp-http
      port: 4318
      targetPort: 4318
    - name: admin
      port: 14269
      targetPort: 14269
EOF

# Wait for Jaeger to start
kubectl wait --for=condition=Available \
  deployment/jaeger \
  -n tracing \
  --timeout=60s

# Access Jaeger UI
kubectl port-forward -n tracing svc/jaeger-all-in-one 16686:16686 &
echo "Jaeger UI: http://localhost:16686"
```

### Option B: Jaeger Operator (Production Setup)

The Jaeger Operator manages Jaeger deployments with different deployment strategies.

```bash
# Install cert-manager (required by Jaeger Operator)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl wait --for=condition=Available \
  deployment/cert-manager \
  -n cert-manager \
  --timeout=120s

# Install Jaeger Operator
kubectl create namespace observability
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.53.0/jaeger-operator.yaml \
  -n observability

# Wait for operator
kubectl wait --for=condition=Available \
  deployment/jaeger-operator \
  -n observability \
  --timeout=120s

# Deploy Jaeger using operator CRD
kubectl apply -f - << 'EOF'
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: simplest
  namespace: tracing
spec:
  strategy: allInOne        # Other options: production, streaming
  allInOne:
    image: jaegertracing/all-in-one:1.53
    options:
      memory:
        max-traces: 100000
  storage:
    type: memory             # Use elasticsearch for production
  ingress:
    enabled: false
  agent:
    strategy: DaemonSet      # Deploy agent as DaemonSet for auto-injection
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
EOF

# For production with Elasticsearch storage:
kubectl apply -f - << 'EOF'
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger-production
  namespace: tracing
spec:
  strategy: production
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch-es-http.elastic.svc.cluster.local:9200
        username: elastic
        index-prefix: jaeger
    secretName: jaeger-secret
  collector:
    replicas: 2
    resources:
      requests:
        memory: 128Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m
  query:
    replicas: 1
    options:
      query:
        base-path: /jaeger
EOF
```

---

## 3. Online/Cloud Setup

### Jaeger on Grafana Tempo (Free Cloud Tracing)

Grafana Tempo is a distributed tracing backend that is OpenTelemetry-compatible and integrates natively with Grafana Cloud.

```bash
# Install Tempo on Kubernetes
helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo \
  --namespace tracing \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo \
  --set persistence.enabled=true \
  --set persistence.size=10Gi

# Configure OpenTelemetry Collector to send to Grafana Cloud Tempo
cat > otel-collector-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: tracing
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          thrift_compact:
            endpoint: 0.0.0.0:6831
          thrift_http:
            endpoint: 0.0.0.0:14268

    processors:
      batch:
        timeout: 5s
        send_batch_size: 10000

    exporters:
      otlp:
        endpoint: "tempo-distributor.tracing.svc.cluster.local:4317"
        tls:
          insecure: true
      # Forward to Grafana Cloud
      otlp/grafana:
        endpoint: "tempo-prod-04-prod-us-east-0.grafana.net:443"
        headers:
          authorization: "Basic <base64-encoded-user:token>"

    service:
      pipelines:
        traces:
          receivers: [otlp, jaeger]
          processors: [batch]
          exporters: [otlp, otlp/grafana]
EOF
```

---

## 4. Configuration Deep Dive

### 4.1 Sampling Strategies

Sampling determines what percentage of requests to trace. Tracing 100% of requests would produce too much data and add overhead.

#### Head-Based Sampling (decision at trace start)

```yaml
# Sampling configuration served by Jaeger
# GET http://jaeger-agent:5778/sampling?service=my-service

# Remote sampling strategies file
apiVersion: v1
kind: ConfigMap
metadata:
  name: jaeger-sampling-strategies
  namespace: tracing
data:
  sampling_strategies.json: |
    {
      "service_strategies": [
        {
          "service": "payment-service",
          // WARNING: param 1.0 = 100% sampling. Only use in development/debugging.
          // In production, use 0.01-0.10 (1%-10%) to limit overhead and storage.
          "type": "probabilistic",
          "param": 1.0
        },
        {
          "service": "frontend",
          "type": "ratelimiting",
          "param": 100          
        },
        {
          "service": "health-checker",
          "type": "probabilistic",
          "param": 0.001        
        }
      ],
      "default_strategy": {
        "type": "probabilistic",
        "param": 0.1            
      }
    }
```

#### Adaptive Sampling (Jaeger built-in)

```bash
# Enable adaptive sampling in Jaeger Collector
kubectl patch deployment -n tracing jaeger-collector \
  --type=json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--sampling.strategies-file=/etc/jaeger/sampling_strategies.json"}]'

# Adaptive sampling automatically adjusts rates to achieve target QPS per service
# Jaeger Operator configuration:
apiVersion: jaegertracing.io/v1
kind: Jaeger
spec:
  collector:
    options:
      collector:
        tags: "environment=production,cluster=k8s-prod"
  sampling:
    options:
      default_strategy:
        type: adaptive
        max_traces_per_second: 10     # Target 10 traces per second
```

### 4.2 Storage Backends

#### Elasticsearch Storage (Recommended for Production)

```yaml
# jaeger-elasticsearch.yaml
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger
  namespace: tracing
spec:
  strategy: production
  
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch-es-http.elastic.svc.cluster.local:9200
        username: elastic
        # Index prefix - all Jaeger indices will be: jaeger-span-YYYY-MM-DD
        index-prefix: jaeger
        # Number of shards/replicas per index
        num-shards: 1
        num-replicas: 0           # 0 for single-node ES
        # Retention - how long to keep spans
        max-span-age: 168h        # 7 days
        # Bulk indexing settings
        bulk:
          workers: 1
          size: 5000000           # 5MB
          actions: 1000
          flush-interval: 200ms
    # ILM - Index Lifecycle Management
    esIndexCleaner:
      enabled: true
      numberOfDays: 7             # Delete indices older than 7 days
      schedule: "55 23 * * *"    # Run at 23:55 every day

    secretName: jaeger-es-credentials

---
apiVersion: v1
kind: Secret
metadata:
  name: jaeger-es-credentials
  namespace: tracing
type: Opaque
stringData:
  ES_PASSWORD: "elastic-password"
  ES_USERNAME: "elastic"
```

### 4.3 OpenTelemetry Auto-Instrumentation

```yaml
# Install OpenTelemetry Operator for auto-instrumentation
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# Create Instrumentation resource
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: my-instrumentation
  namespace: default
spec:
  # OTLP endpoint (Jaeger OTLP receiver or OpenTelemetry Collector)
  exporter:
    endpoint: http://jaeger-all-in-one.tracing.svc.cluster.local:4317
  
  propagators:
    - tracecontext     # W3C Trace Context
    - baggage
    - jaeger           # Jaeger propagation headers
    - b3               # B3 propagation (Zipkin-compatible)
  
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"    # Sample 10% of traces
  
  # Language-specific agent configurations
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.0
    env:
      - name: OTEL_EXPORTER_OTLP_TIMEOUT
        value: "20000"
  
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.43b0
    env:
      - name: OTEL_LOGS_EXPORTER
        value: "none"
  
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.44.0
  
  dotnet:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.2.0
```

```yaml
# Annotate a deployment for auto-instrumentation
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: default
spec:
  template:
    metadata:
      annotations:
        # Triggers OTel operator to inject agent
        instrumentation.opentelemetry.io/inject-java: "true"
        # Optional: specify service name
        instrumentation.opentelemetry.io/container-names: "payment-service"
    spec:
      containers:
        - name: payment-service
          image: mycompany/payment-service:v1.0
          env:
            - name: OTEL_SERVICE_NAME
              value: payment-service
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "service.version=1.0,deployment.environment=production"
```

---

## 5. Integration with Existing Tools

### 5.1 Kubernetes: Auto-injection of Jaeger Agent

The Jaeger Operator can automatically inject a Jaeger agent sidecar into pods.

```yaml
# Enable auto-injection for a namespace
kubectl annotate namespace default \
  sidecar.jaegertracing.io/inject=jaeger-production

# Or annotate specific deployments
kubectl annotate deployment payment-service \
  sidecar.jaegertracing.io/inject=jaeger-production

# The operator injects the agent as a sidecar:
# Container jaeger-agent is added to each pod
# Application connects to localhost:6831 (UDP) to report spans
```

### 5.2 Istio: Jaeger Integration with Service Mesh

Istio's Envoy proxy automatically propagates trace headers for all traffic it proxies.

```bash
# Verify Istio is installed
kubectl get pods -n istio-system

# Configure Istio to send traces to Jaeger
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio
  namespace: istio-system
data:
  mesh: |
    defaultConfig:
      tracing:
        zipkin:
          address: jaeger-all-in-one.tracing.svc.cluster.local:9411
        sampling: 100.0          # Sample 100% for debugging
    enableTracing: true
EOF

# Restart istiod to apply
kubectl rollout restart deployment/istiod -n istio-system

# Verify traces appear in Jaeger from Istio
# Navigate to http://localhost:16686, service: istio-ingressgateway
```

### 5.3 Grafana: Jaeger Data Source

```bash
# Jaeger is already configured as a Grafana datasource in the Grafana guide
# Verify the Jaeger datasource:
curl -s http://admin:admin123@localhost:3000/api/datasources | \
  python3 -c "
import json, sys
for s in json.load(sys.stdin):
    if s['type'] == 'jaeger':
        print(f\"Jaeger datasource: {s['name']} at {s['url']}\")
"

# Open Grafana Explore and select Jaeger datasource
# Search by service, operation, trace ID, or tags
# Example trace ID search: 5e8d4c2f1a9b3e7f
```

### 5.4 Prometheus: RED Metrics Correlation

The RED method (Rate, Errors, Duration) correlates with tracing data:

```yaml
# Use exemplars to link Prometheus metrics to specific traces
# Application code (Go example):
# histogram.Observe(duration, prometheus.Labels{"handler": "/api/order"},
#   prometheus.ExemplarLabels{"traceID": traceID})

# In Grafana: Enable exemplars for Prometheus datasource
# Configuration > Data Sources > Prometheus > Enable exemplars
# Trace ID label name: traceID
# Data source for traces: Jaeger

# ServiceMonitor with exemplar support
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-service
  namespace: monitoring
spec:
  endpoints:
    - port: metrics
      interval: 15s
      # Exemplars are automatically captured if app exports them
```

---

## 6. Real-World Scenarios

### Scenario 1: Trace a Slow HTTP Request Across Microservices

```bash
# Step 1: Identify slow requests from Prometheus
# PromQL query to find requests > 1 second:
# histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 1

# Step 2: Get trace ID from application logs or exemplars
kubectl logs -n production \
  $(kubectl get pod -n production -l app=api-gateway -o jsonpath='{.items[0].metadata.name}') | \
  grep "trace_id" | grep "slow\|timeout\|5[0-9][0-9]" | tail -5

# Step 3: Search in Jaeger by trace ID
curl "http://localhost:16686/api/traces/5e8d4c2f1a9b3e7f0a2b4c6d8e9f1a2b" | \
  python3 -m json.tool | head -50

# Step 4: Or search by service and operation with duration filter
curl "http://localhost:16686/api/traces?service=api-gateway&operation=GET%20/api/checkout&minDuration=1000ms&limit=20" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for trace in data['data'][:5]:
    trace_id = trace['traceID']
    duration = max(s['duration'] for s in trace['spans']) / 1000
    root_span = next(s for s in trace['spans'] if not s.get('references'))
    print(f'Trace: {trace_id}')
    print(f'  Duration: {duration:.1f}ms')
    print(f'  Service: {root_span[\"processID\"]}')
    print(f'  Operation: {root_span[\"operationName\"]}')
    print()
"

# Step 5: Find which child span is slowest
curl "http://localhost:16686/api/traces/5e8d4c2f1a9b3e7f0a2b4c6d8e9f1a2b" | \
  python3 -c "
import json, sys
trace = json.load(sys.stdin)['data'][0]
spans = sorted(trace['spans'], key=lambda s: -s['duration'])
for span in spans[:5]:
    service = trace['processes'][span['processID']]['serviceName']
    print(f'{service}/{span[\"operationName\"]}: {span[\"duration\"]/1000:.1f}ms')
"
```

### Scenario 2: Find the Bottleneck in a 5-Service Chain

```bash
# Deploy a sample microservices application for demo
kubectl apply -f - << 'EOF'
# Simplified HotROD demo application from Jaeger
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hotrod
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hotrod
  template:
    metadata:
      labels:
        app: hotrod
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: hotrod
          image: jaegertracing/example-hotrod:1.53
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: JAEGER_AGENT_HOST
              value: jaeger-all-in-one.tracing.svc.cluster.local
            - name: JAEGER_AGENT_PORT
              value: "6831"
            - name: JAEGER_SAMPLER_TYPE
              value: const
            - name: JAEGER_SAMPLER_PARAM
              value: "1"
---
apiVersion: v1
kind: Service
metadata:
  name: hotrod
  namespace: default
spec:
  selector:
    app: hotrod
  ports:
    - port: 8080
      name: http
  type: NodePort
EOF

# Access HotROD
kubectl port-forward svc/hotrod 8080:8080 &
# Open http://localhost:8080 and click on customer requests

# Step 1: Generate some traffic
for i in {1..10}; do
  curl -s "http://localhost:8080/dispatch?customer=123" > /dev/null
done

# Step 2: Find slowest traces
curl "http://localhost:16686/api/traces?service=frontend&limit=20&lookback=1h" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
traces = sorted(data['data'], key=lambda t: -max(s['duration'] for s in t['spans']))
for trace in traces[:3]:
    max_duration = max(s['duration'] for s in trace['spans']) / 1000
    print(f'Trace {trace[\"traceID\"][:16]}: {max_duration:.0f}ms, {len(trace[\"spans\"])} spans')
"

# Step 3: Analyze service dependency graph
curl "http://localhost:16686/api/dependencies?endTs=$(date +%s000)&lookback=3600000" | \
  python3 -c "
import json, sys
deps = json.load(sys.stdin)
for d in deps['data']:
    print(f'{d[\"parent\"]} -> {d[\"child\"]}: {d[\"callCount\"]} calls')
"
```

### Scenario 3: Debug Intermittent Errors

```bash
# Step 1: Find traces with errors
curl "http://localhost:16686/api/traces?service=payment-service&tags=%7B%22error%22%3A%22true%22%7D&limit=20&lookback=1h" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Found {len(data[\"data\"])} error traces')
for trace in data['data'][:5]:
    error_spans = [s for s in trace['spans'] if any(t.get('key') == 'error' and t.get('value') for t in s.get('tags', []))]
    for span in error_spans:
        service = trace['processes'][span['processID']]['serviceName']
        error_msg = next((t['value'] for t in span.get('tags', []) if t['key'] == 'error.message'), 'unknown')
        print(f'  Service: {service}, Operation: {span[\"operationName\"]}')
        print(f'  Error: {error_msg}')
"

# Step 2: Correlate with error logs in ELK
# Find trace IDs from Jaeger, then search in Elasticsearch
TRACE_IDS=("abc123" "def456" "ghi789")
for TRACE_ID in "${TRACE_IDS[@]}"; do
  echo "Searching logs for trace: $TRACE_ID"
  curl -s -X POST "http://localhost:9200/k8s-logs-*/_search" \
    -u "elastic:$ES_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"query\": {\"term\": {\"trace.id\": \"$TRACE_ID\"}}, \"size\": 20}" | \
    python3 -c "
import json, sys
hits = json.load(sys.stdin)['hits']['hits']
for h in hits:
    print(f\"  [{h['_source'].get('@timestamp', '')}] {h['_source'].get('message', '')[:100]}\")
  "
done

# Step 3: Find error patterns - what operation fails most often?
curl "http://localhost:16686/api/traces?service=payment-service&tags=%7B%22error%22%3A%22true%22%7D&limit=100&lookback=24h" | \
  python3 -c "
import json, sys
from collections import Counter
data = json.load(sys.stdin)
error_ops = Counter()
for trace in data['data']:
    for span in trace['spans']:
        if any(t.get('key') == 'error' and t.get('value') for t in span.get('tags', [])):
            error_ops[span['operationName']] += 1
for op, count in error_ops.most_common(10):
    print(f'{op}: {count} errors')
"
```

---

## 7. Verification & Testing

### Verify Jaeger Components

```bash
# Check all components are running
kubectl get pods -n tracing
# NAME                        READY   STATUS    RESTARTS   AGE
# jaeger-7b8c9d7f4d-xkj2p    1/1     Running   0          5m

# Check Jaeger health
curl -s http://localhost:14269/ | head -5

# Verify UI is accessible
curl -s http://localhost:16686/ | grep "Jaeger UI" | head -3

# Check Jaeger services via API
curl -s http://localhost:16686/api/services | python3 -m json.tool
# {"data": ["jaeger-query", "frontend", "backend"], "total": 3}

# Check operations for a service
curl -s "http://localhost:16686/api/operations?service=frontend" | python3 -m json.tool
```

### Send a Test Trace

```bash
# Send a test trace using Jaeger's HTTP collector
curl -X POST "http://localhost:14268/api/traces" \
  -H "Content-Type: application/x-thrift" \
  --data-binary @<(python3 - << 'EOF'
# This would normally be a Thrift-encoded span
# Use OTLP instead:
EOF
)

# Better: Send via OTLP HTTP
curl -X POST "http://localhost:4318/v1/traces" \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{"key": "service.name", "value": {"stringValue": "test-service"}}]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5b8efff798038103d269b633813fc60c",
          "spanId": "eee19b7ec3c1b173",
          "name": "test-operation",
          "kind": 1,
          "startTimeUnixNano": "1705312000000000000",
          "endTimeUnixNano": "1705312000100000000",
          "status": {"code": 1}
        }]
      }]
    }]
  }'

# Verify trace appears
curl "http://localhost:16686/api/traces/5b8efff798038103d269b633813fc60c" | python3 -m json.tool
```

---

## 8. Troubleshooting Guide

### Issue 1: No Traces Appearing in Jaeger UI

**Symptoms:** Jaeger UI shows "No traces found"

**Solution:**
```bash
# 1. Check if Jaeger is receiving spans
curl http://localhost:14269/metrics | grep "jaeger_collector_spans_received"

# 2. Check application agent configuration
kubectl exec -n default <app-pod> -- env | grep JAEGER

# 3. Verify UDP connectivity to Jaeger agent (port 6831)
kubectl exec -n default <app-pod> -- sh -c \
  "echo 'test' > /dev/udp/jaeger-all-in-one.tracing.svc.cluster.local/6831 && echo OK"

# 4. Check Jaeger collector logs
kubectl logs -n tracing deployment/jaeger | grep -E "ERROR|WARN" | tail -20

# 5. Verify sampling is not set to 0
curl http://localhost:5778/sampling?service=my-service | python3 -m json.tool
```

### Issue 2: Jaeger Running Out of Memory (All-in-One)

**Symptoms:** Jaeger pod OOMKilled with in-memory storage

**Solution:**
```bash
# Reduce max traces in memory
kubectl set env deployment/jaeger \
  MEMORY_MAX_TRACES=10000 \
  -n tracing

# Or switch to Elasticsearch storage for production
# See Section 4.2 for ES storage configuration
```

### Issue 3: Traces Incomplete (Missing Spans)

**Symptoms:** Traces show some services but missing others

**Solution:**
```bash
# 1. Check if all services are configured to send to same Jaeger
kubectl exec -n default <missing-service-pod> -- env | grep -E "JAEGER|OTEL"

# 2. Check trace context propagation headers
# Each service must extract and propagate these headers:
# - uber-trace-id (Jaeger native)
# - traceparent (W3C)
# - b3 (Zipkin)

# 3. Verify services use same propagation format
# Add to application environment:
kubectl set env deployment/my-service \
  OTEL_PROPAGATORS=tracecontext,baggage,jaeger \
  -n default

# 4. Check for network issues between services
kubectl exec -n default <service-pod> -- \
  wget -O- http://jaeger-all-in-one.tracing.svc.cluster.local:14268/api/traces
```

### Issue 4: High Latency from Jaeger Agent

**Symptoms:** Adding tracing increases request latency significantly

**Solution:**
```bash
# Jaeger agent uses async UDP - should add <1ms overhead
# If latency is high, check:

# 1. Ensure using UDP (not HTTP) for agent communication
# UDP is fire-and-forget, HTTP waits for response
# Bad:  JAEGER_ENDPOINT=http://jaeger:14268/api/traces
# Good: JAEGER_AGENT_HOST=jaeger  JAEGER_AGENT_PORT=6831

# 2. Reduce sampling rate in production
# Set to 10% instead of 100%
kubectl create configmap jaeger-sampling \
  --from-literal=strategies.json='{"default_strategy":{"type":"probabilistic","param":0.1}}' \
  -n tracing

# 3. Use batch processing for spans
# In application config:
# OTEL_BSP_MAX_QUEUE_SIZE=2048
# OTEL_BSP_EXPORT_TIMEOUT=30000
# OTEL_BSP_SCHEDULE_DELAY=5000
```

### Issue 5: Elasticsearch Storage Index Not Created

**Symptoms:** Jaeger with ES backend fails with "no index found"

**Solution:**
```bash
# Run Jaeger ES index creation job
kubectl apply -f - << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: jaeger-es-index-init
  namespace: tracing
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: jaeger-es-index-cleaner
          image: jaegertracing/jaeger-es-index-cleaner:1.53
          args:
            - "0"
            - http://elasticsearch-es-http.elastic.svc.cluster.local:9200
          env:
            - name: ES_USERNAME
              value: elastic
            - name: ES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: elasticsearch-es-elastic-user
                  key: elastic
EOF

# Check Elasticsearch indices
curl -s "http://localhost:9200/_cat/indices/jaeger*?v" \
  -u "elastic:$ES_PASSWORD"
```

---

## 9. Jaeger Cheat Sheet

### Jaeger API Quick Reference

| Endpoint | Description |
|----------|-------------|
| `GET /api/services` | List all traced services |
| `GET /api/operations?service=<name>` | List operations for a service |
| `GET /api/traces?service=<name>&limit=20` | Search traces |
| `GET /api/traces/<traceID>` | Get specific trace |
| `GET /api/dependencies` | Get service dependency graph |
| `GET /api/services/<svc>/operations` | Operations for service |
| `GET /` (port 14269) | Admin health check |
| `GET /metrics` (port 14269) | Prometheus metrics |

### Trace Search Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `service` | Filter by service name | `service=payment-api` |
| `operation` | Filter by operation | `operation=POST%20/checkout` |
| `tags` | Filter by span tags (JSON) | `tags={"error":"true"}` |
| `minDuration` | Minimum trace duration | `minDuration=100ms` |
| `maxDuration` | Maximum trace duration | `maxDuration=5s` |
| `limit` | Max results to return | `limit=20` |
| `lookback` | Time window | `lookback=1h` |
| `start` | Start time (microseconds) | `start=1705312000000000` |
| `end` | End time (microseconds) | `end=1705315600000000` |

### OpenTelemetry Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name in traces | `payment-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | `http://jaeger:4317` |
| `OTEL_TRACES_SAMPLER` | Sampling strategy | `parentbased_traceidratio` |
| `OTEL_TRACES_SAMPLER_ARG` | Sampling argument | `0.1` (10%) |
| `OTEL_PROPAGATORS` | Context propagators | `tracecontext,baggage,jaeger` |
| `OTEL_RESOURCE_ATTRIBUTES` | Resource attributes | `service.version=1.0,env=prod` |
| `OTEL_LOG_LEVEL` | SDK logging level | `debug` |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | Batch span processor size | `512` |

### Jaeger Agent Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 5775 | UDP | Zipkin compact thrift (deprecated) |
| 6831 | UDP | Jaeger compact thrift (**primary**) |
| 6832 | UDP | Jaeger binary thrift |
| 5778 | HTTP | Sampling configuration endpoint |
| 14271 | HTTP | Agent admin/health |

### Jaeger Collector Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 14267 | TCP | Jaeger thrift from agent |
| 14268 | HTTP | Jaeger thrift direct from clients |
| 14269 | HTTP | Admin/health/metrics |
| 4317 | gRPC | OTLP traces |
| 4318 | HTTP | OTLP traces |
| 9411 | HTTP | Zipkin compatible endpoint |

---

*Last updated: 2024 | Maintained by DevOps Team*
