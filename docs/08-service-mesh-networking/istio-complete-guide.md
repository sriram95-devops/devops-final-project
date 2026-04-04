# Istio Service Mesh — Complete Guide

## 1. Overview & Why You Need It

Istio is an open-source **service mesh** that adds traffic management, security (mTLS), and observability to Kubernetes microservices without changing application code.

| Feature | Istio | Linkerd | Consul Connect |
|---------|-------|---------|----------------|
| mTLS | ✅ | ✅ | ✅ |
| Traffic splitting | ✅ Advanced | ✅ Basic | ✅ Basic |
| Circuit breaker | ✅ | ❌ | ✅ |
| Observability | ✅ Full | ✅ | ✅ |
| Complexity | High | Low | Medium |

**When to use Istio:**
- Microservices needing zero-trust security (mTLS)
- Canary deployments with traffic percentage splits
- Circuit breaking and retry policies
- Distributed tracing without code changes

---

## 2. Local Setup on Minikube

### Prerequisites

```bash
# Start Minikube with enough resources
minikube start --cpus=4 --memory=8192 --driver=docker

# Verify
kubectl get nodes
```

### Install Istio with istioctl

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Add to .bashrc for persistence
echo 'export PATH=$HOME/istio-1.20.0/bin:$PATH' >> ~/.bashrc

# Install Istio with demo profile (includes all features for learning)
istioctl install --set profile=demo -y

# Expected output:
# ✔ Istio core installed
# ✔ Istiod installed
# ✔ Egress gateways installed
# ✔ Ingress gateways installed
# ✔ Installation complete

# Verify Istio pods are running
kubectl get pods -n istio-system
# Expected:
# istio-egressgateway-xxx     1/1  Running
# istio-ingressgateway-xxx    1/1  Running
# istiod-xxx                  1/1  Running
```

### Enable Sidecar Injection

```bash
# Label namespace for automatic sidecar injection
kubectl label namespace default istio-injection=enabled

# Verify label
kubectl get namespace default --show-labels
# Expected: istio-injection=enabled

# Deploy test application
kubectl apply -f $ISTIO_HOME/samples/bookinfo/platform/kube/bookinfo.yaml

# Verify each pod has 2 containers (app + Envoy sidecar)
kubectl get pods
# Expected:
# details-v1-xxx      2/2  Running   (app + envoy)
# productpage-v1-xxx  2/2  Running
# ratings-v1-xxx      2/2  Running
# reviews-v1-xxx      2/2  Running

# Open in browser (Minikube)
minikube tunnel &
kubectl apply -f $ISTIO_HOME/samples/bookinfo/networking/bookinfo-gateway.yaml
INGRESS_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Open: http://$INGRESS_IP/productpage"
```

---

## 3. Online/Cloud Setup — AKS with Istio Addon

```bash
# AKS has Istio as a managed addon (preview)
az aks create \
  --resource-group rg-devops \
  --name aks-istio-cluster \
  --node-count 3 \
  --enable-asm \
  --generate-ssh-keys

# OR enable on existing cluster
az aks mesh enable \
  --resource-group rg-devops \
  --name aks-devops-cluster

# Verify
kubectl get pods -n aks-istio-system
```

---

## 4. Configuration Deep Dive

### 4.1 VirtualService — Traffic Routing

```yaml
# virtualservice-routing.yaml
# Routes traffic to different versions based on user headers
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: reviews                         # Name must match K8s Service name
  namespace: default
spec:
  hosts:
  - reviews                             # Target service hostname
  http:
  - match:                              # Rule 1: match user header
    - headers:
        end-user:
          exact: jason                  # If user=jason, send to v2
    route:
    - destination:
        host: reviews
        subset: v2
  - route:                              # Rule 2: default (everyone else)
    - destination:
        host: reviews
        subset: v1                      # Send to v1
```

### 4.2 DestinationRule — Subsets + Circuit Breaker

```yaml
# destinationrule.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: reviews
  namespace: default
spec:
  host: reviews                         # Must match Service name
  trafficPolicy:
    outlierDetection:                   # Circuit breaker settings
      consecutive5xxErrors: 3          # Trip after 3 consecutive 5xx errors
      interval: 30s                     # Check interval
      baseEjectionTime: 30s            # How long to eject unhealthy host
      maxEjectionPercent: 50           # Max 50% of hosts ejected at once
    connectionPool:
      tcp:
        maxConnections: 100            # Max TCP connections per host
      http:
        http1MaxPendingRequests: 100   # Max pending HTTP requests
        http2MaxRequests: 1000         # Max concurrent HTTP/2 requests
  subsets:
  - name: v1                           # Subset name (used in VirtualService)
    labels:
      version: v1                      # Matches pod labels
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
```

### 4.3 Gateway — External Traffic

```yaml
# gateway.yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: myapp-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway               # Use Istio's ingress gateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "myapp.example.com"              # External hostname
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE                      # TLS termination at gateway
      credentialName: myapp-tls-cert   # K8s TLS Secret name
    hosts:
    - "myapp.example.com"
