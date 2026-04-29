# Guide 04 — NGINX in Kubernetes (Pods and Ingress)

## Goal of This Guide

By the end you will understand:
- How NGINX Ingress Controller works in Kubernetes
- How to install it in Minikube (local) and AKS (production)
- How to route traffic to multiple pods using Ingress rules
- How to use NGINX as a **sidecar container** inside a pod
- How to debug ingress issues in Kubernetes

---

## 1. Two Ways to Use NGINX in Kubernetes

| Pattern | What It Is | When to Use |
|---------|-----------|-------------|
| **NGINX Ingress Controller** | A dedicated NGINX pod that reads Ingress objects and routes all external traffic | Entry point for all external HTTP/HTTPS to the cluster |
| **NGINX as a sidecar** | NGINX container running inside the same pod as your app | When your app can only serve HTTP internally and needs TLS termination at the pod level |

**In 99% of cases, you want NGINX Ingress Controller.** The sidecar pattern is rare and advanced.

---

## 2. How NGINX Ingress Works in Kubernetes

```
Browser → https://shop.myapp.com/api/products
           │
           ▼
    Azure Load Balancer (AKS) or Minikube tunnel
    External IP: 20.50.100.200
           │
           ▼
    ingress-nginx-controller Pod
    (NGINX running inside a pod, watching Ingress objects)
           │
    Reads this Ingress object:
    ┌──────────────────────────────────────────┐
    │  host: shop.myapp.com                    │
    │  /api/products → product-service:80      │
    │  /api/users    → user-service:80         │
    │  /             → api-gateway:80          │
    └──────────────────────────────────────────┘
           │
    Matches path /api/products
           │
           ▼
    product-service (ClusterIP Service)
           │
           ▼
    product-service Pod(s)
```

Key point: You do **not** edit `nginx.conf` directly in Kubernetes.
Instead, you create `Ingress` YAML objects and the controller translates them into NGINX config automatically.

---

## 3. Install NGINX Ingress Controller on Minikube

### Option A — Minikube built-in addon (fastest for local dev)

```bash
# Enable the ingress addon
minikube addons enable ingress

# Wait for the controller to be ready (takes 1-2 minutes)
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx
# Expected:
# deployment "ingress-nginx-controller" successfully rolled out

# Verify pods are running
kubectl get pods -n ingress-nginx
# Expected:
# NAME                                        READY   STATUS
# ingress-nginx-controller-7799c6795f-xxxxx   1/1     Running
```

### Option B — Helm install (production-like setup for Minikube)

```bash
# Add the Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Create namespace
kubectl create namespace ingress-nginx

# Install with Helm
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.replicaCount=1 \
  --wait     # ← wait until pods are ready before returning

# Verify
kubectl get svc -n ingress-nginx
# Expected:
# NAME                                 TYPE           EXTERNAL-IP
# ingress-nginx-controller             LoadBalancer   <pending>   ← pending on Minikube without tunnel

# Start Minikube tunnel to get an external IP (run in separate terminal)
minikube tunnel
# Now EXTERNAL-IP will show 127.0.0.1
```

---

## 4. Deploy the Sample Apps (3 Microservices)

We will deploy three services that represent an ecommerce app: `api-gateway`, `product-service`, `user-service`.

### Create the namespace

```bash
kubectl create namespace dev
```

### Deploy api-gateway

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: dev
spec:
  replicas: 2                            # ← run 2 pods for availability
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: api-gateway
        image: hashicorp/http-echo        # ← simple HTTP echo server for testing
        args:
        - "-text=Hello from api-gateway"
        ports:
        - containerPort: 5678
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: dev
spec:
  selector:
    app: api-gateway
  ports:
  - port: 80                              # ← NGINX: Ingress will target port 80 of this service
    targetPort: 5678
