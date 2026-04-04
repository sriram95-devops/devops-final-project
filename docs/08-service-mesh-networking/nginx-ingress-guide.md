# Nginx Ingress Controller — Complete Guide

## 1. Overview & Why You Need It

Nginx Ingress Controller manages external HTTP/HTTPS access to services inside a Kubernetes cluster. It is a Layer-7 load balancer that replaces the need for multiple LoadBalancer services.

| Feature | Nginx Ingress | Traefik | HAProxy Ingress |
|---------|--------------|---------|-----------------|
| Path routing | ✅ | ✅ | ✅ |
| TLS termination | ✅ | ✅ | ✅ |
| Rate limiting | ✅ (annotation) | ✅ (middleware) | ✅ |
| Auth (OAuth2) | ✅ | ✅ | ✅ |
| Kubernetes native | ✅ | ✅ | ✅ |
| Maturity | High | High | Medium |
| Azure integration | ✅ ALB | ✅ | ✅ |

**When to use Nginx Ingress:**
- Expose multiple services under one IP/domain
- TLS termination (HTTPS)
- Path-based or host-based routing
- Rate limiting / auth at edge
- Works well alongside Istio (Nginx as north-south edge, Istio for east-west)

---

## 2. Local Setup on Minikube

### Option A — Minikube Addon

```bash
# Enable built-in ingress addon
minikube addons enable ingress

# Verify
kubectl get pods -n ingress-nginx
# Expected:
# ingress-nginx-controller-xxx   1/1   Running

# Get Minikube IP (use this as your ingress IP)
minikube ip
# e.g., 192.168.49.2
```

### Option B — Helm Install (recommended for production parity)

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with 2 replicas for HA
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.metrics.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"=true \
  --set controller.podAnnotations."prometheus\.io/port"=10254

# On Minikube: run tunnel to get external IP
minikube tunnel &

# Verify external IP is assigned
kubectl get svc -n ingress-nginx
# Expected:
# ingress-nginx-controller  LoadBalancer  10.96.x.x  192.168.49.2  80:31xxx/TCP,443:32xxx/TCP
```

---

## 3. Online/Cloud Setup — AKS

```bash
# On AKS, Nginx Ingress gets a real Azure Load Balancer IP
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux

# Get public IP (takes ~2 mins to provision Azure LB)
kubectl get svc ingress-nginx-controller -n ingress-nginx --watch
# Expected:
# NAME                     TYPE           EXTERNAL-IP      PORT(S)
# ingress-nginx-controller LoadBalancer   20.x.x.x         80:xxx,443:xxx
```

---

## 4. Configuration Deep Dive

### 4.1 Basic Host-Based Ingress

```yaml
# ingress-host-based.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: default
  annotations:
    # Use nginx ingress class
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx               # Required: specify ingress class
  rules:
  - host: api.myapp.example.com         # Route requests for this hostname
    http:
      paths:
      - path: /                         # All paths
        pathType: Prefix
        backend:
          service:
            name: api-service           # Forward to this K8s service
            port:
              number: 80
  - host: www.myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

### 4.2 Path-Based Routing (Single Domain, Multiple Services)

```yaml
# ingress-path-based.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: microservices-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"        # Enable regex paths
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /api/users                # Requests to /api/users → user-service
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 8080
      - path: /api/orders               # Requests to /api/orders → order-service
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 8080
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 8080
      - path: /                         # Everything else → frontend
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

### 4.3 TLS Termination with cert-manager

```bash
# Step 1: Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager pods
kubectl get pods -n cert-manager
# Expected: cert-manager-xxx, cert-manager-cainjector-xxx, cert-manager-webhook-xxx all Running
```

```yaml
# clusterissuer-letsencrypt.yaml
# Defines HOW to request certificates from Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod               # Name referenced in Ingress annotation
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory  # Let's Encrypt prod
    email: devops@company.com          # Your email for expiry alerts
    privateKeySecretRef:
      name: letsencrypt-prod-key       # Secret to store ACME private key
    solvers:
    - http01:                          # HTTP-01 challenge (Nginx handles it)
        ingress:
          class: nginx
```

```yaml
# ingress-with-tls.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"     # Auto-issue cert
    nginx.ingress.kubernetes.io/ssl-redirect: "true"       # Force HTTPS
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com                # Domain for certificate
    secretName: myapp-tls-secret       # cert-manager will create this Secret
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

```bash
kubectl apply -f clusterissuer-letsencrypt.yaml
kubectl apply -f ingress-with-tls.yaml

# Monitor certificate issuance
kubectl get certificate
kubectl describe certificate myapp-tls-secret
# Expected: Status: True, Reason: Ready
```

