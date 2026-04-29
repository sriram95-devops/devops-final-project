# Guide 05 — NGINX on Azure (VM and AKS)

## Goal of This Guide

By the end you will:
- Run NGINX on an Azure Ubuntu VM as a reverse proxy
- Deploy NGINX Ingress Controller on AKS (Azure Kubernetes Service)
- Understand how Azure Load Balancer integrates with NGINX
- Use Azure Container Registry (ACR) with NGINX Ingress
- Set up TLS with cert-manager on AKS

---

## 1. Azure Architecture Overview

### NGINX on Azure VM

```
                       Internet
                           │
                    Azure Public IP
                    (e.g., 20.50.100.5)
                           │
                ┌──────────▼──────────┐
                │  Azure VM (Ubuntu)  │
                │  Standard_B2s       │
                │                     │
                │  NGINX :80 / :443   │
                │    │      │      │  │
                │  :3000  :3001  :3002│
                │  App1   App2   App3 │
                └─────────────────────┘
                         │
                   Azure NSG (firewall rules)
                   Allow port 80, 443, 22
```

### NGINX Ingress on AKS

```
                       Internet
                           │
                  Azure Standard Load Balancer
                  External IP: 20.50.100.5
                           │
                ┌──────────▼──────────────────────┐
                │          AKS Cluster             │
                │                                  │
                │  ingress-nginx-controller pod    │
                │         │        │        │      │
                │     :80 path  :443 path         │
                │         │        │               │
                │   ┌─────▼──┐ ┌───▼────┐          │
                │   │product │ │  user  │          │
                │   │service │ │service │          │
                │   │pod(s)  │ │ pod(s) │          │
                └─────────────────────────────────-┘
```

---

## 2. NGINX on an Azure VM

### Step 1 — Create the Azure VM

```bash
# Login to Azure
az login

# Create a resource group
az group create --name rg-nginx-demo --location eastus

# Create the Ubuntu VM
az vm create \
  --resource-group rg-nginx-demo \
  --name vm-nginx \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --output table
# Expected:
# PublicIpAddress: 20.50.100.5  ← your server IP
```

### Step 2 — Open firewall ports (Azure NSG)

```bash
# Allow HTTP
az vm open-port --resource-group rg-nginx-demo --name vm-nginx --port 80 --priority 100

# Allow HTTPS
az vm open-port --resource-group rg-nginx-demo --name vm-nginx --port 443 --priority 101

# SSH is already open (port 22 opened by default)
```

### Step 3 — SSH into the VM and install NGINX

```bash
# SSH into the VM
ssh azureuser@20.50.100.5    # <-- REPLACE with your VM's Public IP

# Update and install NGINX
sudo apt update && sudo apt upgrade -y
sudo apt install nginx -y

# Start and enable
sudo systemctl start nginx
sudo systemctl enable nginx

# Test from outside — open browser to:
# http://20.50.100.5
# You will see: Welcome to nginx!
```

### Step 4 — Configure NGINX for 3 services

```bash
# Create the NGINX site config
sudo tee /etc/nginx/sites-available/ecommerce <<'EOF'
upstream api_gateway    { server 127.0.0.1:3000; }
upstream product_svc    { server 127.0.0.1:3001; }
upstream user_svc       { server 127.0.0.1:3002; }

server {
    listen 80;
    server_name _;            # Accept requests on the public IP

    access_log /var/log/nginx/ecommerce_access.log;
    error_log  /var/log/nginx/ecommerce_error.log;

    location /api/products {
        proxy_pass http://product_svc;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/users {
        proxy_pass http://user_svc;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://api_gateway;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable and reload
sudo ln -s /etc/nginx/sites-available/ecommerce /etc/nginx/sites-enabled/ecommerce
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo nginx -s reload
```

### Step 5 — Add HTTPS with Let's Encrypt on Azure VM

```bash
# You need a domain name pointing to your VM's public IP
# Add A record: yourdomain.com → 20.50.100.5

# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Get the certificate
sudo certbot --nginx -d yourdomain.com --non-interactive --agree-tos -m admin@yourdomain.com
# Expected:
# Successfully deployed certificate for yourdomain.com

# Test auto-renewal
sudo certbot renew --dry-run
```

---

## 3. NGINX Ingress Controller on AKS

### Step 1 — Create the AKS Cluster

```bash
# Create AKS cluster (this takes 5-10 minutes)
az aks create \
  --resource-group rg-nginx-demo \
  --name aks-nginx-demo \
  --node-count 2 \
  --node-vm-size Standard_B2s \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --output table

# Connect kubectl to the cluster
az aks get-credentials \
  --resource-group rg-nginx-demo \
  --name aks-nginx-demo \
  --overwrite-existing

# Verify
kubectl get nodes
# Expected:
# NAME                                STATUS   ROLES
# aks-nodepool1-xxx-vmss000000        Ready    agent
# aks-nodepool1-xxx-vmss000001        Ready    agent
```