EOF
```

### Deploy product-service

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
    spec:
      containers:
      - name: product-service
        image: hashicorp/http-echo
        args:
        - "-text=Hello from product-service"
        ports:
        - containerPort: 5678
        resources:
          requests: { memory: "64Mi", cpu: "50m" }
          limits:   { memory: "128Mi", cpu: "200m" }
---
apiVersion: v1
kind: Service
metadata:
  name: product-service
  namespace: dev
spec:
  selector:
    app: product-service
  ports:
  - port: 80
    targetPort: 5678
EOF
```

### Deploy user-service

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: hashicorp/http-echo
        args:
        - "-text=Hello from user-service"
        ports:
        - containerPort: 5678
        resources:
          requests: { memory: "64Mi", cpu: "50m" }
          limits:   { memory: "128Mi", cpu: "200m" }
---
apiVersion: v1
kind: Service
metadata:
  name: user-service
  namespace: dev
spec:
  selector:
    app: user-service
  ports:
  - port: 80
    targetPort: 5678
EOF
```

### Verify all pods are running

```bash
kubectl get pods,svc -n dev
# Expected:
# NAME                                   READY   STATUS
# pod/api-gateway-xxx                    1/1     Running
# pod/product-service-xxx                1/1     Running
# pod/user-service-xxx                   1/1     Running
# NAME                   TYPE        CLUSTER-IP    PORT(S)
# service/api-gateway    ClusterIP   10.96.x.x     80/TCP
# service/product-service ClusterIP  10.96.x.x     80/TCP
# service/user-service   ClusterIP   10.96.x.x     80/TCP
```

---

## 5. Create the Ingress Object — Path-Based Routing

This is the core of NGINX Ingress. One Ingress object routes to all 3 services.

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: dev                           # ← NGINX: must be same namespace as services
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /           # ← NGINX: strip the path prefix before forwarding
    nginx.ingress.kubernetes.io/use-regex: "true"           # ← NGINX: allow regex in path rules
spec:
  ingressClassName: nginx                  # ← NGINX: tells Kubernetes which Ingress Controller to use
  rules:
  - host: shop.local                       # ← NGINX: only handle requests for this hostname
    http:
      paths:
      - path: /api/products(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: product-service          # ← NGINX: route to product-service
            port:
              number: 80
      - path: /api/users(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: user-service             # ← NGINX: route to user-service
            port:
              number: 80
      - path: /(.*)
        pathType: Prefix
        backend:
          service:
            name: api-gateway              # ← NGINX: catch-all to api-gateway
            port:
              number: 80
EOF
```

### Mandatory Lines Table — Ingress object

| Line | Why It Is Mandatory |
|------|---------------------|
| `namespace: dev` | Ingress must be in the same namespace as the backend Services |
| `rewrite-target: /` | Without this, the full path `/api/products/list` is forwarded to the backend which may not have that route |
| `ingressClassName: nginx` | Without this, the Ingress object is ignored — no controller picks it up |
| `host: shop.local` | Without a host, NGINX tries to match all hostnames — can cause conflicts |
| `port.number: 80` | Must match the `port` defined in the Service (not `targetPort`) |

### Verify the Ingress was created

```bash
kubectl get ingress -n dev
# Expected:
# NAME                 CLASS   HOSTS        ADDRESS        PORTS
# ecommerce-ingress    nginx   shop.local   192.168.49.2   80
```

---

## 6. Test the Routing

### On Minikube — add the host entry

```bash
# Get Minikube IP
minikube ip
# e.g., 192.168.49.2

# Add to your hosts file (Windows: C:\Windows\System32\drivers\etc\hosts)
# Add this line:
# 192.168.49.2 shop.local
```

```bash
# Test each route
curl http://shop.local/api/products
# Expected: Hello from product-service

curl http://shop.local/api/users
# Expected: Hello from user-service

curl http://shop.local/
# Expected: Hello from api-gateway
```

---

## 7. Host-Based Routing (Multiple Domains, One Ingress Controller)