### 4.4 Rate Limiting

```yaml
# ingress-rate-limited.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-rate-limited
  annotations:
    # Limit requests per second per IP
    nginx.ingress.kubernetes.io/limit-rps: "10"
    # Limit connections per IP
    nginx.ingress.kubernetes.io/limit-connections: "5"
    # Limit request rate per minute
    nginx.ingress.kubernetes.io/limit-rpm: "100"
    # Whitelist IPs that bypass rate limiting
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8,172.16.0.0/12"
    # Return 429 instead of 503 when limited
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
spec:
  ingressClassName: nginx
  rules:
  - host: api.myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
```

### 4.5 Basic Authentication

```bash
# Create htpasswd file
htpasswd -c auth admin
# Enter password when prompted

# Create K8s Secret from htpasswd file
kubectl create secret generic basic-auth \
  --from-file=auth \
  --namespace default
```

```yaml
# ingress-basic-auth.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: protected-ingress
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic           # Basic auth type
    nginx.ingress.kubernetes.io/auth-secret: basic-auth    # Secret with htpasswd
    nginx.ingress.kubernetes.io/auth-realm: "Protected Area"  # Browser prompt text
spec:
  ingressClassName: nginx
  rules:
  - host: admin.myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 80
```

### 4.6 Global Nginx Configuration (ConfigMap)

```yaml
# nginx-configmap.yaml
# Tunes global Nginx behavior
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller        # Must match controller's --configmap arg
  namespace: ingress-nginx
data:
  # Worker processes (usually = CPU cores)
  worker-processes: "auto"
  # Max connections per worker
  max-worker-connections: "65536"
  # Enable gzip compression
  use-gzip: "true"
  gzip-level: "5"
  gzip-types: "application/json text/plain text/css application/javascript"
  # Proxy timeouts
  proxy-connect-timeout: "15"
  proxy-send-timeout: "600"
  proxy-read-timeout: "600"
  # Body size limit (increase for file uploads)
  proxy-body-size: "50m"
  # Enable real IP from X-Forwarded-For
  use-forwarded-headers: "true"
  # SSL protocols
  ssl-protocols: "TLSv1.2 TLSv1.3"
  # HSTS
  hsts: "true"
  hsts-max-age: "31536000"
```

### 4.7 Sticky Sessions

```yaml
# ingress-sticky-sessions.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sticky-ingress
  annotations:
    # Enable sticky sessions (cookie-based)
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "INGRESSCOOKIE"
    nginx.ingress.kubernetes.io/session-cookie-expires: "172800"   # 2 days
    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"
    nginx.ingress.kubernetes.io/session-cookie-path: "/"
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: stateful-app
            port:
              number: 80
```

---

## 5. Integration with Existing Tools

### Expose ArgoCD via Nginx Ingress

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"    # Pass TLS to ArgoCD (it handles its own TLS)
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.mycompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

### Expose Jenkins via Nginx Ingress with TLS

```yaml
# jenkins-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-ingress
  namespace: jenkins
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "500m"    # Jenkins builds upload artifacts
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600" # Long-running builds
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - jenkins.mycompany.com
    secretName: jenkins-tls
  rules:
  - host: jenkins.mycompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jenkins
            port:
              number: 8080
```

### Prometheus — Scrape Nginx Metrics

```yaml
# nginx-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-ingress-metrics
  namespace: monitoring
  labels:
    release: prometheus                  # Must match Prometheus operator selector
spec:
  namespaceSelector:
    matchNames:
    - ingress-nginx
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  endpoints:
  - port: metrics                        # Port named 'metrics' on Nginx controller svc
    interval: 30s
    path: /metrics
```

```bash
# Useful Nginx PromQL queries:
# Request rate: rate(nginx_ingress_controller_requests[5m])
# Error rate:   rate(nginx_ingress_controller_requests{status=~"5.."}[5m])
# P99 latency:  histogram_quantile(0.99, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m]))
```

### Grafana — Nginx Dashboard

```bash
# Import Nginx Ingress dashboard
# In Grafana: + → Import → Dashboard ID: 9614 → Select Prometheus → Import

# Key panels to monitor:
# - Request rate by ingress
# - 4xx/5xx error rate
# - Connections
# - Request duration percentiles
```

---

## 6. Real-World Scenarios

### Scenario 1: Path-Based Routing for Microservices App

**Objective:** Route `/api/*`, `/auth/*`, `/static/*` to different backend services under one domain.

