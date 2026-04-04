# Scenario 02: Canary Deployment
# Istio + ArgoCD Rollouts + Prometheus Metrics-Based Auto-Rollback

## Overview

This scenario demonstrates a **safe canary deployment** strategy where a new version receives a small percentage of traffic, Prometheus monitors error rates, and ArgoCD Rollouts automatically promotes or rolls back based on metrics.

**Estimated Time:** 1.5–2 hours to set up, ~15 minutes per canary release

```mermaid
flowchart LR
    A[Jenkins\nBuilds v2] --> B[JFrog\nImage Push]
    B --> C[ArgoCD Rollouts\nCanary Start 10%]
    C --> D{Prometheus\nAnalysis}
    D -- Error rate OK --> E[Promote\n25% → 50% → 100%]
    D -- Error rate HIGH --> F[Auto Rollback\nto v1 100%]
    E --> G[Istio\nUpdate Weights]
    G --> H[Grafana\nCanary Dashboard]
    H --> I[Slack\nPromotion Alert]
```

---

## Prerequisites

```bash
# Ensure these are installed
kubectl get pods -n istio-system
kubectl get pods -n argocd

# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Install Argo Rollouts kubectl plugin
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Verify
kubectl argo rollouts version
```

---

## Step 1: Kubernetes Services Setup

```yaml
# services.yaml
# Two services needed for Istio canary: stable and canary
---
# Stable service — points to current version (v1)
apiVersion: v1
kind: Service
metadata:
  name: myapp-stable
  namespace: prod
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
---
# Canary service — points to new version (v2)
apiVersion: v1
kind: Service
metadata:
  name: myapp-canary
  namespace: prod
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
---
# Public service — the one clients use (Ingress/Gateway points here)
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: prod
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

---

## Step 2: Istio Traffic Configuration

```yaml
# istio-canary.yaml
---
# VirtualService: splits traffic between stable and canary
# ArgoCD Rollouts will update the weights automatically
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp-vs
  namespace: prod
spec:
  hosts:
  - myapp                               # Matches service name
  http:
  - name: primary                       # Route name (referenced by Rollout)
    route:
    - destination:
        host: myapp-stable              # Stable receives 100% initially
        port:
          number: 80
      weight: 100
    - destination:
        host: myapp-canary              # Canary receives 0% initially
        port:
          number: 80
      weight: 0
---
# DestinationRule: defines subsets for v1 and v2
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: myapp-dr
  namespace: prod
spec:
  host: myapp
  subsets:
  - name: stable
    labels:
      app: myapp
  - name: canary
    labels:
      app: myapp
```

---

## Step 3: Prometheus Analysis Template

```yaml
# analysis-template.yaml
# Defines the success/failure criteria for the canary
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: prod
spec:
  args:
  - name: service-name                  # Passed by the Rollout
  metrics:
  - name: success-rate
    interval: 30s                       # Check every 30s
    # Must stay above 95% success rate to continue
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.90  # Fail immediately if < 90%
    failureLimit: 3                     # Allow 3 failures before abort
    provider:
      prometheus:
        address: http://prometheus-operated.monitoring:9090
        query: |
          sum(
            rate(istio_requests_total{
              destination_service=~"{{args.service-name}}",
              response_code!~"5.*"
            }[5m])
          )
          /
          sum(
            rate(istio_requests_total{
              destination_service=~"{{args.service-name}}"
            }[5m])
          )
```

---

## Step 4: ArgoCD Rollout Definition

```yaml
# rollout.yaml
# Replaces the standard Deployment resource
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
  namespace: prod
spec:
  replicas: 5                           # Total pod count
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      imagePullSecrets:
      - name: jfrog-pull-secret
      containers:
      - name: myapp
        image: mycompany.jfrog.io/docker-local/myapp:v1  # Updated per release
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
  strategy:
    canary:
      canaryService: myapp-canary       # K8s service for canary pods
      stableService: myapp-stable       # K8s service for stable pods
      trafficRouting:
        istio:
          virtualService:
            name: myapp-vs              # VirtualService to update
            routes:
            - primary                   # Route name within VirtualService
      analysis:
        templates:
        - templateName: success-rate    # AnalysisTemplate to run
        startingStep: 1                 # Start analysis at step 1
        args:
        - name: service-name
          value: myapp-canary.prod.svc.cluster.local
      steps:
      - setWeight: 10                   # Step 1: Send 10% to canary
      - pause: {duration: 2m}           # Wait 2 minutes, check metrics
      - setWeight: 25                   # Step 2: Send 25% to canary
      - pause: {duration: 2m}
      - setWeight: 50                   # Step 3: Send 50% to canary
      - pause: {duration: 2m}
      - setWeight: 75                   # Step 4: Send 75% to canary
      - pause: {duration: 2m}
      - setWeight: 100                  # Step 5: Full rollout
