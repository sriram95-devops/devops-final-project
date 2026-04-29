# ELK Stack Guide for Kubernetes

## Table of Contents

1. [Overview & Why ELK](#1-overview--why-elk)
2. [Local Setup on Minikube](#2-local-setup-on-minikube)
3. [Online/Cloud Setup](#3-onlinecloud-setup)
4. [Configuration Deep Dive](#4-configuration-deep-dive)
5. [Integration with Existing Tools](#5-integration-with-existing-tools)
6. [Real-World Scenarios](#6-real-world-scenarios)
7. [Verification & Testing](#7-verification--testing)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [ELK Cheat Sheet](#9-elk-cheat-sheet)

---

## 1. Overview & Why ELK

### What Is the ELK Stack?

The ELK Stack is a combination of three open-source tools that together provide a powerful log management and analytics platform:

- **E**lasticsearch — A distributed search and analytics engine built on Apache Lucene. It stores logs as JSON documents and provides near-real-time search and aggregation capabilities.
- **L**ogstash — A server-side data processing pipeline that ingests data from multiple sources simultaneously, transforms it, and then sends it to Elasticsearch.
- **K**ibana — A data visualization and exploration interface that sits on top of Elasticsearch, providing dashboards, search, and analytics features.

In modern Kubernetes deployments, **Filebeat** (a lightweight log shipper) typically replaces Logstash for collection, creating the "EFK Stack" (Elasticsearch + Filebeat + Kibana). Logstash is still used for complex transformations.

### Why ELK for Kubernetes Log Monitoring?

In Kubernetes environments, logs are distributed across:
- Hundreds of pods running across multiple nodes
- System components (kubelet, kube-proxy, CoreDNS)
- Infrastructure (etcd, API server)
- Ingress controllers and service meshes

Without a centralized logging solution, you must `kubectl logs` into each individual pod, which is:
- **Impractical at scale** — 100 pods means 100 separate log checks
- **Ephemeral** — Kubernetes deletes pod logs when pods are restarted or rescheduled
- **Non-searchable** — You cannot search for patterns across pods simultaneously
- **No correlation** — Cannot link logs from frontend, backend, and database pods for a single request

ELK solves all of this by centralizing logs with:
- **Full-text search** across all pods simultaneously
- **Structured field extraction** — parse `level`, `timestamp`, `trace_id` from JSON logs
- **Real-time dashboards** — visualize error rates, slow requests, exception patterns
- **Log retention** — 30/90/365 day retention with ILM policies
- **Alerting** — get paged when error rate spikes

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                   │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  Pod A   │  │  Pod B   │  │  Pod C   │              │
│  │ /var/log │  │ /var/log │  │ /var/log │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │              │              │                    │
│  ┌────▼──────────────▼──────────────▼─────┐             │
│  │         Filebeat DaemonSet              │             │
│  │  (one per node, reads all pod logs)     │             │
│  └────────────────────┬────────────────────┘             │
│                       │                                  │
│  ┌────────────────────▼────────────────────┐            │
│  │              Logstash                    │            │
│  │  (parse, transform, enrich logs)         │            │
│  └────────────────────┬────────────────────┘            │
│                       │                                  │
│  ┌────────────────────▼────────────────────┐            │
│  │           Elasticsearch                  │            │
│  │  (store, index, search logs)             │            │
│  └────────────────────┬────────────────────┘            │
│                       │                                  │
│  ┌────────────────────▼────────────────────┐            │
│  │               Kibana                     │            │
│  │  (visualize, search, alert)              │            │
│  └─────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Local Setup on Minikube

### Prerequisites

```bash
# Verify resources - ELK needs significant memory
minikube status
# minikube: Running
# kubectl: Correctly Configured

# Check available resources
kubectl top nodes 2>/dev/null || echo "metrics-server not ready yet"

# If Minikube is not started with enough resources, restart it
minikube stop
minikube start \
  --cpus=4 \
  --memory=10240 \
  --disk-size=30g \
  --driver=docker

# Verify kubectl works
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   2m    v1.29.0
```

### Method A: ECK (Elastic Cloud on Kubernetes) — Recommended

ECK is the official Kubernetes operator for Elasticsearch, Kibana, and the Elastic Beats family.

#### Step 1: Install ECK Operator

```bash
# Install ECK CRDs and operator
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
# customresourcedefinition.apiextensions.k8s.io/agents.agent.k8s.elastic.co created
# customresourcedefinition.apiextensions.k8s.io/apmservers.apm.k8s.elastic.co created
# customresourcedefinition.apiextensions.k8s.io/beats.beat.k8s.elastic.co created
# customresourcedefinition.apiextensions.k8s.io/elasticmapsservers.maps.k8s.elastic.co created
# customresourcedefinition.apiextensions.k8s.io/elasticsearches.elasticsearch.k8s.elastic.co created
# customresourcedefinition.apiextensions.k8s.io/kibanas.kibana.k8s.elastic.co created

kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml
# namespace/elastic-system created
# serviceaccount/elastic-operator created
# ...
# deployment.apps/elastic-operator created

# Wait for operator to be ready
kubectl wait --for=condition=Available \
  deployment/elastic-operator \
  -n elastic-system \
  --timeout=120s

# Check operator logs
kubectl logs -n elastic-system statefulset.apps/elastic-operator | tail -5
```

#### Step 2: Deploy Elasticsearch

```bash
# Create elastic namespace
kubectl create namespace elastic

# Deploy a single-node Elasticsearch for Minikube (production needs 3+ nodes)
cat > elasticsearch.yaml << 'EOF'
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: elastic
spec:
  version: 8.12.0
  nodeSets:
    - name: default
      count: 1                          # Single node for Minikube
      config:
        # Disable security for easier local dev (NOT for production)
        xpack.security.enabled: true
        xpack.security.http.ssl.enabled: false
        xpack.security.transport.ssl.enabled: false
        # Memory settings
        node.store.allow_mmap: false    # Required for Minikube
      podTemplate:
        spec:
          initContainers:
            # Set vm.max_map_count for Elasticsearch
            - name: sysctl
              securityContext:
                privileged: true
                runAsUser: 0
              command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
          containers:
            - name: elasticsearch
              resources:
                requests:
                  memory: 1Gi
                  cpu: 500m
                limits:
                  memory: 2Gi
                  cpu: 1
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms512m -Xmx512m"    # JVM heap size
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
            storageClassName: standard
EOF

kubectl apply -f elasticsearch.yaml

# Watch Elasticsearch start up (takes 2-3 minutes)
kubectl get elasticsearch -n elastic -w
# NAME            HEALTH   NODES   VERSION   PHASE             AGE
# elasticsearch   green    1       8.12.0    Ready             3m

# Get the elastic user password
ES_PASSWORD=$(kubectl get secret -n elastic \
  elasticsearch-es-elastic-user \
  -o jsonpath="{.data.elastic}" | base64 --decode)
echo "Elasticsearch password: $ES_PASSWORD"
```

#### Step 3: Deploy Kibana

```bash
cat > kibana.yaml << 'EOF'
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: elastic
spec:
  version: 8.12.0
  count: 1
  elasticsearchRef:
    name: elasticsearch        # Automatically configures connection to ES
  http:
    tls:
      selfSignedCertificate:
        disabled: true         # Disable TLS for local access
  podTemplate:
    spec:
      containers:
        - name: kibana
          resources:
            requests:
              memory: 512Mi
              cpu: 200m
            limits:
              memory: 1Gi
              cpu: 500m
          env:
            - name: NODE_OPTIONS
              value: "--max-old-space-size=512"
EOF

kubectl apply -f kibana.yaml

# Wait for Kibana to be ready
kubectl get kibana -n elastic -w
# NAME     HEALTH   NODES   VERSION   AGE
# kibana   green    1       8.12.0    2m

# Access Kibana
kubectl port-forward -n elastic svc/kibana-kb-http 5601:5601 &
echo "Kibana available at: http://localhost:5601"
echo "Username: elastic"
echo "Password: $ES_PASSWORD"
```

#### Step 4: Deploy Filebeat DaemonSet

Filebeat collects logs from all pods on every node.

```bash
cat > filebeat.yaml << 'EOF'
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: filebeat
  namespace: elastic
spec:
  type: filebeat
  version: 8.12.0
  elasticsearchRef:
    name: elasticsearch
  kibanaRef:
    name: kibana
  config:
    # Filebeat configuration
    filebeat.autodiscover:
      providers:
        - type: kubernetes
          node: ${NODE_NAME}
          hints.enabled: true          # Read hints from pod annotations
          hints.default_config:
            type: container
            paths:
              - /var/log/containers/*${data.kubernetes.container.id}.log
          templates:
            # Multi-line log support for Java stack traces
            - condition:
                contains:
                  kubernetes.labels.app: java
              config:
                - type: container
                  paths:
                    - /var/log/containers/*${data.kubernetes.container.id}.log
                  multiline:
                    pattern: '^[[:space:]]'
                    negate: false
                    match: after
            # JSON log parsing
            - condition:
                contains:
                  kubernetes.labels.log-format: json
              config:
                - type: container
                  paths:
                    - /var/log/containers/*${data.kubernetes.container.id}.log
                  json.keys_under_root: true
                  json.add_error_key: true

    # Processors to enrich log data
    processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
          matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
      - add_host_metadata: ~
      - add_cloud_metadata: ~
      - drop_event:
          when:
            contains:
              kubernetes.container.name: "filebeat"  # Don't collect own logs
      # Parse log level from common formats
      - dissect:
          when:
            contains:
              message: " ERROR "
          tokenizer: "%{} %{log.level} %{}"
          field: message
          target_prefix: ""

    # Output settings
    output.elasticsearch:
      hosts: ["https://elasticsearch-es-http.elastic.svc.cluster.local:9200"]
      username: "elastic"
      password: "${ELASTIC_PASSWORD}"
      ssl.verification_mode: none
      # Index naming with date rotation
      index: "filebeat-%{[agent.version]}-%{+yyyy.MM.dd}"

    # Template settings
    setup.template.name: "filebeat"
    setup.template.pattern: "filebeat-*"
    setup.ilm.enabled: true
    setup.ilm.policy_name: "filebeat-policy"

    # Kibana setup
    setup.kibana:
      host: "http://kibana-kb-http.elastic.svc.cluster.local:5601"

  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: filebeat
        automountServiceAccountToken: true
        terminationGracePeriodSeconds: 30
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true                      # Required for host-level metadata
        tolerations:
          - key: node-role.kubernetes.io/control-plane
            effect: NoSchedule                 # Also collect control plane logs
        containers:
          - name: filebeat
            resources:
              requests:
                memory: 200Mi
                cpu: 100m
              limits:
                memory: 400Mi
                cpu: 200m
            env:
              - name: NODE_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: spec.nodeName
              - name: ELASTIC_PASSWORD
                valueFrom:
                  secretKeyRef:
                    name: elasticsearch-es-elastic-user
                    key: elastic
            securityContext:
              runAsUser: 0                     # Required to read host log files
              privileged: false
            volumeMounts:
              - name: varlogcontainers
                mountPath: /var/log/containers
              - name: varlogpods
                mountPath: /var/log/pods
              - name: varlibdockercontainers
                mountPath: /var/lib/docker/containers
        volumes:
          - name: varlogcontainers
            hostPath:
              path: /var/log/containers
          - name: varlogpods
            hostPath:
              path: /var/log/pods
          - name: varlibdockercontainers
            hostPath:
              path: /var/lib/docker/containers

---
# RBAC for Filebeat to read K8s metadata
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: elastic
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
rules:
  - apiGroups: [""]
    resources:
      - namespaces
      - pods
      - nodes
    verbs: ["get", "watch", "list"]
  - apiGroups: ["apps"]
    resources:
      - replicasets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources:
      - jobs
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
  - kind: ServiceAccount
    name: filebeat
    namespace: elastic
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f filebeat.yaml

# Verify Filebeat is running on all nodes
kubectl get pods -n elastic -l beat.k8s.elastic.co/name=filebeat
# NAME              READY   STATUS    RESTARTS   AGE
# filebeat-beat-xxxx   1/1     Running   0          2m
```

### Method B: Helm Chart Deployment

```bash
# Add Elastic Helm repository
helm repo add elastic https://helm.elastic.co
helm repo update

# Install Elasticsearch
helm install elasticsearch elastic/elasticsearch \
  --namespace elastic \
  --create-namespace \
  --set replicas=1 \
  --set minimumMasterNodes=1 \
  --set resources.requests.memory=1Gi \
  --set resources.limits.memory=2Gi \
  --set esJavaOpts="-Xmx512m -Xms512m" \
  --set persistence.size=10Gi \
  --set antiAffinity=soft

# Install Kibana
helm install kibana elastic/kibana \
  --namespace elastic \
  --set elasticsearchHosts=http://elasticsearch-master.elastic.svc.cluster.local:9200 \
  --set resources.requests.memory=512Mi \
  --set resources.limits.memory=1Gi

# Install Filebeat
helm install filebeat elastic/filebeat \
  --namespace elastic \
  --set filebeatConfig."filebeat\.yml"="$(cat filebeat-config.yml)"
```

---

## 3. Online/Cloud Setup

### Option A: Elastic Cloud Free Trial

Elastic Cloud provides a 14-day free trial with 8GB storage and full access to all Elastic Stack features.

```bash
# Step 1: Sign up at https://cloud.elastic.co/registration
# Step 2: Create a deployment (choose Google Cloud or Azure)
# Step 3: Note the Cloud ID and credentials

# Step 4: Configure Filebeat to ship to Elastic Cloud
cat > filebeat-cloud.yaml << 'EOF'
output.elasticsearch:
  cloud.id: "${ELASTIC_CLOUD_ID}"
  cloud.auth: "elastic:${ELASTIC_PASSWORD}"
  
setup.kibana:
  cloud.id: "${ELASTIC_CLOUD_ID}"
  cloud.auth: "elastic:${ELASTIC_PASSWORD}"
EOF

# Step 5: Create Kubernetes secret with credentials
kubectl create secret generic elastic-cloud-credentials \
  --namespace elastic \
  --from-literal=cloud-id="deployment-name:base64encodedstring" \
  --from-literal=elastic-password="your-elastic-password"
```

### Option B: Azure Elasticsearch Service

```bash
# Create Azure Elasticsearch Service
az elastic create \
  --name devops-elastic \
  --resource-group devops-rg \
  --location eastus \
  --sku-name "ess-consumption-2024_Monthly" \
  --version 8.12.0

# Get the Elasticsearch endpoint
az elastic show \
  --name devops-elastic \
  --resource-group devops-rg \
  --query "properties.elasticProperties.elasticsearchServiceUrl" -o tsv
```

---

## 4. Configuration Deep Dive

### 4.1 Filebeat Configuration for K8s Pod Logs

```yaml
# filebeat.yml - Complete configuration

# ===== Autodiscover Configuration =====
filebeat.autodiscover:
  providers:
    - type: kubernetes
      # This node's name - used to collect only local logs
      node: ${NODE_NAME}
      
      # Enable hints-based configuration via pod annotations
      # Pods can self-configure by adding annotations like:
      # co.elastic.logs/enabled: "true"
      # co.elastic.logs/multiline.type: pattern
      hints.enabled: true
      
      # Default configuration for all containers
      hints.default_config:
        type: container
        paths:
          - /var/log/containers/*${data.kubernetes.container.id}.log
      
      # Named templates for specific workloads
      templates:
        # NGINX access logs
        - condition:
            equals:
              kubernetes.labels.app: nginx
          config:
            - module: nginx
              access:
                enabled: true
                var.paths: ["/var/log/containers/*${data.kubernetes.container.id}.log"]
              error:
                enabled: true
        
        # Spring Boot / Java applications
        - condition:
            equals:
              kubernetes.labels.runtime: java
          config:
            - type: container
              paths:
                - /var/log/containers/*${data.kubernetes.container.id}.log
              # Merge multi-line Java stack traces
              multiline.type: pattern
              multiline.pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
              multiline.negate: true
              multiline.match: after
              multiline.max_lines: 500
        
        # Apps that output JSON logs
        - condition:
            equals:
              kubernetes.labels.log-format: json
          config:
            - type: container
              paths:
                - /var/log/containers/*${data.kubernetes.container.id}.log
              # Parse JSON automatically
              json.keys_under_root: true
              json.overwrite_keys: true
              json.add_error_key: true
              json.expand_keys: true

# ===== Processors =====
processors:
  # Add Kubernetes metadata (pod name, namespace, labels)
  - add_kubernetes_metadata:
      host: ${NODE_NAME}
      matchers:
        - logs_path:
            logs_path: "/var/log/containers/"
  
  # Add host information
  - add_host_metadata:
      when.not.contains.tags: forwarded
  
  # Add cloud provider metadata (AWS, Azure, GCP)
  - add_cloud_metadata: ~
  
  # Drop health check logs (high volume, low value)
  - drop_event:
      when:
        or:
          - contains:
              message: "GET /health"
          - contains:
              message: "GET /readyz"
          - contains:
              message: "GET /livez"
  
  # Truncate very long messages (prevent Elasticsearch issues)
  - truncate_fields:
      fields: ["message"]
      max_bytes: 10240
      fail_on_error: false
  
  # Extract log level from message
  - script:
      lang: javascript
      id: extract_log_level
      source: >
        function process(event) {
          var msg = event.Get("message");
          if (msg == null) return;
          var levels = ["ERROR", "WARN", "INFO", "DEBUG", "TRACE"];
          for (var i = 0; i < levels.length; i++) {
            if (msg.indexOf(levels[i]) !== -1) {
              event.Put("log.level", levels[i].toLowerCase());
              break;
            }
          }
        }

# ===== Output =====
output.elasticsearch:
  hosts: ["${ELASTICSEARCH_HOST:elasticsearch-es-http.elastic.svc.cluster.local:9200}"]
  username: "${ELASTICSEARCH_USERNAME:elastic}"
  password: "${ELASTICSEARCH_PASSWORD}"
  
  # Data stream naming (Elastic 8.x)
  # Creates: filebeat-8.12.0-{YYYY.MM.DD}
  indices:
    - index: "filebeat-%{[agent.version]}-%{+yyyy.MM.dd}"

  # Bulk indexing settings
  bulk_max_size: 2048
  worker: 2
  
  # SSL/TLS (if enabled on Elasticsearch)
  # ssl.verification_mode: certificate
  # ssl.certificate_authorities: ["/etc/ssl/certs/ca.crt"]

# ===== ILM (Index Lifecycle Management) =====
setup.ilm.enabled: true
setup.ilm.rollover_alias: "filebeat"
setup.ilm.policy_name: "filebeat-7-days"
setup.ilm.policy:
  phases:
    hot:
      min_age: 0ms
      actions:
        rollover:
          max_size: 5GB
          max_age: 1d        # Rotate every day
        set_priority:
          priority: 100
    warm:
      min_age: 2d
      actions:
        shrink:
          number_of_shards: 1
        forcemerge:
          max_num_segments: 1
        set_priority:
          priority: 50
    delete:
      min_age: 7d            # Delete after 7 days
      actions:
        delete: {}

# ===== Monitoring =====
monitoring.enabled: true
monitoring.elasticsearch:
  hosts: ["${ELASTICSEARCH_HOST}"]
  username: "elastic"
  password: "${ELASTICSEARCH_PASSWORD}"
```

### 4.2 Logstash Pipeline Configuration

```ruby
# /usr/share/logstash/pipeline/logstash.conf

# ===== INPUT =====
input {
  # Receive from Filebeat
  beats {
    port => 5044
    ssl_enabled => false
  }
  
  # Direct TCP input for legacy systems
  tcp {
    port => 5000
    codec => json_lines
    type => "tcp"
  }
}

# ===== FILTER =====
filter {
  # Add common metadata
  mutate {
    add_field => {
      "environment" => "${ENVIRONMENT:development}"
      "cluster"     => "${CLUSTER_NAME:minikube}"
    }
  }
  
  # Parse Kubernetes container logs (containerd format)
  # Format: 2024-01-15T10:00:00.000000000Z stdout F <actual message>
  if [log][file][path] =~ "/var/log/containers/" {
    grok {
      match => {
        "message" => "^(?<time>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]+Z) (?<stream>stdout|stderr) (?<flags>[^ ]*) (?<log_message>.*)$"
      }
      overwrite => ["message"]
    }
    
    mutate {
      rename => { "log_message" => "message" }
      remove_field => ["flags", "time", "stream"]
    }
  }
  
  # Try to parse JSON logs
  if [message] =~ /^\{/ {
    json {
      source => "message"
      target => "parsed"
      skip_on_invalid_json => true
    }
    
    if "_jsonparsefailure" not in [tags] {
      # Promote common fields
      if [parsed][level] {
        mutate { rename => { "[parsed][level]" => "log.level" } }
      }
      if [parsed][msg] {
        mutate { rename => { "[parsed][msg]" => "message" } }
      }
      if [parsed][trace_id] {
        mutate { rename => { "[parsed][trace_id]" => "trace.id" } }
      }
    }
  }
  
  # Parse NGINX access logs
  if [kubernetes][labels][app] == "nginx" {
    grok {
      match => {
        "message" => '%{IPORHOST:client_ip} - %{USERNAME:auth} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{URIPATHPARAM:request} HTTP/%{NUMBER:http_version}" %{NUMBER:response_code:int} %{NUMBER:bytes_sent:int} "%{URI:referrer}" "%{GREEDYDATA:user_agent}" %{NUMBER:request_time:float}'
      }
    }
    
    geoip {
      source => "client_ip"
      target => "geoip"
    }
    
    useragent {
      source => "user_agent"
      target => "ua"
    }
  }
  
  # Set log severity from HTTP status
  if [response_code] {
    if [response_code] >= 500 {
      mutate { add_field => { "log.level" => "error" } }
    } else if [response_code] >= 400 {
      mutate { add_field => { "log.level" => "warn" } }
    } else {
      mutate { add_field => { "log.level" => "info" } }
    }
  }
  
  # Parse timestamps
  date {
    match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z", "ISO8601"]
    target => "@timestamp"
    timezone => "UTC"
  }
  
  # Drop noisy debug logs in production
  if [environment] == "production" and [log.level] == "debug" {
    drop {}
  }
  
  # Clean up unnecessary fields
  mutate {
    remove_field => ["agent", "ecs", "input", "host.mac"]
  }
}

# ===== OUTPUT =====
output {
  elasticsearch {
    hosts => ["${ELASTICSEARCH_HOSTS:http://elasticsearch-es-http.elastic.svc.cluster.local:9200}"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    
    # Dynamic index naming based on namespace
    index => "k8s-logs-%{[kubernetes][namespace]}-%{+YYYY.MM.dd}"
    
    # ILM policy
    ilm_enabled => true
    ilm_rollover_alias => "k8s-logs"
    ilm_policy => "k8s-logs-policy"
    
    # Retry settings
    retry_max_interval => 64
    retry_initial_interval => 2
  }
  
  # Also send to stdout for debugging
  if [log.level] == "error" {
    stdout {
      codec => rubydebug
    }
  }
}
```

### 4.3 Elasticsearch Index Templates and ILM Policies

```bash
# Create ILM policy via Elasticsearch API
ES_PASSWORD=$(kubectl get secret -n elastic \
  elasticsearch-es-elastic-user \
  -o jsonpath="{.data.elastic}" | base64 --decode)

kubectl port-forward -n elastic svc/elasticsearch-es-http 9200:9200 &

# Create ILM policy for K8s logs
curl -X PUT "http://localhost:9200/_ilm/policy/k8s-logs-policy" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "min_age": "0ms",
          "actions": {
            "rollover": {
              "max_size": "10gb",
              "max_age": "1d",
              "max_docs": 1000000
            },
            "set_priority": {"priority": 100}
          }
        },
        "warm": {
          "min_age": "3d",
          "actions": {
            "shrink": {"number_of_shards": 1},
            "forcemerge": {"max_num_segments": 1},
            "set_priority": {"priority": 50}
          }
        },
        "cold": {
          "min_age": "15d",
          "actions": {
            "freeze": {},
            "set_priority": {"priority": 0}
          }
        },
        "delete": {
          "min_age": "30d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'

# Create index template
curl -X PUT "http://localhost:9200/_index_template/k8s-logs" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["k8s-logs-*", "filebeat-*"],
    "priority": 200,
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "k8s-logs-policy",
        "index.lifecycle.rollover_alias": "k8s-logs",
        "index.mapping.total_fields.limit": 2000,
        "index.refresh_interval": "30s"
      },
      "mappings": {
        "dynamic_templates": [
          {
            "strings_as_keyword": {
              "match_mapping_type": "string",
              "mapping": {
                "type": "text",
                "fields": {
                  "keyword": {
                    "type": "keyword",
                    "ignore_above": 256
                  }
                }
              }
            }
          }
        ],
        "properties": {
          "@timestamp": {"type": "date"},
          "message": {"type": "text"},
          "log": {
            "properties": {
              "level": {"type": "keyword"},
              "file": {
                "properties": {
                  "path": {"type": "keyword"}
                }
              }
            }
          },
          "kubernetes": {
            "properties": {
              "namespace": {"type": "keyword"},
              "pod": {
                "properties": {
                  "name": {"type": "keyword"},
                  "uid": {"type": "keyword"}
                }
              },
              "container": {
                "properties": {
                  "name": {"type": "keyword"},
                  "image": {"type": "keyword"}
                }
              },
              "labels": {"type": "object", "dynamic": true},
              "node": {
                "properties": {
                  "name": {"type": "keyword"}
                }
              }
            }
          },
          "trace": {
            "properties": {
              "id": {"type": "keyword"}
            }
          },
          "response_code": {"type": "integer"},
          "request_time": {"type": "float"},
          "geoip": {
            "properties": {
              "location": {"type": "geo_point"}
            }
          }
        }
      }
    },
    "data_stream": {}
  }'

echo "ILM policy and index template created successfully"
```

### 4.4 Kibana Index Patterns, Dashboards, and Saved Searches

```bash
# Create Kibana index pattern via API
curl -X POST "http://localhost:5601/api/index_patterns/index_pattern" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "index_pattern": {
      "id": "k8s-logs",
      "title": "k8s-logs-*",
      "timeFieldName": "@timestamp",
      "fieldFormats": {
        "response_code": {
          "id": "color",
          "params": {
            "fieldType": "number",
            "colors": [
              {"range": "200:299", "text": "#00ff00", "background": "transparent"},
              {"range": "400:499", "text": "#ffaa00", "background": "transparent"},
              {"range": "500:599", "text": "#ff0000", "background": "transparent"}
            ]
          }
        }
      }
    }
  }'

# Create saved search for ERROR logs
curl -X POST "http://localhost:5601/api/saved_objects/search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "attributes": {
      "title": "All Error Logs",
      "description": "Shows all logs with ERROR level",
      "hits": 0,
      "columns": ["kubernetes.namespace", "kubernetes.pod.name", "kubernetes.container.name", "log.level", "message"],
      "sort": [["@timestamp", "desc"]],
      "kibanaSavedObjectMeta": {
        "searchSourceJSON": "{\"query\":{\"query_string\":{\"query\":\"log.level:error OR log.level:ERROR\"}},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
      }
    },
    "references": [
      {"id": "k8s-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
    ]
  }'

# Create Kibana dashboard for K8s log overview
curl -X POST "http://localhost:5601/api/saved_objects/dashboard" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "attributes": {
      "title": "Kubernetes Log Overview",
      "hits": 0,
      "description": "Overview of logs across all Kubernetes namespaces",
      "panelsJSON": "[]",
      "optionsJSON": "{\"darkTheme\":false}",
      "timeRestore": true,
      "timeTo": "now",
      "timeFrom": "now-1h",
      "refreshInterval": {"display":"30 seconds","pause":false,"value":30000},
      "kibanaSavedObjectMeta": {
        "searchSourceJSON": "{\"filter\":[],\"query\":{\"query\":\"*\",\"language\":\"kuery\"}}"
      }
    }
  }'
```

---

## 5. Integration with Existing Tools

### 5.1 Kubernetes: Collect Pod, System, and Audit Logs

```yaml
# Deploy Filebeat with comprehensive K8s log collection
# Add these additional log paths to Filebeat DaemonSet:

volumes:
  # Standard container logs
  - name: varlogcontainers
    hostPath:
      path: /var/log/containers
  # Pod logs (by pod UID)
  - name: varlogpods
    hostPath:
      path: /var/log/pods
  # Container runtime logs
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers
  # System journal logs
  - name: varlogsyslog
    hostPath:
      path: /var/log
  # Kubernetes audit logs
  - name: audit-logs
    hostPath:
      path: /var/log/kubernetes/audit

# In filebeat.yml, add these inputs:
filebeat.inputs:
  # System journal
  - type: journald
    id: everything
    seek: tail
    
  # Kubernetes audit logs
  - type: filestream
    id: kubernetes-audit
    paths:
      - /var/log/kubernetes/audit/*.log
    parsers:
      - ndjson:
          keys_under_root: true
    tags: ["kubernetes-audit"]
```

### 5.2 Jenkins: Ship Build Logs to ELK

```groovy
// Jenkinsfile - Send build logs to Elasticsearch
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                script {
                    // Build step
                    sh 'mvn clean package'
                }
            }
            post {
                always {
                    script {
                        // Send build result to ELK
                        def buildLog = currentBuild.rawBuild.getLog(1000).join('\n')
                        def payload = [
                            '@timestamp': new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
                            'jenkins.job': env.JOB_NAME,
                            'jenkins.build': env.BUILD_NUMBER,
                            'jenkins.result': currentBuild.result,
                            'jenkins.duration': currentBuild.duration,
                            'message': "Build ${env.BUILD_NUMBER} ${currentBuild.result}"
                        ]
                        
                        httpRequest(
                            url: "http://elasticsearch-es-http.elastic.svc.cluster.local:9200/jenkins-logs/_doc",
                            httpMode: 'POST',
                            contentType: 'APPLICATION_JSON',
                            requestBody: groovy.json.JsonOutput.toJson(payload),
                            authentication: 'elastic-credentials'
                        )
                    }
                }
            }
        }
    }
}
```

### 5.3 ArgoCD: Deployment Logs

```bash
# Filebeat automatically collects ArgoCD pod logs
# Add annotation to ArgoCD pods for structured parsing:
kubectl annotate pod -n argocd \
  $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].metadata.name}') \
  co.elastic.logs/json.keys_under_root="true" \
  co.elastic.logs/json.add_error_key="true"

# Create Kibana search for ArgoCD sync failures
# KQL query in Discover:
# kubernetes.namespace: argocd AND (message: "sync failed" OR message: "OutOfSync")
```

### 5.4 Grafana: Elasticsearch as Data Source

> The complete Grafana datasource API command for adding Elasticsearch (including all `jsonData` fields, `basicAuth`, and log field mapping) is documented in:
> **[grafana-complete-guide.md — Section 5.3 ELK: Elasticsearch Data Source for Log Correlation](grafana-complete-guide.md)**

---

## 6. Real-World Scenarios

### Scenario 1: Debug a CrashLoopBackOff Pod Using Logs

```bash
# Step 1: Identify the crashing pod
kubectl get pods -A | grep -E "CrashLoop|Error|0/1"
# NAMESPACE   NAME                    READY   STATUS             RESTARTS   AGE
# production  payment-api-7b8c9f-xyz  0/1     CrashLoopBackOff   8          15m

# Step 2: Search in Kibana for the pod's logs (even from previous crashes)
# Kibana Discover query:
# kubernetes.pod.name: "payment-api-7b8c9f-xyz" AND @timestamp > now-30m

# Step 3: Search for errors around the crash time
# KQL: kubernetes.pod.name: "payment-api*" AND log.level: error
# Time range: last 30 minutes

# Step 4: Use ELK API to query programmatically
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"match": {"kubernetes.pod.name": "payment-api"}},
          {"range": {"@timestamp": {"gte": "now-30m"}}},
          {"match": {"log.level": "error"}}
        ]
      }
    },
    "sort": [{"@timestamp": {"order": "desc"}}],
    "_source": ["@timestamp", "message", "kubernetes.pod.name", "kubernetes.container.name"],
    "size": 50
  }' | python3 -m json.tool

# Expected: Reveals root cause like:
# "message": "ERROR: Cannot connect to database: Connection refused (jdbc:postgresql://postgres:5432/paymentdb)"
# "message": "FATAL: Failed to initialize application context"
```

### Scenario 2: Search for Error Patterns Across All Pods

```bash
# Find all pods with connection timeout errors
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"match_phrase": {"message": "connection timeout"}},
          {"range": {"@timestamp": {"gte": "now-1h"}}}
        ]
      }
    },
    "aggs": {
      "by_service": {
        "terms": {
          "field": "kubernetes.labels.app.keyword",
          "size": 20
        }
      },
      "timeline": {
        "date_histogram": {
          "field": "@timestamp",
          "calendar_interval": "5m"
        }
      }
    },
    "size": 0
  }' | python3 -m json.tool

# Find all HTTP 500 errors across all services
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"range": {"response_code": {"gte": 500, "lt": 600}}},
          {"range": {"@timestamp": {"gte": "now-1h"}}}
        ]
      }
    },
    "aggs": {
      "errors_by_endpoint": {
        "terms": {"field": "request.keyword", "size": 20}
      },
      "errors_by_service": {
        "terms": {"field": "kubernetes.namespace.keyword", "size": 10}
      }
    },
    "sort": [{"@timestamp": {"order": "desc"}}],
    "size": 20
  }' | python3 -m json.tool

# Create Kibana alert for error spike
curl -X POST "http://localhost:5601/api/alerting/rule" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "name": "Error Rate Spike",
    "rule_type_id": ".es-query",
    "consumer": "alerts",
    "schedule": {"interval": "5m"},
    "params": {
      "index": ["k8s-logs-*"],
      "timeField": "@timestamp",
      "timeWindowSize": 5,
      "timeWindowUnit": "m",
      "threshold": [100],
      "thresholdComparator": ">",
      "esQuery": "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"log.level\":\"error\"}}]}}}"
    },
    "actions": [
      {
        "id": "<slack-connector-id>",
        "group": "threshold met",
        "params": {
          "message": "Error rate spike: {{context.value}} errors in last 5 minutes"
        }
      }
    ]
  }'
```

### Scenario 3: Setup Kubernetes Audit Log Monitoring

```bash
# Step 1: Enable audit logging on Minikube
minikube start \
  --extra-config=apiserver.audit-log-path=/var/log/kubernetes/audit/audit.log \
  --extra-config=apiserver.audit-log-maxage=7 \
  --extra-config=apiserver.audit-log-maxbackup=10 \
  --extra-config=apiserver.audit-log-maxsize=100 \
  --extra-config=apiserver.audit-policy-file=/etc/kubernetes/audit-policy.yaml

# Step 2: Create audit policy
cat > audit-policy.yaml << 'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all failed requests
  - level: RequestResponse
    omitStages:
      - RequestReceived
    users: []
    verbs: ["*"]
    resources: []
    namespaces: []
    nonResourceURLs: []

  # Log secret access (security monitoring)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
    verbs: ["get", "list", "watch"]

  # Log RBAC changes
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "clusterroles", "rolebindings", "clusterrolebindings"]
    verbs: ["create", "update", "patch", "delete"]

  # Omit system noise
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
      - group: ""
        resources: ["endpoints", "services", "services/status"]
EOF

# Step 3: Search audit logs in Elasticsearch
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"tags": "kubernetes-audit"}},
          {"range": {"@timestamp": {"gte": "now-1h"}}}
        ],
        "should": [
          {"term": {"responseStatus.code": 403}},
          {"term": {"responseStatus.code": 401}}
        ],
        "minimum_should_match": 1
      }
    },
    "aggs": {
      "denied_by_user": {
        "terms": {
          "field": "user.username.keyword",
          "size": 10
        }
      }
    },
    "sort": [{"@timestamp": {"order": "desc"}}],
    "size": 20
  }' | python3 -m json.tool
```

---

## 7. Verification & Testing

### Kibana Discover Verification

```bash
# Verify logs are flowing into Elasticsearch
curl -s "http://localhost:9200/_cat/indices/k8s-logs-*?v&s=index" \
  -u "elastic:$ES_PASSWORD"

# Check document count
curl -s "http://localhost:9200/k8s-logs-*/_count" \
  -u "elastic:$ES_PASSWORD" | python3 -m json.tool
# {"count": 45230, "_shards": {"total": 5, "successful": 5}}

# Check most recent log timestamp
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"sort": [{"@timestamp": {"order": "desc"}}], "size": 1, "_source": ["@timestamp", "message", "kubernetes.pod.name"]}' \
  | python3 -m json.tool
```

### Filebeat Health Check

```bash
# Check Filebeat pod logs
kubectl logs -n elastic -l beat.k8s.elastic.co/name=filebeat --tail=50

# Check Filebeat monitoring stats
curl -s "http://localhost:9200/.monitoring-beats-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match_all": {}}, "sort": [{"timestamp": {"order": "desc"}}], "size": 1}' \
  | python3 -m json.tool | grep -A5 "events"

# Check registry file (tracks file read positions)
kubectl exec -n elastic \
  $(kubectl get pod -n elastic -l beat.k8s.elastic.co/name=filebeat -o jsonpath='{.items[0].metadata.name}') \
  -- cat /usr/share/filebeat/data/registry/filebeat/data.json | \
  python3 -c "import json,sys; data=json.load(sys.stdin); print(f'Tracking {len(data)} log files')"
```

### Elasticsearch Cluster Health

```bash
# Check cluster health
curl -s "http://localhost:9200/_cluster/health?pretty" \
  -u "elastic:$ES_PASSWORD"
# {
#   "cluster_name": "elasticsearch",
#   "status": "green",              <-- should be green
#   "number_of_nodes": 1,
#   "number_of_data_nodes": 1,
#   "active_shards": 15,
#   "unassigned_shards": 0          <-- should be 0
# }

# Check index statistics
curl -s "http://localhost:9200/_stats?pretty" \
  -u "elastic:$ES_PASSWORD" | \
  python3 -c "
import json, sys
stats = json.load(sys.stdin)
total = stats['_all']['total']
print(f\"Total docs: {total['docs']['count']:,}\")
print(f\"Total size: {total['store']['size_in_bytes'] / 1024 / 1024:.1f} MB\")
"

# Test a search query
curl -X POST "http://localhost:9200/k8s-logs-*/_search?pretty" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"log.level": "error"}}, "size": 5}'
```

---

## 8. Troubleshooting Guide

### Issue 1: Elasticsearch Pod OOMKilled

**Symptoms:** Elasticsearch pod crashes with `OOMKilled` status

**Solution:**
```bash
# Check current memory usage
kubectl top pod -n elastic -l elasticsearch.k8s.elastic.co/cluster-name=elasticsearch

# Reduce JVM heap size (should be 50% of container memory limit)
kubectl patch elasticsearch -n elastic elasticsearch --type=merge -p '{
  "spec": {
    "nodeSets": [{
      "name": "default",
      "podTemplate": {
        "spec": {
          "containers": [{
            "name": "elasticsearch",
            "env": [{"name": "ES_JAVA_OPTS", "value": "-Xms256m -Xmx256m"}],
            "resources": {
              "requests": {"memory": "1Gi"},
              "limits": {"memory": "2Gi"}
            }
          }]
        }
      }
    }]
  }
}'
```

### Issue 2: Filebeat Not Collecting Logs

**Symptoms:** No new documents in Elasticsearch, Filebeat running but silent

**Solution:**
```bash
# Check Filebeat logs for errors
kubectl logs -n elastic \
  $(kubectl get pod -n elastic -l beat.k8s.elastic.co/name=filebeat -o jsonpath='{.items[0].metadata.name}') \
  | grep -E "ERROR|WARN|Failed"

# Check if Filebeat can reach Elasticsearch
kubectl exec -n elastic \
  $(kubectl get pod -n elastic -l beat.k8s.elastic.co/name=filebeat -o jsonpath='{.items[0].metadata.name}') \
  -- wget -O- http://elasticsearch-es-http.elastic.svc.cluster.local:9200

# Verify Filebeat RBAC permissions
kubectl auth can-i get pods \
  --as=system:serviceaccount:elastic:filebeat

# Check volume mounts exist
kubectl exec -n elastic \
  $(kubectl get pod -n elastic -l beat.k8s.elastic.co/name=filebeat -o jsonpath='{.items[0].metadata.name}') \
  -- ls /var/log/containers/ | head -5
```

### Issue 3: Elasticsearch Red/Yellow Status

**Symptoms:** `_cluster/health` returns `red` or `yellow`

**Solution:**
```bash
# Check unassigned shards
curl -s "http://localhost:9200/_cluster/allocation/explain?pretty" \
  -u "elastic:$ES_PASSWORD"

# For single-node clusters, yellow status is normal (no replica placement possible)
# Set replicas to 0 for all indices
curl -X PUT "http://localhost:9200/_settings" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"index.number_of_replicas": 0}'

# Check disk usage
curl -s "http://localhost:9200/_cat/allocation?v" \
  -u "elastic:$ES_PASSWORD"
```

### Issue 4: Kibana Cannot Connect to Elasticsearch

**Symptoms:** Kibana shows "Kibana server is not ready yet"

**Solution:**
```bash
# Check Kibana logs
kubectl logs -n elastic \
  $(kubectl get pod -n elastic -l kibana.k8s.elastic.co/name=kibana -o jsonpath='{.items[0].metadata.name}') | \
  grep -E "ERROR|Unable|Failed" | tail -20

# Verify Elasticsearch is healthy
curl -s "http://localhost:9200/_cluster/health" \
  -u "elastic:$ES_PASSWORD" | python3 -m json.tool

# Check Kibana status
kubectl get kibana -n elastic kibana -o yaml | grep -A10 "status:"
```

### Issue 5: Too Many Shards Warning

**Symptoms:** "Cluster health is yellow" with `too_many_shards_on_node` warning

**Solution:**
```bash
# Check current shard count
curl -s "http://localhost:9200/_cat/shards?v" \
  -u "elastic:$ES_PASSWORD" | wc -l

# Delete old indices
curl -X DELETE "http://localhost:9200/k8s-logs-*2024.01.*" \
  -u "elastic:$ES_PASSWORD"

# Increase max shards per node (temporary fix)
curl -X PUT "http://localhost:9200/_cluster/settings" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"persistent": {"cluster.max_shards_per_node": 2000}}'

# Better: Ensure ILM policy is working to delete old indices
curl -s "http://localhost:9200/_ilm/policy/k8s-logs-policy" \
  -u "elastic:$ES_PASSWORD" | python3 -m json.tool
```

### Issue 6: Logs Showing with Wrong Timestamp

**Symptoms:** All logs show the same timestamp or timestamps are in the future/past

**Solution:**
```bash
# Check Filebeat time parsing in a log entry
curl -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"sort": [{"@timestamp": "desc"}], "size": 1, "_source": ["@timestamp", "message"]}' \
  | python3 -m json.tool

# Ensure Filebeat timezone is UTC
# Add to filebeat.yml:
# processors:
#   - timestamp:
#       field: timestamp
#       layouts:
#         - '2006-01-02T15:04:05Z07:00'
#       timezone: 'UTC'
```

### Issue 7: High Elasticsearch CPU Usage

**Symptoms:** Elasticsearch consuming >80% CPU

**Solution:**
```bash
# Check hot threads
curl -s "http://localhost:9200/_nodes/hot_threads" \
  -u "elastic:$ES_PASSWORD"

# Reduce indexing buffer
curl -X PUT "http://localhost:9200/_cluster/settings" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"persistent": {"indices.memory.index_buffer_size": "5%"}}'

# Reduce refresh interval (less frequent merges = less CPU)
curl -X PUT "http://localhost:9200/k8s-logs-*/_settings" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"index.refresh_interval": "60s"}'
```

### Issue 8: Kibana Dashboards Not Loading

**Symptoms:** Kibana shows spinner indefinitely or "No results found"

**Solution:**
```bash
# Check if index pattern matches existing indices
curl -s "http://localhost:9200/_cat/indices?v&h=index,docs.count,store.size" \
  -u "elastic:$ES_PASSWORD" | grep k8s-logs

# Refresh field list in Kibana index pattern
curl -X POST "http://localhost:5601/api/index_patterns/index_pattern/k8s-logs/fields" \
  -u "elastic:$ES_PASSWORD" \
  -H "kbn-xsrf: true"

# Check for query errors in Kibana dev tools
# Stack Management > Dev Tools
# GET k8s-logs-*/_count
```

### Issue 9: Logstash Pipeline Dropping Events

**Symptoms:** Logstash shows "pipeline input workers are overwhelmed"

**Solution:**
```bash
# Check Logstash pipeline stats
curl -s http://localhost:9600/_node/stats/pipelines | python3 -m json.tool | \
  grep -A5 "dropped"

# Increase pipeline workers and batch size
# In logstash.yml:
# pipeline.workers: 4
# pipeline.batch.size: 250
# pipeline.batch.delay: 50

# Add persistent queue to handle bursts
# queue.type: persisted
# queue.max_bytes: 2gb
```

### Issue 10: Elasticsearch Disk Full

**Symptoms:** Elasticsearch read-only mode, indexing stopped with `cluster_block_exception`

**Solution:**
```bash
# Check disk usage
curl -s "http://localhost:9200/_cat/allocation?v" \
  -u "elastic:$ES_PASSWORD"

# Remove read-only block (after freeing space)
curl -X PUT "http://localhost:9200/_all/_settings" \
  -u "elastic:$ES_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"index.blocks.read_only_allow_delete": null}'

# Delete oldest indices
# First, see oldest indices:
curl -s "http://localhost:9200/_cat/indices?v&s=creation.date:asc&h=index,creation.date.string,store.size,docs.count" \
  -u "elastic:$ES_PASSWORD" | head -10

# Delete them
curl -X DELETE "http://localhost:9200/k8s-logs-production-2024.01.01" \
  -u "elastic:$ES_PASSWORD"

# Long-term: Ensure ILM policy is configured correctly
curl -s "http://localhost:9200/_ilm/policy" \
  -u "elastic:$ES_PASSWORD" | python3 -m json.tool
```

---

## 9. ELK Cheat Sheet

### Elasticsearch API Quick Reference

| Operation | Command |
|-----------|---------|
| Cluster health | `GET /_cluster/health` |
| List indices | `GET /_cat/indices?v` |
| Index count | `GET /index-name/_count` |
| Search all | `GET /index-name/_search` |
| Delete index | `DELETE /index-name` |
| Index settings | `GET /index-name/_settings` |
| Index mapping | `GET /index-name/_mapping` |
| Node stats | `GET /_nodes/stats` |
| Hot threads | `GET /_nodes/hot_threads` |
| ILM explain | `GET /index-name/_ilm/explain` |
| Force rollover | `POST /alias-name/_rollover` |
| Flush index | `POST /index-name/_flush` |

### Kibana KQL (Kibana Query Language)

| Query | Description |
|-------|-------------|
| `log.level: error` | Exact field match |
| `message: "connection refused"` | Phrase search |
| `response_code >= 500` | Numeric comparison |
| `kubernetes.namespace: production` | Filter by namespace |
| `NOT kubernetes.container.name: sidecar` | Exclusion |
| `log.level: (error OR warn)` | Multiple values |
| `kubernetes.pod.name: payment-*` | Wildcard |
| `message: timeout AND kubernetes.namespace: production` | AND logic |
| `@timestamp >= "2024-01-15T00:00:00Z"` | Time filter |
| `exists: trace.id` | Field exists check |

### Filebeat Log Annotation Hints

| Annotation | Effect |
|-----------|--------|
| `co.elastic.logs/enabled: "true"` | Enable log collection |
| `co.elastic.logs/enabled: "false"` | Disable log collection |
| `co.elastic.logs/multiline.type: pattern` | Enable multiline |
| `co.elastic.logs/multiline.pattern: '^[0-9]'` | Multiline pattern |
| `co.elastic.logs/json.keys_under_root: "true"` | Parse JSON logs |
| `co.elastic.logs/module: nginx` | Use Filebeat module |
| `co.elastic.logs/fileset.stdout: access` | Map stdout to module fileset |

### Common Elasticsearch Queries

```json
// Search by field
{"query": {"term": {"kubernetes.namespace.keyword": "production"}}}

// Full text search
{"query": {"match": {"message": "connection refused"}}}

// Date range
{"query": {"range": {"@timestamp": {"gte": "now-1h", "lte": "now"}}}}

// Boolean combination
{"query": {"bool": {"must": [{"match": {"log.level": "error"}}, {"range": {"@timestamp": {"gte": "now-15m"}}}]}}}

// Aggregation: count errors by service
{"aggs": {"by_service": {"terms": {"field": "kubernetes.labels.app.keyword"}}}, "query": {"match": {"log.level": "error"}}, "size": 0}

// Top error messages
{"aggs": {"top_errors": {"terms": {"field": "message.keyword", "size": 10}}}, "query": {"match": {"log.level": "error"}}, "size": 0}
```

---

*Last updated: 2024 | Maintained by DevOps Team*