```bash
# Step 1: Deploy sample services
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:0.2.3
        args: ["-text=API Service Response"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
      - name: auth
        image: hashicorp/http-echo:0.2.3
        args: ["-text=Auth Service Response"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
spec:
  selector:
    app: auth
  ports:
  - port: 80
    targetPort: 5678
EOF

# Step 2: Apply path-based ingress
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: microservices-ingress
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 80
EOF

# Step 3: Test routing (add to /etc/hosts first)
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$INGRESS_IP myapp.local" | sudo tee -a /etc/hosts

# Verify routing
curl http://myapp.local/api
# Expected: API Service Response
curl http://myapp.local/auth
# Expected: Auth Service Response
```

### Scenario 2: TLS with cert-manager (Self-Signed for Local Dev)

```bash
# For local dev, use self-signed issuer instead of Let's Encrypt
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-local-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
EOF

# Verify certificate
kubectl get certificate
# Expected: READY=True

# Test HTTPS
curl -k https://myapp.local/api
# Expected: API Service Response (with self-signed cert)
```

### Scenario 3: Rate Limiting for API Protection

```bash
# Deploy API and apply rate limiting
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limited-api
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "5"
    nginx.ingress.kubernetes.io/limit-connections: "3"
spec:
  ingressClassName: nginx
  rules:
  - host: api.myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
EOF

# Test rate limiting — send 20 rapid requests
for i in {1..20}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://api.myapp.local/)
  echo "Request $i: $STATUS"
done
# Expected: First 5 return 200, then 429 Too Many Requests
```

---

## 7. Verification & Testing

```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50

# Check ingress resources
kubectl get ingress -A
kubectl describe ingress <name>

# Check ingress controller service (should have external IP)
kubectl get svc -n ingress-nginx

# Test an ingress route
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: myapp.example.com" http://$INGRESS_IP/

# Validate TLS certificate
echo | openssl s_client -connect myapp.example.com:443 -servername myapp.example.com 2>&1 | grep "subject="

# Check cert-manager certificate status
kubectl get certificate -A
kubectl describe certificate <cert-name>

# Test nginx config validity
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -t
```

---

## 8. Troubleshooting Guide

| Issue | Symptom | Fix |
|-------|---------|-----|
| Ingress has no address | `ADDRESS` column empty | Check ingress controller pod is running; run `minikube tunnel` for local |
| 404 from ingress | All requests get 404 | Verify `ingressClassName: nginx` in spec; check host header matches |
| 503 Service Unavailable | Backend unreachable | Check backend Service exists and pod is Running |
| cert-manager cert pending | `READY=False` | Describe certificate; check ClusterIssuer is Ready; verify DNS |
| TLS redirect loop | Browser infinite redirect | Check `ssl-redirect` annotation and Service port |
| Rate limiting not working | No 429 responses | Verify nginx-controller ConfigMap has `limit-req-zone` configured |
| Large file upload fails | 413 Entity Too Large | Add annotation: `nginx.ingress.kubernetes.io/proxy-body-size: "100m"` |
| Timeout on long requests | 504 Gateway Timeout | Add `proxy-read-timeout` and `proxy-send-timeout` annotations |
| SSL passthrough not working | TLS cert mismatch | Install controller with `--enable-ssl-passthrough` flag |
| Annotations not applied | Config ignored | Delete and re-create ingress; check annotation spelling exactly |

---

## 9. Cheat Sheet

```bash
# Install
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

# Get ingress controller IP
kubectl get svc ingress-nginx-controller -n ingress-nginx

# List all ingresses
kubectl get ingress -A

# Describe ingress (shows rules and backend)
kubectl describe ingress <name>

# Check controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100

# Test config
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -t

# Get cert-manager certs
kubectl get certificate -A

# Annotate ingress for rate limiting
kubectl annotate ingress <name> nginx.ingress.kubernetes.io/limit-rps="10"

# Force TLS redirect
kubectl annotate ingress <name> nginx.ingress.kubernetes.io/ssl-redirect="true"

# Useful annotations reference:
# nginx.ingress.kubernetes.io/rewrite-target: /           # Strip path prefix
# nginx.ingress.kubernetes.io/proxy-body-size: "50m"      # Upload size limit
# nginx.ingress.kubernetes.io/proxy-read-timeout: "600"   # Read timeout (s)
# nginx.ingress.kubernetes.io/limit-rps: "10"             # Rate limit req/s
# nginx.ingress.kubernetes.io/auth-type: basic            # Basic auth
# cert-manager.io/cluster-issuer: "letsencrypt-prod"      # Auto TLS cert
# nginx.ingress.kubernetes.io/ssl-passthrough: "true"     # Pass TLS through
# nginx.ingress.kubernetes.io/affinity: "cookie"          # Sticky sessions
```