```

---

## Step 5: Trigger a Canary Release

### Via Jenkins Pipeline

```groovy
// Jenkinsfile — Canary Release
stage('Update Image for Canary') {
    steps {
        withCredentials([usernamePassword(credentialsId: 'github-credentials',
            usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
            sh """
                git clone https://${GIT_USER}:${GIT_PASS}@github.com/myorg/myapp-config.git /tmp/config
                cd /tmp/config
                # Update Rollout image tag
                sed -i 's|image: mycompany.jfrog.io/docker-local/myapp:.*|image: mycompany.jfrog.io/docker-local/myapp:${IMAGE_TAG}|' rollout.yaml
                git add rollout.yaml
                git commit -m "ci: canary release ${IMAGE_TAG}"
                git push origin main
            """
        }
    }
}

stage('Monitor Canary') {
    steps {
        sh """
            # Watch canary progression
            kubectl argo rollouts get rollout myapp -n prod --watch
        """
    }
}
```

### Manual Trigger

```bash
# Update image to trigger canary rollout
kubectl argo rollouts set image myapp \
  myapp=mycompany.jfrog.io/docker-local/myapp:v2 \
  -n prod

# Watch the progression
kubectl argo rollouts get rollout myapp -n prod --watch
```

---

## Step 6: Monitor the Canary

```bash
# Watch rollout status in real time
kubectl argo rollouts get rollout myapp -n prod --watch
# Expected output shows step progression:
# ✔ Stable ReplicaSet: myapp-xxx (4 pods)
# ✔ Canary ReplicaSet: myapp-yyy (1 pod)
# ↕  Pausing (2m0s remaining)

# Check traffic split in Istio VirtualService
kubectl get virtualservice myapp-vs -n prod -o yaml | grep weight

# Check Prometheus metrics for canary
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring &
# Query: sum(rate(istio_requests_total{destination_service=~"myapp-canary.*",response_code!~"5.*"}[5m])) / sum(rate(istio_requests_total{destination_service=~"myapp-canary.*"}[5m]))
```

### Grafana Dashboard

```bash
# Import Argo Rollouts dashboard
# Grafana → Import → ID: 15386 → Select Prometheus → Import

# Key metrics in the canary dashboard:
# - Canary weight (traffic %)
# - Success rate (canary vs stable)
# - Request rate (canary vs stable)
# - Analysis run status
```

---

## Step 7: Manual Promote or Abort

```bash
# Option A: Manually promote (skip pause)
kubectl argo rollouts promote myapp -n prod

# Option B: Abort canary (roll back to stable)
kubectl argo rollouts abort myapp -n prod

# Option C: After abort, restart rollout with stable image
kubectl argo rollouts undo myapp -n prod
```

---

## Scenario: Canary Auto-Rollback in Action

```bash
# Step 1: Deploy a "bad" version that returns 500 errors
kubectl argo rollouts set image myapp \
  myapp=mycompany.jfrog.io/docker-local/myapp:bad-v3 \
  -n prod

# Step 2: Watch analysis fail
kubectl argo rollouts get rollout myapp -n prod --watch
# Expected:
# ✖ AnalysisRun: FAILED (success-rate < 90%)
# ↩  Rolling back to stable...

# Step 3: Verify rollback completed
kubectl argo rollouts get rollout myapp -n prod
# Expected: Fully stable (100% traffic to v1)

# Step 4: Check the analysis run details
kubectl get analysisrun -n prod
kubectl describe analysisrun <name> -n prod
# Shows exact metric values that caused the failure
```

---

## Verification

```bash
# 1. Rollout is progressing
kubectl argo rollouts get rollout myapp -n prod
# STATUS: Progressing (Paused at step N of M)

# 2. Istio weights updated
kubectl get virtualservice myapp-vs -n prod -o jsonpath='{.spec.http[0].route[*].weight}'

# 3. Analysis is passing
kubectl get analysisrun -n prod
# Expected: Measure result >= 0.95

# 4. Slack notification
# Check #deployments for canary step notifications

# 5. Grafana canary dashboard shows metrics separating v1 vs v2
```

---

## Rollback Procedures

```bash
# Immediate rollback (all traffic back to stable)
kubectl argo rollouts abort myapp -n prod

# Full undo (reset to previous image)
kubectl argo rollouts undo myapp -n prod

# Verify traffic is 100% on stable
kubectl get virtualservice myapp-vs -n prod -o yaml | grep -A2 weight
# Expected: stable=100, canary=0
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Analysis run not starting | Check AnalysisTemplate exists in same namespace; verify Prometheus URL |
| Istio weights not updating | Verify Rollout has correct VirtualService name; check argo-rollouts controller logs |
| Canary pods not receiving traffic | Verify `canaryService` selector matches pod labels |
| Prometheus query returning NaN | Check Istio metrics are present: `rate(istio_requests_total[5m])` |
| Analysis stays in Pending | Verify Prometheus is reachable from the analysis pod |
| Rollout stuck in pause | Manually promote: `kubectl argo rollouts promote myapp -n prod` |
