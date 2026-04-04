# AIOps for DevOps: Complete Guide with Dynatrace

## Table of Contents
1. [Overview & Why AIOps](#1-overview--why-aiops)
2. [Tool Selection: Dynatrace vs Alternatives](#2-tool-selection-dynatrace-vs-alternatives)
3. [Local Setup: Dynatrace on Minikube/K8s](#3-local-setup-dynatrace-on-minikubek8s)
4. [Online/Cloud Setup: Dynatrace SaaS](#4-onlinecloud-setup-dynatrace-saas)
5. [Configuration Deep Dive](#5-configuration-deep-dive)
6. [Integration with Existing Tools](#6-integration-with-existing-tools)
7. [Real-World Scenarios](#7-real-world-scenarios)
8. [Verification & Testing](#8-verification--testing)
9. [Troubleshooting Guide](#9-troubleshooting-guide)
10. [Cheat Sheet](#10-cheat-sheet)

---

## 1. Overview & Why AIOps

### What is AIOps?

AIOps (Artificial Intelligence for IT Operations) applies machine learning, big data analytics, and AI algorithms to automate and enhance IT operations. It correlates vast streams of operational data — logs, metrics, events, traces — to surface actionable insights, reduce noise, and trigger automated remediation.

### Core AIOps Capabilities

#### Anomaly Detection
Traditional monitoring fires alerts when metrics cross static thresholds. AIOps learns your system's normal behavior and detects deviations automatically:
- Baseline CPU usage per service, time-of-day, day-of-week
- Automatic detection of memory leaks before OOM kills
- Response time degradation detection (not just "is it up")
- Throughput drops relative to expected traffic patterns

#### Auto-Remediation
When an anomaly is detected, AIOps platforms can trigger automated responses:
- Restart crashed pods via kubectl
- Scale up deployments when memory pressure is detected
- Roll back bad deployments that degrade SLOs
- Execute Ansible runbooks for complex remediation

#### Alert Correlation
AIOps reduces alert storms by grouping related alerts into a single "Problem":
- One JVM memory issue might trigger 50 individual alerts (high GC, slow response, pod restarts)
- AIOps groups these into: "Problem: Memory pressure on payment-service" with root cause analysis
- Reduces Mean Time to Detect (MTTD) and Mean Time to Resolve (MTTR)

#### Deployment Impact Analysis
- AI classifies each deployment as "good" or "bad" based on post-deploy metric changes
- Automatic rollback triggers when SLO breach is detected post-deploy
- Causal analysis: which service change caused which downstream impact

### Why Your DevOps Team Needs AIOps

| Without AIOps | With AIOps |
|---------------|------------|
| 200+ alerts/day, manual triage | 5-10 problems/day, auto-correlated |
| Hours to find root cause | Minutes with AI-assisted root cause |
| Manual deployment validation | Auto quality gate with AI scoring |
| Static thresholds miss slow leaks | Dynamic baselines catch all anomalies |
| On-call fatigue from noise | Meaningful, actionable alerts only |

### Key Metrics AIOps Improves
- **MTTD** (Mean Time to Detect): From hours to minutes
- **MTTR** (Mean Time to Resolve): From hours to under 30 minutes
- **Alert Noise Reduction**: Typically 90%+ reduction
- **Deployment Quality**: Catch 95%+ of bad deploys before full rollout

---

## 2. Tool Selection: Dynatrace vs Alternatives

### Why Dynatrace for This Stack

Dynatrace is chosen as the primary AIOps platform for this DevOps project because:

1. **Native Kubernetes monitoring** — OneAgent auto-discovers pods, namespaces, workloads
2. **Jenkins plugin** — First-class integration, deployment events, quality gates
3. **Davis AI** — Purpose-built AI engine for IT operations, causal AI (not just correlation)
4. **Full-stack observability** — Infrastructure, APM, logs, user experience in one platform
5. **Auto-instrumentation** — Zero-code instrumentation for Node.js, Java, Python
6. **Free trial** — 15-day full-featured trial, plus free forever tier

### Comparison Table

| Feature | Dynatrace | Moogsoft | PagerDuty |
|---------|-----------|----------|-----------|
| **Primary Use** | Full-stack observability + AIOps | Alert correlation & AIOps | Incident management + AIOps |
| **AI Engine** | Davis AI (causal) | Moogsoft Correlation | AIOps add-on |
| **K8s Integration** | Native, auto-discovery | Via integrations | Via integrations |
| **Jenkins Plugin** | Official, feature-rich | Limited | Moderate |
| **Auto-instrumentation** | Yes (OneAgent) | No | No |
| **Deployment Events** | Built-in | Manual | Manual |
| **Free Tier** | Yes (limited) | No | No |
| **Pricing Model** | Per host/DEM unit | Per event | Per user |
| **Root Cause AI** | Topology-based causal AI | Event clustering ML | Alert grouping |
| **Auto-Remediation** | Built-in runbooks | Via integrations | Via runbooks |
| **Prometheus Ingest** | Yes, native | Yes, via connector | Limited |
| **Setup Complexity** | Low (OneAgent) | Medium | Low |

### When to Choose Alternatives

**Moogsoft** — Better choice when:
- You already have multiple monitoring tools and need to aggregate alerts
- Primary need is noise reduction across heterogeneous environments
- You want SaaS-based event correlation without APM

**PagerDuty** — Better choice when:
- Primary focus is on-call scheduling and incident response workflow
- You need advanced escalation policies
- Team-centric incident management (who gets paged, runbooks, postmortems)

**Recommendation**: Use Dynatrace as primary observability + AIOps, PagerDuty for on-call management if your team uses it. They integrate well together.

---

## 3. Local Setup: Dynatrace on Minikube/K8s

### Prerequisites
```bash
# Verify Minikube is running
minikube status

# Verify kubectl access
kubectl cluster-info

# Check available resources (Dynatrace needs at least 4GB RAM for Minikube)
minikube config view
```

### Step 1: Start Minikube with Sufficient Resources
```bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --kubernetes-version=v1.28.0

# Verify
kubectl get nodes
```

### Step 2: Get Dynatrace Free Trial

1. Go to https://www.dynatrace.com/trial/
2. Sign up with your email
3. Choose "Dynatrace SaaS" (cloud-hosted, no local install)
4. Note your **Environment ID** (format: `abc12345`)
5. Note your **API Token** (Settings → Access Tokens → Generate new token)

Required API token permissions:
- `metrics.ingest`
- `logs.ingest`
- `events.ingest`
- `DataExport`
- `ReadConfig`
- `WriteConfig`
- `PaaSIntegration`

### Step 3: Create Kubernetes Namespace and Secret
```bash
# Create namespace
kubectl create namespace dynatrace

# Create secret with your Dynatrace credentials
kubectl create secret generic dynakube \
  --namespace dynatrace \
  --from-literal=apiToken=<YOUR_API_TOKEN> \
  --from-literal=dataIngestToken=<YOUR_DATA_INGEST_TOKEN>

# Verify
kubectl get secret dynakube -n dynatrace
```

### Step 4: Install Dynatrace Operator via Helm
```bash
# Add Dynatrace Helm repo
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update

# Install Dynatrace Operator
helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --atomic

# Verify operator is running
kubectl get pods -n dynatrace
kubectl get crd | grep dynatrace
```

### Step 5: Deploy DynaKube Custom Resource

Create `dynakube.yaml`:
```yaml
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
  annotations:
    feature.dynatrace.com/automatic-kubernetes-api-monitoring: "true"
spec:
  # Dynatrace API endpoint
  apiUrl: https://<YOUR_ENVIRONMENT_ID>.live.dynatrace.com/api

  # Skip TLS verification (not recommended for production)
  skipCertCheck: false

  # OneAgent configuration - monitors each node
  oneAgent:
    classicFullStack:
      tolerations:
        - effect: NoSchedule
          key: node-role.kubernetes.io/master
          operator: Exists
      # Resource limits for OneAgent DaemonSet
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1.5Gi
      # Environment variables for OneAgent
      env:
        - name: ONEAGENT_ENABLE_VOLUME_STORAGE
          value: "true"

  # ActiveGate for routing and data collection
  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
      - dynatrace-api
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1
        memory: 1.5Gi
    # TLS configuration
    tlsSecretName: activegatecert

  # Kubernetes monitoring settings
  metadataEnrichment:
    enabled: true
    namespaceSelector:
      matchLabels:
        monitor: "true"
```

Apply the configuration:
```bash
kubectl apply -f dynakube.yaml

# Watch deployment
kubectl get dynakube -n dynatrace -w
kubectl get pods -n dynatrace -w
```

### Step 6: OneAgent DaemonSet YAML (Manual Deployment)

If not using the Operator, deploy OneAgent as a DaemonSet:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: oneagent
  namespace: dynatrace
spec:
  selector:
    matchLabels:
      app: oneagent
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: oneagent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
      hostPID: true
      hostIPC: true
      hostNetwork: true
      serviceAccountName: dynatrace-oneagent
      containers:
        - name: oneagent
          image: docker.io/dynatrace/oneagent:latest
          env:
            - name: ONEAGENT_INSTALLER_SCRIPT_URL
              value: "https://<YOUR_ENV_ID>.live.dynatrace.com/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=<API_TOKEN>&arch=x86&flavor=default"
            - name: ONEAGENT_ENABLE_VOLUME_STORAGE
              value: "true"
            - name: ONEAGENT_INSTALLER_DOWNLOAD_TOKEN
              valueFrom:
                secretKeyRef:
                  name: oneagent
                  key: tokens
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1.5Gi
          securityContext:
            privileged: true
            runAsUser: 0
          volumeMounts:
            - mountPath: /mnt/root
              name: host-root
      volumes:
        - name: host-root
          hostPath:
            path: /
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dynatrace-oneagent
  namespace: dynatrace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dynatrace-oneagent
rules:
  - apiGroups: [""]
    resources: ["nodes", "pods", "namespaces", "services", "endpoints", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dynatrace-oneagent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dynatrace-oneagent
subjects:
  - kind: ServiceAccount
    name: dynatrace-oneagent
    namespace: dynatrace
```

### Step 7: ActiveGate Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynatrace-activegate
  namespace: dynatrace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: activegate
  template:
    metadata:
      labels:
        app: activegate
    spec:
      containers:
        - name: activegate
          image: docker.io/dynatrace/activegate:latest
          env:
            - name: DT_CAPABILITIES
              value: "MSIauth,MSIAuthentication,DynatraceModuleUpdate,kubernetes_monitoring,metrics_ingest"
            - name: DT_ID_SEED_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: DT_ID_SEED_K8S_CLUSTER_ID
              value: "minikube-local"
            - name: DT_SERVER
              value: "https://<YOUR_ENV_ID>.live.dynatrace.com/communication"
            - name: DT_TENANT
              value: "<YOUR_ENV_ID>"
            - name: DT_TOKEN_PATH
              value: "/var/lib/dynatrace/secrets/tokens/tenant-token"
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1
              memory: 1.5Gi
          ports:
            - containerPort: 9999
              protocol: TCP
          volumeMounts:
            - mountPath: /var/lib/dynatrace/secrets/tokens
              name: tenanttoken
              readOnly: true
      volumes:
        - name: tenanttoken
          secret:
            secretName: dynakube
---
apiVersion: v1
kind: Service
metadata:
  name: dynatrace-activegate
  namespace: dynatrace
spec:
  selector:
    app: activegate
  ports:
    - port: 9999
      targetPort: 9999
      protocol: TCP
  type: ClusterIP
```

### Verify Local Setup
```bash
# Check all Dynatrace pods are running
kubectl get pods -n dynatrace

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# dynakube-activegate-xxx               1/1     Running   0          2m
# dynakube-oneagent-xxx (per node)     1/1     Running   0          2m
# dynatrace-operator-xxx                1/1     Running   0          5m

# Check operator logs
kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator --tail=50

# Check OneAgent logs
kubectl logs -n dynatrace -l app=oneagent --tail=50
```

---

## 4. Online/Cloud Setup: Dynatrace SaaS

### Dynatrace SaaS Architecture (Cloud-Native)

In SaaS mode, Dynatrace manages all backend infrastructure. You only deploy:
- **OneAgent** on your hosts/pods (data collection)
- **ActiveGate** (optional, for routing/proxying in VPC environments)

### Quick SaaS Setup for AKS/EKS/GKE

```bash
# For AKS (Azure Kubernetes Service)
# First, get AKS credentials
az aks get-credentials --resource-group myRG --name myAKSCluster

# Install Dynatrace Operator
kubectl create namespace dynatrace
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update

helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --set installCRD=true \
  --set platform=kubernetes

# Create secrets
kubectl create secret generic dynakube \
  --namespace dynatrace \
  --from-literal=apiToken=${DYNATRACE_API_TOKEN} \
  --from-literal=dataIngestToken=${DYNATRACE_INGEST_TOKEN}
```

### SaaS DynaKube for Cloud Clusters
```yaml
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
spec:
  apiUrl: https://<ENV_ID>.live.dynatrace.com/api

  # Cloud-native full stack (recommended for cloud)
  oneAgent:
    cloudNativeFullStack:
      # Resource overhead per node
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1Gi
      # Inject into all namespaces
      namespaceSelector: {}

  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
      - metrics-ingest
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1
        memory: 1Gi

  # Enable Kubernetes monitoring
  kubernetesMonitoring:
    enabled: true
```

---

## 5. Configuration Deep Dive

### Dynatrace Operator on Kubernetes

The Dynatrace Operator manages the lifecycle of OneAgent and ActiveGate deployments:

```bash
# Check operator status
kubectl get dynakube -n dynatrace -o yaml

# Get operator events
kubectl describe dynakube dynakube -n dynatrace

# Update operator
helm upgrade dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --reuse-values
```

### Auto-Instrumentation: Node.js Applications

Dynatrace OneAgent auto-instruments Node.js without code changes. For explicit configuration:

```javascript
// Optional: Dynatrace SDK for custom business metrics
const Dynatrace = require('@dynatrace/oneagent-sdk');
const api = Dynatrace.createInstance();

// Create custom service for better topology
const messagingSystem = api.traceIncomingMessageProcess({
  vendorName: 'RabbitMQ',
  destinationName: 'orders-queue',
  destinationType: Dynatrace.MessageSystemDestinationType.QUEUE
});

messagingSystem.start();
try {
  // Process message
  processOrder(message);
  messagingSystem.end();
} catch (err) {
  messagingSystem.error(err.message);
  messagingSystem.end();
}
```

Kubernetes annotation for auto-instrumentation:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodejs-app
  namespace: production
spec:
  template:
    metadata:
      annotations:
        # Enable OneAgent injection
        oneagent.dynatrace.com/inject: "true"
        # Set custom service name
        oneagent.dynatrace.com/technologies: "nodejs"
        # Optional: set deployment group
        metadata.dynatrace.com/dt.deployment.stage: "production"
```

### Auto-Instrumentation: Java Applications

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-app
  namespace: production
spec:
  template:
    metadata:
      annotations:
        oneagent.dynatrace.com/inject: "true"
        oneagent.dynatrace.com/technologies: "java"
    spec:
      containers:
        - name: java-app
          image: my-java-app:latest
          env:
            # Dynatrace will inject -javaagent automatically
            - name: DT_RELEASE_VERSION
              value: "1.2.3"
            - name: DT_RELEASE_BUILD_VERSION
              value: "build-456"
            - name: DT_RELEASE_STAGE
              value: "production"
            - name: DT_RELEASE_PRODUCT
              value: "payment-service"
```

### Alerting Profiles

Configure via Dynatrace API:
```bash
# Create alerting profile via API
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/alertingProfiles" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Production Critical",
    "rules": [
      {
        "severityLevel": "AVAILABILITY",
        "tagFilters": [
          {
            "includeMode": "INCLUDE_ALL",
            "tagFilters": [
              {
                "context": "CONTEXTLESS",
                "key": "env",
                "value": "production"
              }
            ]
          }
        ],
        "delayInMinutes": 0
      },
      {
        "severityLevel": "PERFORMANCE",
        "tagFilters": [
          {
            "includeMode": "INCLUDE_ALL",
            "tagFilters": []
          }
        ],
        "delayInMinutes": 5
      }
    ],
    "managementZoneId": null,
    "eventTypeFilters": []
  }'
```

### Problem Notifications (Slack Integration via API)
```bash
# Configure problem notification
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/notifications" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "SLACK",
    "name": "Production Alerts Slack",
    "alertingProfile": "<ALERTING_PROFILE_ID>",
    "active": true,
    "url": "https://hooks.slack.com/services/T.../B.../xxx",
    "channel": "#production-alerts",
    "message": "{ProblemTitle}\n{ProblemDetailsHTML}"
  }'
```

### Auto-Remediation Runbooks

Dynatrace Workflows (formerly Runbooks) can trigger kubectl commands via webhook:

```yaml
# Example: Auto-remediation webhook receiver (deploy as K8s Job)
apiVersion: v1
kind: ConfigMap
metadata:
  name: remediation-scripts
  namespace: dynatrace-remediation
data:
  restart-deployment.sh: |
    #!/bin/bash
    # Called by Dynatrace webhook on OOMKill detection
    NAMESPACE=$1
    DEPLOYMENT=$2
    
    echo "Restarting deployment $DEPLOYMENT in namespace $NAMESPACE"
    kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
    
    # Wait for rollout
    kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s
    
    echo "Remediation complete"
  
  scale-deployment.sh: |
    #!/bin/bash
    # Scale up when memory pressure detected
    NAMESPACE=$1
    DEPLOYMENT=$2
    CURRENT_REPLICAS=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
    
    kubectl scale deployment/$DEPLOYMENT -n $NAMESPACE --replicas=$NEW_REPLICAS
    echo "Scaled $DEPLOYMENT from $CURRENT_REPLICAS to $NEW_REPLICAS replicas"
```

Webhook receiver deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynatrace-remediation-webhook
  namespace: dynatrace-remediation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: remediation-webhook
  template:
    metadata:
      labels:
        app: remediation-webhook
    spec:
      serviceAccountName: remediation-sa
      containers:
        - name: webhook
          image: python:3.11-slim
          command: ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=8080"]
          env:
            - name: FLASK_APP
              value: "/app/webhook.py"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: app-code
              mountPath: /app
      volumes:
        - name: scripts
          configMap:
            name: remediation-scripts
            defaultMode: 0755
        - name: app-code
          configMap:
            name: webhook-app
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: remediation-sa
  namespace: dynatrace-remediation
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: remediation-role
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments/scale"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: remediation-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: remediation-role
subjects:
  - kind: ServiceAccount
    name: remediation-sa
    namespace: dynatrace-remediation
```

### AI-Driven Anomaly Detection Settings

Configure detection sensitivity via API:
```bash
# Set custom anomaly detection thresholds for a service
curl -X PUT "https://<ENV_ID>.live.dynatrace.com/api/v2/settings/objects" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemaId": "builtin:anomaly-detection.services",
    "scope": "SERVICE-<SERVICE_ID>",
    "value": {
      "failureRate": {
        "enabled": true,
        "method": "FIXED",
        "fixedDetection": {
          "sensitivityType": "LOW",
          "threshold": 5,
          "requestsPerMinute": 10,
          "minutesAbnormalState": 5
        }
      },
      "responseTime": {
        "enabled": true,
        "method": "ADAPTIVE",
        "adaptiveDetection": {
          "loadBaseline": "FIFTEEN_MINUTES"
        }
      },
      "trafficDrop": {
        "enabled": true,
        "method": "ADAPTIVE",
        "adaptiveDetection": {
          "trafficDropPercent": 50
        }
      },
      "trafficSpike": {
        "enabled": false
      }
    }
  }'
```

### Davis AI Concepts

Davis is Dynatrace's causal AI engine. Key concepts:

**Topology-Based Analysis**: Davis understands service dependencies from auto-discovered topology. When payment-service response time degrades, Davis traces back to database connection pool exhaustion.

**Baselining**: Davis builds behavior models per:
- Time of day (peak vs off-peak)
- Day of week (weekday vs weekend)
- Seasonal trends (holiday traffic)

**Problem Detection Flow**:
```
Metric anomaly detected
    → Davis checks: Is this part of a larger issue?
    → Cross-references: Deployments? Infrastructure changes? Upstream services?
    → Groups related events into ONE Problem
    → Determines: Root cause entity, impacted entities
    → Triggers: Notification, auto-remediation workflow
```

**Davis AI Settings**:
```bash
# Enable Davis for a specific management zone
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v2/settings/objects" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemaId": "builtin:davis-ai.config",
    "value": {
      "enableAnomalyDetection": true,
      "enableAutoProblems": true,
      "enableRootCauseAnalysis": true,
      "topologyLearningEnabled": true,
      "baselineLearningMinutes": 60
    }
  }'
```

---

## 6. Integration with Existing Tools

### Jenkins Integration

#### Install Dynatrace Jenkins Plugin
```groovy
// In Jenkins: Manage Jenkins → Plugin Manager → Available
// Search: "Dynatrace" → Install "Dynatrace Plugin"
```

Configure credentials in Jenkins:
```
Manage Jenkins → Credentials → System → Global credentials
→ Add: "Dynatrace API Token" (Secret text)
  ID: dynatrace-api-token
  Secret: <your-api-token>

→ Add: "Dynatrace Server URL"
  ID: dynatrace-server-url
  Value: https://<ENV_ID>.live.dynatrace.com
```

#### Jenkinsfile with Dynatrace Integration
```groovy
pipeline {
  agent any

  environment {
    DT_API_TOKEN    = credentials('dynatrace-api-token')
    DT_SERVER       = credentials('dynatrace-server-url')
    APP_NAME        = 'payment-service'
    APP_VERSION     = "${BUILD_NUMBER}"
    DT_STAGE        = 'production'
  }

  stages {
    stage('Build') {
      steps {
        sh 'docker build -t ${APP_NAME}:${APP_VERSION} .'
      }
    }

    stage('Push Deployment Event') {
      steps {
        script {
          // Push deployment event to Dynatrace BEFORE deploying
          sh """
            curl -X POST "${DT_SERVER}/api/v1/events" \\
              -H "Authorization: Api-Token ${DT_API_TOKEN}" \\
              -H "Content-Type: application/json" \\
              -d '{
                "eventType": "CUSTOM_DEPLOYMENT",
                "attachRules": {
                  "tagRule": [
                    {
                      "meTagFilters": [
                        {
                          "context": "CONTEXTLESS",
                          "key": "app",
                          "value": "${APP_NAME}"
                        }
                      ]
                    }
                  ]
                },
                "deploymentName": "${APP_NAME}",
                "deploymentVersion": "${APP_VERSION}",
                "deploymentProject": "devops-project",
                "ciBackLink": "${BUILD_URL}",
                "source": "Jenkins",
                "customProperties": {
                  "Jenkins Build Number": "${BUILD_NUMBER}",
                  "Git Commit": "${GIT_COMMIT}",
                  "Branch": "${GIT_BRANCH}"
                }
              }'
          """
        }
      }
    }

    stage('Deploy') {
      steps {
        sh 'kubectl set image deployment/${APP_NAME} ${APP_NAME}=${APP_NAME}:${APP_VERSION} -n production'
        sh 'kubectl rollout status deployment/${APP_NAME} -n production --timeout=120s'
      }
    }

    stage('Dynatrace Quality Gate') {
      steps {
        script {
          sleep(time: 120, unit: 'SECONDS') // Wait for metrics to stabilize

          // Check for open problems related to this service
          def problems = sh(
            returnStdout: true,
            script: """
              curl -s -X GET "${DT_SERVER}/api/v2/problems?from=now-5m&entitySelector=tag%3A${APP_NAME}" \\
                -H "Authorization: Api-Token ${DT_API_TOKEN}" | \\
                python3 -c "import json,sys; data=json.load(sys.stdin); print(data['totalCount'])"
            """
          ).trim()

          echo "Open problems after deployment: ${problems}"

          if (problems.toInteger() > 0) {
            echo "Quality gate FAILED: ${problems} problem(s) detected after deployment"
            
            // Auto-rollback
            sh 'kubectl rollout undo deployment/${APP_NAME} -n production'
            
            error("Deployment rolled back due to Dynatrace quality gate failure")
          } else {
            echo "Quality gate PASSED: No problems detected"
          }
        }
      }
    }
  }

  post {
    failure {
      // Push failure event to Dynatrace
      sh """
        curl -X POST "${DT_SERVER}/api/v1/events" \\
          -H "Authorization: Api-Token ${DT_API_TOKEN}" \\
          -H "Content-Type: application/json" \\
          -d '{
            "eventType": "CUSTOM_ANNOTATION",
            "attachRules": {"tagRule": [{"meTagFilters": [{"context":"CONTEXTLESS","key":"app","value":"${APP_NAME}"}]}]},
            "annotationType": "DEPLOYMENT_FAILED",
            "annotationDescription": "Jenkins build ${BUILD_NUMBER} failed",
            "source": "Jenkins"
          }'
      """ 
    }
  }
}
```

### Kubernetes Monitoring

Dynatrace automatically discovers and monitors:
- All pods, namespaces, deployments, replicasets
- Node CPU, memory, disk, network
- Pod CPU throttling, OOMKills, restart counts
- Service-to-service communication

Enable namespace-level monitoring:
```bash
# Label namespace for monitoring
kubectl label namespace production monitor=true

# Add metadata annotations to deployments
kubectl annotate deployment/payment-service \
  metadata.dynatrace.com/dt.operator.inject="true" \
  -n production
```

Custom Kubernetes event forwarding:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubernetes-event-forwarder
  namespace: dynatrace
data:
  config.yaml: |
    sinks:
      - type: dynatrace
        config:
          url: https://<ENV_ID>.live.dynatrace.com/api/v2/events/ingest
          token: <API_TOKEN>
    sources:
      - type: kubernetes
        config:
          namespaces:
            - production
            - staging
          eventTypes:
            - Warning
            - Normal
```

### Prometheus Metrics Integration

Dynatrace can ingest Prometheus metrics via the metrics API:

```yaml
# Deploy prometheus-to-dynatrace forwarder
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-to-dt
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus-to-dt
  template:
    metadata:
      labels:
        app: prometheus-to-dt
    spec:
      containers:
        - name: forwarder
          image: dynatrace/dynatrace-metric-utils:latest
          env:
            - name: PROMETHEUS_ENDPOINT
              value: "http://prometheus-service:9090"
            - name: DT_ENDPOINT
              value: "https://<ENV_ID>.live.dynatrace.com/api/v2/metrics/ingest"
            - name: DT_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: dynatrace-secret
                  key: metricsIngestToken
```

Alternatively, configure Prometheus remote_write to Dynatrace:
```yaml
# prometheus.yml - remote_write section
remote_write:
  - url: "https://<ENV_ID>.live.dynatrace.com/api/v2/metrics/ingest"
    remote_timeout: 10s
    headers:
      Authorization: "Api-Token <METRICS_INGEST_TOKEN>"
    write_relabel_configs:
      - source_labels: [__name__]
        regex: "container_.*|node_.*|kube_.*"
        action: keep
    queue_config:
      max_samples_per_send: 1000
      max_shards: 5
      batch_send_deadline: 5s
```

### Grafana Integration

Install Dynatrace data source plugin for Grafana:

```bash
# Install Dynatrace data source plugin
grafana-cli plugins install dynatrace-datasource

# Or via Grafana provisioning
cat <<EOF > /etc/grafana/provisioning/datasources/dynatrace.yaml
apiVersion: 1
datasources:
  - name: Dynatrace
    type: dynatrace-datasource
    url: https://<ENV_ID>.live.dynatrace.com
    access: proxy
    jsonData:
      tenantUrl: "https://<ENV_ID>.live.dynatrace.com"
    secureJsonData:
      token: "${DT_API_TOKEN}"
    isDefault: false
EOF

# Restart Grafana
systemctl restart grafana-server
# OR in K8s:
kubectl rollout restart deployment/grafana -n monitoring
```

Sample Dynatrace query in Grafana:
```
# Query Dynatrace metrics via DQL (Dynatrace Query Language)
fetch metrics
| filter metricSelector == "ext:kubernetes.pod.cpu.usage"
| filter k8s.namespace.name == "production"
| summarize avg(value), by:{k8s.pod.name}
| sort avg DESC
| limit 20
```

### Slack/Teams Notifications

Full Slack notification setup:
```bash
# 1. Create Slack Incoming Webhook
# Go to: https://api.slack.com/apps → Create App → Incoming Webhooks → Add Webhook

# 2. Configure Dynatrace notification
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/notifications" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "SLACK",
    "name": "production-slack-alerts",
    "alertingProfile": "00000000-0000-0000-0000-000000000001",
    "active": true,
    "url": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
    "channel": "#production-alerts",
    "message": ":red_circle: *{ProblemTitle}*\n*Severity:* {ProblemSeverity}\n*Impact:* {ProblemImpact}\n*Root Cause:* {ProblemRootCause}\n<{ProblemURL}|View in Dynatrace>"
  }'
```

MS Teams notification:
```bash
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/notifications" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "MSTEAMS",
    "name": "Teams Production Alerts",
    "alertingProfile": "00000000-0000-0000-0000-000000000001",
    "active": true,
    "url": "https://outlook.office.com/webhook/YOUR_TEAMS_WEBHOOK"
  }'
```

---

## 7. Real-World Scenarios

### Scenario 1: Auto-Detect OOMKill and Increase Memory

**Problem**: Payment service pods getting OOMKilled under load.

**Detection**: Dynatrace Davis detects `kubernetes.pod.restarts` spike + OOMKill event.

**Remediation Flow**:
```
Dynatrace detects OOMKill
    → Creates Problem: "OOMKill on payment-service"
    → Triggers Webhook to remediation service
    → Remediation service runs script
```

Remediation webhook receiver:
```python
# webhook.py - Flask remediation service
from flask import Flask, request, jsonify
import subprocess
import json
import os

app = Flask(__name__)

@app.route('/remediate/oomkill', methods=['POST'])
def handle_oomkill():
    data = request.json
    print(f"Received problem: {json.dumps(data, indent=2)}")
    
    # Extract entity from Dynatrace webhook payload
    affected_entities = data.get('affectedEntityIds', [])
    
    for entity_id in affected_entities:
        # Get entity details via Dynatrace API
        entity_info = get_entity_info(entity_id)
        
        namespace = entity_info.get('namespace', 'production')
        deployment = entity_info.get('deploymentName', '')
        
        if deployment:
            # Get current memory limit
            result = subprocess.run(
                ['kubectl', 'get', 'deployment', deployment, '-n', namespace,
                 '-o', 'jsonpath={.spec.template.spec.containers[0].resources.limits.memory}'],
                capture_output=True, text=True
            )
            current_memory = result.stdout.strip()
            
            # Increase memory by 25%
            new_memory = increase_memory(current_memory, 1.25)
            
            # Patch the deployment
            patch = {
                "spec": {
                    "template": {
                        "spec": {
                            "containers": [{
                                "name": deployment,
                                "resources": {
                                    "limits": {"memory": new_memory},
                                    "requests": {"memory": new_memory}
                                }
                            }]
                        }
                    }
                }
            }
            
            subprocess.run(
                ['kubectl', 'patch', 'deployment', deployment, '-n', namespace,
                 '--patch', json.dumps(patch)],
                check=True
            )
            
            print(f"Increased memory for {deployment} from {current_memory} to {new_memory}")
    
    return jsonify({"status": "remediated"}), 200

def increase_memory(current: str, factor: float) -> str:
    """Parse memory string like '512Mi' and increase by factor."""
    if current.endswith('Mi'):
        value = int(current[:-2])
        new_value = int(value * factor)
        return f"{new_value}Mi"
    elif current.endswith('Gi'):
        value = float(current[:-2])
        new_value = value * factor
        return f"{new_value:.1f}Gi"
    return current

def get_entity_info(entity_id: str) -> dict:
    """Call Dynatrace API to get entity details."""
    import urllib.request
    url = f"https://{os.environ['DT_ENV_ID']}.live.dynatrace.com/api/v2/entities/{entity_id}"
    req = urllib.request.Request(url)
    req.add_header('Authorization', f"Api-Token {os.environ['DT_API_TOKEN']}")
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

Configure Dynatrace Webhook for OOMKill:
```bash
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/notifications" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "WEBHOOK",
    "name": "OOMKill Auto-Remediation",
    "alertingProfile": "<PROFILE_ID>",
    "active": true,
    "url": "http://dynatrace-remediation-webhook.dynatrace-remediation.svc.cluster.local:8080/remediate/oomkill",
    "acceptAnyCertificate": true,
    "headers": [
      {
        "name": "Content-Type",
        "value": "application/json"
      }
    ],
    "payload": "{\"problemId\": \"{ProblemID}\", \"problemTitle\": \"{ProblemTitle}\", \"affectedEntityIds\": [{ImpactedEntities}], \"severityLevel\": \"{ProblemSeverity}\"}"
  }'
```

### Scenario 2: AI-Driven Deployment Validation

**Goal**: Automatically classify deployments as "good" or "bad" using Dynatrace SLO monitoring.

```groovy
// Jenkinsfile: Full deployment validation pipeline
pipeline {
  agent any

  environment {
    DT_API_TOKEN = credentials('dynatrace-api-token')
    DT_SERVER    = "https://${env.DT_ENV_ID}.live.dynatrace.com"
    SLO_ID       = credentials('payment-service-slo-id')
    APP_NAME     = 'payment-service'
  }

  stages {
    stage('Deploy') {
      steps {
        // Record deployment start time
        script {
          env.DEPLOY_START = sh(returnStdout: true, script: 'date +%s000').trim()
        }
        
        // Push deployment event
        sh """
          curl -X POST "${DT_SERVER}/api/v1/events" \\
            -H "Authorization: Api-Token ${DT_API_TOKEN}" \\
            -H "Content-Type: application/json" \\
            -d '{
              "eventType": "CUSTOM_DEPLOYMENT",
              "attachRules": {
                "tagRule": [{"meTagFilters": [{"context":"CONTEXTLESS","key":"app","value":"${APP_NAME}"}]}]
              },
              "deploymentName": "${APP_NAME}",
              "deploymentVersion": "${BUILD_NUMBER}",
              "source": "Jenkins"
            }'
        """
        
        // Deploy
        sh 'kubectl set image deployment/${APP_NAME} app=${APP_NAME}:${BUILD_NUMBER} -n production'
        sh 'kubectl rollout status deployment/${APP_NAME} -n production'
        
        script {
          env.DEPLOY_END = sh(returnStdout: true, script: 'date +%s000').trim()
        }
      }
    }

    stage('Validation Window') {
      steps {
        echo "Waiting 5 minutes for metrics to stabilize..."
        sleep(time: 300, unit: 'SECONDS')
      }
    }

    stage('Dynatrace SLO Quality Gate') {
      steps {
        script {
          // Get SLO evaluation
          def sloResult = sh(
            returnStdout: true,
            script: """
              curl -s "${DT_SERVER}/api/v2/slo/${SLO_ID}/evaluate?from=now-5m&to=now" \\
                -H "Authorization: Api-Token ${DT_API_TOKEN}" | \\
                python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'{data[\"status\"]}|{data[\"evaluatedPercentage\"]:.2f}|{data[\"target\"]}')
"
            """
          ).trim()
          
          def parts = sloResult.split('\\|')
          def status = parts[0]
          def evaluated = parts[1].toFloat()
          def target = parts[2].toFloat()
          
          echo "SLO Status: ${status} | Evaluated: ${evaluated}% | Target: ${target}%"
          
          if (status == 'FAILURE' || evaluated < target) {
            echo "QUALITY GATE FAILED: SLO breach detected"
            sh 'kubectl rollout undo deployment/${APP_NAME} -n production'
            error("Auto-rollback triggered: SLO ${evaluated}% below target ${target}%")
          } else {
            echo "QUALITY GATE PASSED: SLO ${evaluated}% >= target ${target}%"
          }
        }
      }
    }
  }
}
```

### Scenario 3: Auto-Remediation — Restart Crashed Pod

**Trigger**: Dynatrace detects pod crash loop (restarts > 5 in 10 minutes).

**Ansible Runbook**:
```yaml
# remediate-crashloop.yml
---
- name: Auto-remediate CrashLoopBackOff pods
  hosts: localhost
  gather_facts: false
  
  vars:
    dt_api_token: "{{ lookup('env', 'DT_API_TOKEN') }}"
    dt_env_id: "{{ lookup('env', 'DT_ENV_ID') }}"
    namespace: "{{ namespace | default('production') }}"
    deployment_name: "{{ deployment_name | default('') }}"

  tasks:
    - name: Get pod status
      kubernetes.core.k8s_info:
        kind: Pod
        namespace: "{{ namespace }}"
        label_selectors:
          - "app={{ deployment_name }}"
      register: pod_info

    - name: Check for CrashLoopBackOff
      set_fact:
        crashed_pods: "{{ pod_info.resources | selectattr('status.containerStatuses.0.state.waiting.reason', 'equalto', 'CrashLoopBackOff') | list }}"

    - name: Delete crashed pods (K8s will recreate via ReplicaSet)
      kubernetes.core.k8s:
        state: absent
        kind: Pod
        namespace: "{{ namespace }}"
        name: "{{ item.metadata.name }}"
      loop: "{{ crashed_pods }}"
      when: crashed_pods | length > 0

    - name: Wait for pods to restart
      kubernetes.core.k8s_info:
        kind: Pod
        namespace: "{{ namespace }}"
        label_selectors:
          - "app={{ deployment_name }}"
        wait: true
        wait_condition:
          type: Ready
          status: "True"
        wait_timeout: 120
      register: new_pods

    - name: Report to Dynatrace
      uri:
        url: "https://{{ dt_env_id }}.live.dynatrace.com/api/v1/events"
        method: POST
        headers:
          Authorization: "Api-Token {{ dt_api_token }}"
          Content-Type: "application/json"
        body_format: json
        body:
          eventType: "CUSTOM_ANNOTATION"
          attachRules:
            tagRule:
              - meTagFilters:
                  - context: CONTEXTLESS
                    key: "app"
                    value: "{{ deployment_name }}"
          annotationType: "AUTO_REMEDIATION_COMPLETED"
          annotationDescription: "Auto-remediation: Restarted {{ crashed_pods | length }} crashed pods"
          source: "Ansible Runbook"
      when: crashed_pods | length > 0
```

---

## 8. Verification & Testing

### Dynatrace UI Checks

1. **Infrastructure → Kubernetes**: Verify cluster appears and all nodes are monitored
2. **Applications & Microservices → Services**: Verify services are auto-discovered
3. **Problems**: Check for open problems (should be empty for healthy system)
4. **Technologies → OneAgent**: Verify OneAgent deployment status

### API Verification
```bash
# Check environment is reachable
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v1/time" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}"

# List all monitored entities
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/entities?entitySelector=type(SERVICE)&from=now-1h" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | \
  python3 -m json.tool

# Check active problems
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/problems?problemSelector=status(OPEN)" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | \
  python3 -m json.tool

# Verify Kubernetes monitoring
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/entities?entitySelector=type(KUBERNETES_CLUSTER)" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | \
  python3 -m json.tool

# Check metrics ingestion
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/metrics?metricSelector=ext:kubernetes.*&fields=displayName,unit" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | \
  python3 -m json.tool
```

### Simulate Anomaly for Testing
```bash
# Generate CPU load to test anomaly detection
kubectl run cpu-stress --image=progrium/stress --restart=Never -n production \
  -- --cpu 2 --timeout 300s

# Generate memory pressure
kubectl run memory-stress --image=progrium/stress --restart=Never -n production \
  -- --vm 1 --vm-bytes 400M --timeout 300s

# Simulate OOMKill (set very low memory limit)
kubectl run oom-test --image=nginx --restart=Never -n production \
  --limits=memory=10Mi

# Watch for Dynatrace to detect problem
watch -n 5 'curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/problems?problemSelector=status(OPEN)&from=now-5m" -H "Authorization: Api-Token ${DT_API_TOKEN}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Open problems: {d[\"totalCount\"]}\")"'
```

---

## 9. Troubleshooting Guide

### Issue 1: OneAgent Pods in Pending State
```bash
# Check node resources
kubectl describe pod <oneagent-pod> -n dynatrace

# Common fix: increase Minikube resources
minikube stop
minikube start --memory=8192 --cpus=4

# Or reduce OneAgent resource requests
kubectl patch dynakube dynakube -n dynatrace --type=merge \
  -p '{"spec":{"oneAgent":{"classicFullStack":{"resources":{"requests":{"memory":"256Mi","cpu":"50m"}}}}}}'
```

### Issue 2: ActiveGate Not Connecting
```bash
# Check ActiveGate logs
kubectl logs -n dynatrace -l app.kubernetes.io/component=activegate --tail=100

# Verify secret is correct
kubectl get secret dynakube -n dynatrace -o jsonpath='{.data.apiToken}' | base64 -d | head -c 20

# Test connectivity from ActiveGate pod
kubectl exec -n dynatrace $(kubectl get pod -n dynatrace -l app.kubernetes.io/component=activegate -o name | head -1) \
  -- curl -s -o /dev/null -w "%{http_code}" "https://<ENV_ID>.live.dynatrace.com/api/v1/time"
```

### Issue 3: Services Not Auto-Discovered
```bash
# Verify OneAgent is injected into pod
kubectl get pod <app-pod> -n production -o jsonpath='{.spec.initContainers[*].name}'
# Should show: install-oneagent-sdk

# Check OneAgent injection logs
kubectl logs <app-pod> -n production -c install-oneagent-sdk

# Manually add injection annotation
kubectl patch deployment <app-name> -n production \
  --patch '{"spec":{"template":{"metadata":{"annotations":{"oneagent.dynatrace.com/inject":"true"}}}}}'
kubectl rollout restart deployment/<app-name> -n production
```

### Issue 4: Metrics Not Appearing in Dynatrace
```bash
# Check metric ingestion API
curl -v -X POST "https://<ENV_ID>.live.dynatrace.com/api/v2/metrics/ingest" \
  -H "Authorization: Api-Token ${DT_INGEST_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d "test.metric.value 42"

# Verify token has metrics.ingest permission
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v1/tokens/lookup" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"token": "'"${DT_INGEST_TOKEN}"'"}'
```

### Issue 5: Davis AI Not Creating Problems
```bash
# Check if anomaly detection is enabled
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v2/settings/objects?schemaId=builtin:anomaly-detection.services" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}"

# Verify services are in monitoring state (need traffic for baseline)
# Solution: Generate synthetic traffic for at least 1 hour before Davis starts creating baselines
```

### Issue 6: Webhook Remediation Not Triggering
```bash
# Test webhook endpoint manually
curl -X POST "http://dynatrace-remediation-webhook.dynatrace-remediation.svc.cluster.local:8080/remediate/oomkill" \
  -H "Content-Type: application/json" \
  -d '{"problemId": "test-123", "problemTitle": "Test OOMKill", "affectedEntityIds": []}'

# Check webhook deployment
kubectl get pods -n dynatrace-remediation
kubectl logs -n dynatrace-remediation -l app=remediation-webhook --tail=50
```

### Issue 7: Kubernetes Monitoring Shows Partial Data
```bash
# Verify ActiveGate has kubernetes-monitoring capability
kubectl get dynakube dynakube -n dynatrace -o jsonpath='{.spec.activeGate.capabilities}'

# Ensure RBAC is correct for ActiveGate
kubectl auth can-i list pods --as=system:serviceaccount:dynatrace:dynakube-activegate -n production
```

### Issue 8: Jenkins Plugin Not Pushing Events
```bash
# In Jenkins: Check credentials are valid
# Test from Jenkins server
curl -X POST "https://<ENV_ID>.live.dynatrace.com/api/v1/events" \
  -H "Authorization: Api-Token <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"eventType":"CUSTOM_ANNOTATION","attachRules":{"tagRule":[]},"annotationType":"TEST","annotationDescription":"Jenkins test","source":"Jenkins"}'

# Check Jenkins plugin configuration
# Manage Jenkins → System → Dynatrace → Test Connection
```

### Issue 9: High Memory Usage by OneAgent
```bash
# Check OneAgent memory usage
kubectl top pods -n dynatrace

# Reduce monitoring scope
kubectl patch dynakube dynakube -n dynatrace --type=merge -p '{
  "spec": {
    "metadataEnrichment": {
      "namespaceSelector": {
        "matchLabels": {"monitor": "true"}
      }
    }
  }
}'

# Only label critical namespaces
kubectl label namespace production monitor=true
```

### Issue 10: Problem Notifications Not Sent to Slack
```bash
# Test Slack webhook directly
curl -X POST "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test from Dynatrace"}'

# Verify notification configuration
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v1/notifications" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | python3 -m json.tool

# Check alerting profile has correct severity filters
curl -s "https://<ENV_ID>.live.dynatrace.com/api/v1/alertingProfiles/<PROFILE_ID>" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" | python3 -m json.tool
```

---

## 10. Cheat Sheet

### Dynatrace API Quick Reference

| Operation | Command |
|-----------|---------|
| List all services | `curl -H "Authorization: Api-Token $TOKEN" "$DT_URL/api/v2/entities?entitySelector=type(SERVICE)"` |
| Get open problems | `curl -H "Authorization: Api-Token $TOKEN" "$DT_URL/api/v2/problems?problemSelector=status(OPEN)"` |
| Push deployment event | `curl -X POST -H "Authorization: Api-Token $TOKEN" -d '{...}' "$DT_URL/api/v1/events"` |
| Ingest custom metric | `curl -X POST -H "Authorization: Api-Token $TOKEN" -d "my.metric 42" "$DT_URL/api/v2/metrics/ingest"` |
| Get SLO status | `curl -H "Authorization: Api-Token $TOKEN" "$DT_URL/api/v2/slo/<ID>"` |
| List tokens | `curl -H "Authorization: Api-Token $TOKEN" "$DT_URL/api/v1/tokens"` |
| Create alert profile | `curl -X POST -H "Authorization: Api-Token $TOKEN" -d '{...}' "$DT_URL/api/v1/alertingProfiles"` |

### Kubernetes Commands for Dynatrace

```bash
# Check Dynatrace components
kubectl get all -n dynatrace

# Check OneAgent status
kubectl get dynakube -n dynatrace

# View OneAgent logs
kubectl logs -n dynatrace -l app=oneagent --tail=100

# View ActiveGate logs
kubectl logs -n dynatrace -l app.kubernetes.io/component=activegate --tail=100

# Restart OneAgent on a node
kubectl delete pod -n dynatrace -l app=oneagent --field-selector spec.nodeName=<node>

# Check injection status
kubectl get pod <pod-name> -n production -o yaml | grep dynatrace

# Update DynaKube
kubectl edit dynakube dynakube -n dynatrace

# Check operator logs
kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator
```

### Environment Variables Reference

```bash
# Set these in your shell or CI/CD
export DT_ENV_ID="abc12345"
export DT_API_TOKEN="dt0c01.XXXXXX"
export DT_INGEST_TOKEN="dt0c01.YYYYYY"
export DT_SERVER="https://${DT_ENV_ID}.live.dynatrace.com"

# Quick connectivity test
curl -s "${DT_SERVER}/api/v1/time" -H "Authorization: Api-Token ${DT_API_TOKEN}"
```

### Davis AI Problem States

| State | Description | Action |
|-------|-------------|--------|
| OPEN | Active problem, ongoing | Investigate and remediate |
| ACKNOWLEDGED | Team is aware | Document progress |
| RESOLVED | Auto-resolved when anomaly clears | Review and close |
| CLOSED | Manually closed | Post-mortem if needed |

### Alerting Severity Levels

| Level | Meaning | Example |
|-------|---------|---------|
| AVAILABILITY | Service down | Pod CrashLoop, 0 healthy instances |
| PERFORMANCE | Degraded | Response time > 2x baseline |
| ERROR | Error rate spike | HTTP 5xx > 5% of requests |
| RESOURCE_CONTENTION | Resource saturation | CPU throttling, memory pressure |
| CUSTOM_ALERT | User-defined threshold | Custom metric > threshold |

### Useful DQL Queries (Dynatrace Query Language)

```sql
-- Services with high error rates
fetch dt.entity.service
| filter error_rate > 5
| fields entity.name, error_rate, response_time_p99

-- Pods with OOMKills in last hour
fetch events
| filter event.category == "OOM_KILL"
| filter timestamp > now() - 1h
| fields k8s.pod.name, k8s.namespace.name, timestamp
| sort timestamp DESC

-- Top slowest API endpoints
fetch spans
| filter service.name == "payment-service"
| filter duration > 1000ms
| summarize avg(duration), count(), by:{http.url}
| sort avg(duration) DESC
| limit 10
```