---
# VirtualService that binds to this Gateway
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
  - "myapp.example.com"
  gateways:
  - myapp-gateway                      # Reference the Gateway above
  http:
  - route:
    - destination:
        host: myapp-service
        port:
          number: 80
```

### 4.4 PeerAuthentication — Enforce mTLS

```yaml
# peer-authentication-strict.yaml
# Enforces mTLS for ALL services in namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default                    # Apply to entire namespace
spec:
  mtls:
    mode: STRICT                        # STRICT = only mTLS, reject plaintext
    # mode: PERMISSIVE = accept both (use during migration)
---
# Per-workload mTLS (override namespace default)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: legacy-app-permissive
  namespace: default
spec:
  selector:
    matchLabels:
      app: legacy-app                   # Only for legacy-app pods
  mtls:
    mode: PERMISSIVE                    # Allow plaintext for this legacy app
```

### 4.5 AuthorizationPolicy — Service-to-Service Access Control

```yaml
# authorization-policy.yaml
# Only allow frontend to call backend on /api path
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: backend-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: backend                      # Apply to backend pods
  rules:
  - from:
    - source:
        principals:                     # Only from frontend service account
        - "cluster.local/ns/default/sa/frontend-sa"
  - to:
    - operation:
        methods: ["GET", "POST"]        # Only GET and POST
        paths: ["/api/*"]              # Only /api paths
```

### 4.6 Canary Deployment — Traffic Splitting

```yaml
# canary-virtual-service.yaml
# Split traffic: 90% to v1 (stable), 10% to v2 (canary)
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
  namespace: default
spec:
  hosts:
  - myapp                               # Target service
  http:
  - route:
    - destination:
        host: myapp
        subset: stable                  # Stable version
      weight: 90                        # 90% of traffic
    - destination:
        host: myapp
        subset: canary                  # Canary version
      weight: 10                        # 10% of traffic
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: myapp
spec:
  host: myapp
  subsets:
  - name: stable
    labels:
      version: v1
  - name: canary
    labels:
      version: v2
```

```bash
# Apply canary
kubectl apply -f canary-virtual-service.yaml

# Gradually increase canary traffic
# Edit weight: stable=80, canary=20 → stable=50, canary=50 → stable=0, canary=100

# Verify traffic split with curl
for i in {1..20}; do
  curl -s http://$INGRESS_IP/productpage | grep -o 'reviews-v[0-9]' | head -1
done
# Expected: ~18 responses with v1, ~2 with v2
```

---

## 5. Integration with Existing Tools

### Prometheus Integration

Istio automatically exposes metrics to Prometheus:

```yaml
# PodMonitor for Istio metrics
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: istio-proxies
  namespace: monitoring
spec:
  selector:
    matchExpressions:
    - key: istio-prometheus-ignore
      operator: DoesNotExist
  podMetricsEndpoints:
  - path: /stats/prometheus
    targetPort: 15090
```

```bash
# Key Istio PromQL queries:
# Request rate:
# rate(istio_requests_total[5m])

# Error rate (5xx):
# rate(istio_requests_total{response_code=~"5.*"}[5m]) / rate(istio_requests_total[5m])

# P99 latency:
# histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket[5m]))
```

### Grafana Integration

```bash
# Import Istio dashboards into Grafana
# Dashboard IDs:
# - 7630: Istio Mesh Dashboard
# - 7636: Istio Service Dashboard
# - 7642: Istio Workload Dashboard
# - 7639: Istio Pilot Dashboard

# In Grafana: + → Import → Enter ID → Select Prometheus data source → Import
```

### Jaeger Integration

```yaml
# Enable Jaeger tracing in Istio
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    enableTracing: true                # Enable distributed tracing
    defaultConfig:
      tracing:
        sampling: 100                  # 100% sampling (reduce in production)
        zipkin:
          address: jaeger-collector.observability:9411  # Jaeger Zipkin endpoint
```

### ArgoCD + Istio Canary (Argo Rollouts)

```yaml
# rollout-with-istio.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp-rollout
spec:
  replicas: 5
  strategy:
    canary:
      canaryService: myapp-canary      # Canary service
      stableService: myapp-stable      # Stable service
      trafficRouting:
        istio:
          virtualService:
            name: myapp-vs             # VirtualService to update
            routes:
            - primary
      steps:
      - setWeight: 10                  # Step 1: 10% canary
      - pause: {duration: 5m}          # Wait 5 mins
      - setWeight: 30                  # Step 2: 30% canary
      - pause: {duration: 5m}
      - setWeight: 60
      - pause: {duration: 5m}
      - setWeight: 100                 # Full rollout
      analysis:
        templates:
        - templateName: error-rate     # Argo analysis template
        startingStep: 1
        args:
        - name: service-name
          value: myapp-canary
```

---

## 6. Real-World Scenarios

### Scenario 1: Enable mTLS Across All Services

```bash
# Step 1: Verify services are NOT using mTLS yet
kubectl exec -it $(kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}') \
  -c istio-proxy -- pilot-agent request GET /stats | grep ssl