You can also route by domain name instead of path. This is common when you have separate subdomains per service.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based-ingress
  namespace: dev
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: api.shop.local                 # ← NGINX: route for api subdomain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 80

  - host: products.shop.local            # ← NGINX: route for products subdomain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 80

  - host: users.shop.local               # ← NGINX: route for users subdomain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 80
```

---

## 8. NGINX as a Sidecar Container in a Pod

Use this pattern when: your app does not support HTTPS natively, and you want TLS termination at the pod level.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-nginx-sidecar
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-with-nginx-sidecar
  template:
    metadata:
      labels:
        app: app-with-nginx-sidecar
    spec:
      containers:
      # Main application container
      - name: myapp
        image: hashicorp/http-echo
        args: ["-text=Hello from myapp", "-listen=:3000"]
        ports:
        - containerPort: 3000

      # NGINX sidecar — handles HTTPS and forwards to myapp
      - name: nginx-sidecar
        image: nginx:1.25-alpine            # ← NGINX: lightweight NGINX image
        ports:
        - containerPort: 443
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d/     # ← NGINX: where custom config goes
        - name: tls-certs
          mountPath: /etc/nginx/ssl/        # ← NGINX: where TLS certs are mounted

      volumes:
      - name: nginx-config
        configMap:
          name: nginx-sidecar-config        # ← NGINX: config provided via ConfigMap
      - name: tls-certs
        secret:
          secretName: myapp-tls             # ← NGINX: TLS certs from Kubernetes Secret
```

ConfigMap for the sidecar:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-sidecar-config
  namespace: dev
data:
  default.conf: |
    server {
        listen 443 ssl;
        ssl_certificate     /etc/nginx/ssl/tls.crt;
        ssl_certificate_key /etc/nginx/ssl/tls.key;
        location / {
            proxy_pass http://127.0.0.1:3000;    # ← NGINX: forward to main app on localhost
        }
    }
```

---

## 9. Key kubectl Commands for NGINX Ingress

```bash
# List all Ingress objects across all namespaces
kubectl get ingress -A

# Describe an Ingress (shows routing rules and events)
kubectl describe ingress ecommerce-ingress -n dev

# View NGINX Ingress Controller logs (critical for debugging)
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# View NGINX Ingress Controller logs in real time
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Get the actual nginx.conf generated by the controller
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf

# Check Ingress Controller events
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'

# Port-forward the Ingress Controller directly (bypass DNS)
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80

# Test a path using port-forward
curl -H "Host: shop.local" http://localhost:8080/api/products
```

---

## 10. Scenario — 404 Not Found After Deploying Ingress

**Goal:** Understand why Ingress returns 404 even when the service exists.

**Trigger:**
```bash
curl http://shop.local/api/products
# Returns: 404 Not Found
```

**Diagnose — Check if the Ingress is configured correctly:**
```bash
kubectl describe ingress ecommerce-ingress -n dev
# Look for: "Backends: product-service:80 (10.x.x.x:5678)"
# If backends show <error> it means the Service is not found
```

**Check if ingressClassName is set:**
```bash
kubectl get ingress ecommerce-ingress -n dev -o yaml | grep ingressClassName
# If this is missing, the controller ignores the Ingress
```

**Check if pods are actually running:**
```bash
kubectl get pods -n dev -l app=product-service
# If 0/1 Running, the service has no healthy backends → NGINX returns 503
```

**Fix — Common causes of 404:**

| Cause | Fix |
|-------|-----|
| Missing `ingressClassName: nginx` | Add annotation to Ingress spec |
| Wrong service name | Run `kubectl get svc -n dev` and check exact name |
| Wrong port number | Service port must match what Ingress specifies |
| `rewrite-target` stripping wrong part | Check the path regex and rewrite-target together |
| No pods selected by service | Check service selector matches pod labels |

---

## What to Do Next

Read [05-nginx-on-azure.md](05-nginx-on-azure.md) to deploy NGINX on Azure VM and AKS with a real Load Balancer IP.