### Step 2 — Install NGINX Ingress Controller with Helm

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install in its own namespace
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \                          # ← 2 replicas for HA
  --set controller.nodeSelector."kubernetes\.io/os"=linux \  # ← AKS node selector
  --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --wait

# Get the public IP assigned by Azure Load Balancer
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Expected (wait 2-3 minutes for IP):
# NAME                       TYPE           EXTERNAL-IP      PORTS
# ingress-nginx-controller   LoadBalancer   20.50.100.200    80:30xxx/TCP,443:31xxx/TCP
```

### Step 3 — Deploy the Sample Apps on AKS

```bash
# Create namespace
kubectl create namespace dev

# Deploy all 3 services (same YAML as Guide 04)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: dev
spec:
  replicas: 2
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
        image: hashicorp/http-echo
        args: ["-text=Hello from api-gateway"]
        ports:
        - containerPort: 5678
        resources:
          requests: { memory: "64Mi", cpu: "50m" }
          limits:   { memory: "128Mi", cpu: "200m" }
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
  - port: 80
    targetPort: 5678
---
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
        args: ["-text=Hello from product-service"]
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
---
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
        args: ["-text=Hello from user-service"]
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

kubectl rollout status deployment/api-gateway -n dev
kubectl rollout status deployment/product-service -n dev
kubectl rollout status deployment/user-service -n dev
```

### Step 4 — Create Ingress with TLS on AKS

```bash
# Install cert-manager (manages Let's Encrypt certificates automatically)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait

# Create a ClusterIssuer (tells cert-manager how to get certs from Let's Encrypt)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory  # ← Let's Encrypt production URL
    email: admin@yourdomain.com                              # ← REPLACE with your email
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx                                        # ← use NGINX to respond to ACME challenges
EOF
```

```bash
# Create the Ingress with TLS
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: dev
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/use-regex: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod        # ← NGINX: use cert-manager to get TLS cert
spec:
  ingressClassName: nginx                                    # ← NGINX: which controller handles this
  tls:
  - hosts:
    - shop.yourdomain.com                                    # ← REPLACE with your domain
    secretName: ecommerce-tls                                # ← NGINX: name of secret cert-manager will create
  rules:
  - host: shop.yourdomain.com                                # ← REPLACE with your domain
    http:
      paths:
      - path: /api/products(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 80
      - path: /api/users(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 80
      - path: /(.*)
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 80
EOF
```

### Mandatory Lines Table — AKS Ingress with TLS

| Line | Why It Is Mandatory |
|------|---------------------|
| `ingressClassName: nginx` | Without this, AKS ignores the Ingress object |
| `cert-manager.io/cluster-issuer: letsencrypt-prod` | Without this, cert-manager does not create the TLS certificate |
| `tls.hosts[]` | Must match the `host` in the rules exactly, or the certificate will not cover your domain |
| `tls.secretName` | cert-manager creates a Secret with this name; NGINX reads TLS from it |
| `azure-load-balancer-health-probe-request-path=/healthz` | Without this, the Azure Load Balancer health probe may fail and remove the nodes |

### Step 5 — Verify TLS is working

```bash
# Watch for cert-manager to issue the certificate
kubectl get certificate -n dev -w
# Expected (after 2-5 minutes):
# NAME             READY   SECRET          AGE
# ecommerce-tls    True    ecommerce-tls   3m

# Test HTTPS
curl https://shop.yourdomain.com/api/products
# Expected: Hello from product-service
```

---

## 4. Using Azure Container Registry (ACR) with NGINX Ingress

If your apps use private images from ACR:

```bash
# Create ACR
az acr create \
  --resource-group rg-nginx-demo \
  --name myacrregistry \
  --sku Basic

# Attach ACR to AKS (so AKS can pull images without a password)
az aks update \
  --resource-group rg-nginx-demo \
  --name aks-nginx-demo \
  --attach-acr myacrregistry

# Push your app image to ACR
az acr build \
  --registry myacrregistry \
  --image api-gateway:v1.0 \
  --file Dockerfile .

# Use the ACR image in your Deployment
# image: myacrregistry.azurecr.io/api-gateway:v1.0
```

---

## 5. Scale and Monitor NGINX on AKS

```bash
# Scale the ingress controller to 3 replicas
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=3

# View NGINX Ingress metrics (if Prometheus is installed)
kubectl port-forward svc/ingress-nginx-controller-metrics -n ingress-nginx 9913:10254
curl http://localhost:9913/metrics | grep nginx_ingress_controller_requests

# View Ingress Controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100

# View the generated nginx.conf
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -T
```

---

## 6. Clean Up Azure Resources

```bash
# Delete everything when done (to avoid Azure costs)
az group delete --name rg-nginx-demo --yes --no-wait
# This deletes: VM, AKS cluster, Load Balancer, NSG, all resources in the group
```

---

## What to Do Next

Read [06-nginx-debug-troubleshoot.md](06-nginx-debug-troubleshoot.md) to learn how to diagnose and fix every common NGINX error across all environments.