# Step 2: Apply STRICT mTLS
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
EOF

# Step 3: Verify mTLS is enforced
istioctl authn tls-check productpage-v1-xxx.default

# Step 4: Test that plain HTTP is rejected
kubectl run test-pod --image=curlimages/curl -it --rm --restart=Never -- \
  curl -v http://reviews:9080/

# Expected: Connection reset (mTLS required)

# Step 5: Verify app still works (Envoy handles mTLS transparently)
curl http://$INGRESS_IP/productpage
# Expected: 200 OK (app works because sidecars handle mTLS)
```

### Scenario 2: Circuit Breaker in Action

```bash
# Step 1: Apply DestinationRule with circuit breaker
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 10s
      baseEjectionTime: 30s
EOF

# Step 2: Inject failures into httpbin
kubectl apply -f $ISTIO_HOME/samples/httpbin/httpbin.yaml

# Step 3: Send requests that trigger circuit breaker
kubectl run fortio --image=fortio/fortio --restart=Never -- \
  load -c 3 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/status/500

# Step 4: Check circuit breaker tripped
kubectl exec fortio -- fortio report
# Expected: Some requests succeed (circuit open), some fail fast

# Step 5: Verify in Prometheus
# query: pilot_xds_cds_reject_total (should be 0, circuit breaker working)
```

### Scenario 3: Traffic Mirroring (Shadow Traffic)

```bash
# Mirror 100% of production traffic to a new v2 for testing
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
  - myapp
  http:
  - route:
    - destination:
        host: myapp
        subset: v1
      weight: 100
    mirror:
      host: myapp
      subset: v2                       # Mirror to v2 (responses discarded)
    mirrorPercentage:
      value: 100.0                     # Mirror 100% (reduce for high-traffic)
EOF

# Verify mirror traffic hits v2
kubectl logs -l version=v2 -c myapp --tail=10
# Expected: You'll see requests mirrored from v1 traffic
```

---

## 7. Verification & Testing

```bash
# Check Istio installation health
istioctl verify-install

# Analyze configuration for issues
istioctl analyze

# Check proxy status for all pods
istioctl proxy-status

# Check proxy config for specific pod
istioctl proxy-config routes $(kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}')

# Access Kiali dashboard (service mesh visualization)
istioctl dashboard kiali

# Access Jaeger dashboard
istioctl dashboard jaeger

# Access Grafana
istioctl dashboard grafana

# Check mTLS status between two services
istioctl authn tls-check \
  $(kubectl get pod -l app=reviews -o jsonpath='{.items[0].metadata.name}') \
  productpage.default.svc.cluster.local

# Port-forward to test service directly
kubectl port-forward svc/productpage 9080:9080
curl http://localhost:9080/productpage
```

---

## 8. Troubleshooting Guide

| Issue | Symptom | Fix |
|-------|---------|-----|
| Sidecar not injected | Pod has 1 container only | Check namespace label: `kubectl get ns default --show-labels` |
| 503 errors after mTLS | Existing services fail | Use PERMISSIVE mode during migration |
| VirtualService not routing | All traffic goes to v1 | Check `istioctl analyze` for config errors |
| Circuit breaker not tripping | No outlier detection | Verify DestinationRule has `outlierDetection` |
| Istio injection breaks app | App can't start | Check `kubectl describe pod` for sidecar errors |
| High CPU/memory from sidecars | Resource pressure | Tune resource limits in IstioOperator |
| Gateway returns 404 | External routing fails | Verify VirtualService `gateways` field matches Gateway name |
| Metrics missing in Prometheus | No Istio metrics | Check ServiceMonitor and Prometheus scrape configs |
| TLS cert errors | HTTPS fails | Check `credentialName` secret exists in `istio-system` |
| istiod crash | Control plane down | Check `kubectl logs -n istio-system deployment/istiod` |

---

## 9. Cheat Sheet

```bash
# Installation
istioctl install --set profile=demo -y      # Install (demo profile)
istioctl install --set profile=minimal -y   # Minimal (production)
istioctl uninstall --purge                  # Remove Istio

# Namespace injection
kubectl label namespace default istio-injection=enabled   # Enable
kubectl label namespace default istio-injection-           # Disable

# Diagnosis
istioctl analyze                            # Analyze config
istioctl proxy-status                       # All proxy status
istioctl proxy-config all <pod>             # Full proxy config
istioctl verify-install                     # Verify install

# Dashboards
istioctl dashboard kiali                    # Service mesh UI
istioctl dashboard grafana                  # Metrics
istioctl dashboard jaeger                   # Tracing
istioctl dashboard envoy <pod>              # Envoy admin

# mTLS check
istioctl authn tls-check <pod> <service>   # Check mTLS status

# Traffic management
kubectl apply -f virtualservice.yaml        # Apply traffic rules
kubectl delete vs <name>                    # Remove traffic rules
kubectl get vs,dr,gw,pa -A                 # List all Istio resources
```
