# Guide 06 — NGINX Debug and Troubleshoot

## Goal of This Guide

This guide teaches you to diagnose and fix every common NGINX error.
Each problem includes: what it looks like, what causes it, and exactly how to fix it.

Sections:
1. How to read NGINX logs
2. Debug mode and verbose logging
3. Config testing and validation
4. Error code reference (502, 504, 403, 404, 499, 413)
5. On-prem server troubleshooting
6. Kubernetes/Ingress troubleshooting
7. Azure-specific troubleshooting
8. Performance debugging
9. Step-by-step debug workflow

---

## 1. How to Read NGINX Logs

### Access log format

Every HTTP request is written to the access log:

```
192.168.1.10 - - [29/Apr/2026:10:30:00 +0000] "GET /api/products HTTP/1.1" 200 1234 "-" "curl/7.81.0"
│             │   │                             │                           │   │
│             │   │                             │                           │   └── response body bytes
│             │   │                             │                           └────── HTTP status code
│             │   │                             └────────────────────────────────── HTTP method + path + protocol
│             │   └──────────────────────────────────────────────────────────────── timestamp
│             └──────────────────────────────────────────────────────────────────── unused (auth)
└────────────────────────────────────────────────────────────────────────────────── client IP address
```

### Error log format

```
2026/04/29 10:30:00 [error] 1234#1234: *5 connect() failed (111: Connection refused)
                    │       │           │  └── error details
                    │       │           └───── request ID
                    │       └───────────────── NGINX worker process ID
                    └───────────────────────── log level (error/warn/crit)
```

### View logs in each environment

```bash
# On-prem / Azure VM
sudo tail -f /var/log/nginx/access.log       # real-time access log
sudo tail -f /var/log/nginx/error.log        # real-time error log
sudo tail -100 /var/log/nginx/error.log      # last 100 lines

# Custom app logs (if you set access_log in your site config)
sudo tail -f /var/log/nginx/myapp_access.log

# Kubernetes — view Ingress Controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50

# Kubernetes — view logs from a specific pod (if controller has multiple replicas)
kubectl logs -n ingress-nginx <pod-name> -f
```

---

## 2. Debug Mode and Verbose Logging

### Enable debug logging on a server

```bash
sudo nano /etc/nginx/nginx.conf
```

Change the error_log line:

```nginx
# Normal (default)
error_log /var/log/nginx/error.log;

# Debug mode — shows every connection decision NGINX makes
error_log /var/log/nginx/error.log debug;
```

```bash
sudo nginx -t && sudo nginx -s reload
# Warning: debug mode is VERY verbose. Use only when investigating a specific problem.
# Turn it off immediately after debugging.
```

### Enable debug logging in Kubernetes

```bash
# Get the controller pod name
kubectl get pods -n ingress-nginx
# NAME: ingress-nginx-controller-7799c6795f-xxxxx

# Execute debug nginx config reload in the pod
kubectl exec -n ingress-nginx <pod-name> -- nginx -T 2>&1 | grep -A5 "upstream"

# Enable debug via Helm upgrade
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.extraArgs.v=5   # ← increase verbosity (1-5)
```

---

## 3. Config Testing and Validation

**Always test your config before applying it.** If NGINX finds a syntax error, it will refuse to reload and your old config stays active. This prevents downtime.

```bash
# Test config syntax — the most important command you will use
sudo nginx -t

# If config is valid:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# If config has an error:
# nginx: [emerg] unknown directive "proxey_pass" in /etc/nginx/sites-available/myapp:10
#        └── tells you exactly which file and line number has the error

# Print the full effective config (all includes merged into one output)
sudo nginx -T

# Test then reload in one command (safe — only reloads if test passes)
sudo nginx -t && sudo nginx -s reload
```

---

## 4. Error Code Reference

### 502 Bad Gateway

**What it looks like:**
```
<html><head><title>502 Bad Gateway</title></head>
<body><center><h1>502 Bad Gateway</h1></center><hr><center>nginx</center></body></html>
```

**What it means:** NGINX reached the backend but the backend:
- Is not running
- Crashed and refused the connection
- Returned an invalid HTTP response

**How to diagnose:**
```bash
# Check the error log
sudo tail /var/log/nginx/error.log
# You will see:
# connect() failed (111: Connection refused) while connecting to upstream
# upstream: "http://127.0.0.1:3001"

# Check if the backend app is running
sudo systemctl status product-service
curl http://127.0.0.1:3001   # Test directly

# In Kubernetes
kubectl get pods -n dev -l app=product-service
kubectl logs -n dev deployment/product-service
```

**How to fix:**
```bash
# On-prem: restart the backend
sudo systemctl restart product-service

# Kubernetes: check pod status and restart if CrashLoopBackOff
kubectl rollout restart deployment/product-service -n dev
```

---

### 503 Service Unavailable

**What it means:** NGINX has no healthy backend to send the request to. All upstream servers are down or marked as failed.

**How to diagnose:**
```bash
# Check all pods in the target namespace
kubectl get pods -n dev

# In Ingress logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep "503"
```

**How to fix:**
```bash
# Scale up replicas
kubectl scale deployment product-service -n dev --replicas=2

# Check if the Service selector matches pod labels
kubectl get service product-service -n dev -o yaml | grep selector
kubectl get pods -n dev --show-labels | grep product-service
# The selector labels must match the pod labels exactly
```

---

### 504 Gateway Timeout

**What it means:** NGINX forwarded the request to the backend, but the backend took too long to respond.

**How to diagnose:**
```bash
sudo tail /var/log/nginx/error.log
# You will see:
# upstream timed out (110: Connection timed out) while reading response header from upstream
```

**How to fix:**
```nginx
# Increase proxy timeout values in your server block
location /api/slow-endpoint {
    proxy_pass http://backend;
    proxy_connect_timeout 60s;    # ← time to establish connection (default 60s)
    proxy_send_timeout    120s;   # ← time to send request to backend (default 60s)
    proxy_read_timeout    120s;   # ← time to wait for backend response (default 60s)
}
```

---

### 404 Not Found

**What it means:** NGINX could not match the request to any `location` block.

**How to diagnose:**
```bash
# Check which location blocks exist
sudo nginx -T | grep "location"

# In Kubernetes — check Ingress rules
kubectl describe ingress ecommerce-ingress -n dev
# Look at "Rules" section — are your paths there?
```

**Common causes:**
| Cause | Example | Fix |
|-------|---------|-----|
| Path in Ingress does not match request | Request: `/products`, Ingress: `/api/products` | Fix the Ingress path |
| `rewrite-target` removes wrong prefix | `/api/products` becomes `/api/products` not `/` | Fix the regex in path + rewrite-target |
| Wrong namespace | Ingress in `default`, Service in `dev` | Move Ingress to same namespace as Service |
| `ingressClassName` missing | No class → controller ignores Ingress | Add `ingressClassName: nginx` |

---

### 403 Forbidden

**What it means:** NGINX blocked the request (due to auth, IP restrictions, or file permissions).

**How to diagnose:**
```bash
sudo tail /var/log/nginx/error.log
# You will see:
# access forbidden by rule in /etc/nginx/sites-available/myapp:15
# OR
# directory index of "/var/www/html/" is forbidden
```

**How to fix:**
```bash
# File permission issue: NGINX worker (www-data) cannot read the file
ls -la /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/
```

---

### 499 Client Closed Request

**What it means:** The client (browser, curl, load balancer) disconnected before NGINX finished. Not NGINX's fault — usually the client timed out.

**In Kubernetes:** Often caused by the Azure Load Balancer health probe timing out, or a client timeout shorter than the backend response time.

---

### 413 Request Entity Too Large

**What it means:** The request body is bigger than NGINX allows (default 1MB).

**How to fix:**
```nginx
server {
    client_max_body_size 50M;   # ← NGINX: allow request bodies up to 50MB (for file uploads)
}
```

---

## 5. On-Prem Server Troubleshooting

### Step-by-step checklist

```bash
# Step 1 — Is NGINX running?
sudo systemctl status nginx
# If not running: sudo systemctl start nginx

# Step 2 — Is NGINX listening on the right port?
sudo ss -tlnp | grep nginx
# Expected: LISTEN on :80 and :443

# Step 3 — Is the config valid?
sudo nginx -t
# Fix any errors shown, then: sudo nginx -s reload

# Step 4 — Is the firewall blocking the port?
sudo ufw status
# Make sure 80 and 443 are ALLOW

# Step 5 — Can NGINX reach the backend?
curl http://127.0.0.1:3001   # test backend directly
# If this fails: sudo systemctl start product-service

# Step 6 — Does DNS resolve correctly?
nslookup myapp.yourdomain.com
# If DNS is wrong, requests hit the wrong server

# Step 7 — Check logs
sudo tail -50 /var/log/nginx/error.log
```

### Common on-prem errors

| Error Message | Cause | Fix |
|---------------|-------|-----|
| `bind() to 0.0.0.0:80 failed (98: Address already in use)` | Another process (Apache?) is on port 80 | `sudo ss -tlnp | grep :80` then stop the conflicting service |
| `open() "/etc/nginx/sites-enabled/x" failed (2: No such file)` | Config file does not exist | Check path with `ls /etc/nginx/sites-enabled/` |
| `no resolver defined to resolve` | You used a hostname in proxy_pass but no DNS resolver is configured | Add `resolver 8.8.8.8;` to http block |
| `SSL_CTX_use_certificate_file() failed` | Certificate file not found or wrong format | Check path with `ls -la /etc/nginx/ssl/` |

---

## 6. Kubernetes/Ingress Troubleshooting

### Step-by-step checklist

```bash
# Step 1 — Is the Ingress Controller running?
kubectl get pods -n ingress-nginx
# If not Running: kubectl describe pod <name> -n ingress-nginx

# Step 2 — Does the Ingress object exist and have an address?
kubectl get ingress -n dev
# If ADDRESS is empty: check the controller is healthy

# Step 3 — Describe the Ingress — check for errors
kubectl describe ingress ecommerce-ingress -n dev
# Look for "Events" at the bottom — errors appear here

# Step 4 — Are the backend Services and pods healthy?
kubectl get svc,pods -n dev
# Services must exist; pods must be Running and Ready (1/1)

# Step 5 — Test using port-forward (bypass DNS issues)
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
curl -H "Host: shop.local" http://localhost:8080/api/products
# This proves routing works even if DNS is not set up

# Step 6 — Check Ingress Controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100

# Step 7 — Check if Ingress class is correct
kubectl get ingressclass
# Expected: nginx (or whatever class name is installed)

# Step 8 — Verify the generated nginx.conf
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -A5 "shop.local"
```

### Kubernetes-specific errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| Ingress ADDRESS is empty | Controller not installed or ingressClass mismatch | `helm install ingress-nginx ...` or fix ingressClassName |
| 404 for all paths | Path regex does not match or rewrite-target wrong | Check `rewrite-target` annotation and path regex |
| 503 all pods | Service selector does not match pod labels | `kubectl describe svc` and compare to pod labels |
| TLS cert not issued | cert-manager not installed or ClusterIssuer wrong | `kubectl describe certificate -n dev` for error events |
| `Ingress does not contain a valid IngressClass` | Missing `ingressClassName` field | Add `ingressClassName: nginx` to Ingress spec |
| `no endpoints available for service` | All pods are NotReady | Wait for pods to start; check readinessProbe |

---

## 7. Azure-Specific Troubleshooting

### NGINX Ingress on AKS has no External IP

```bash
kubectl get svc -n ingress-nginx
# EXTERNAL-IP shows <pending>

# Cause 1: Azure Load Balancer quota exceeded
az network lb list --resource-group rg-nginx-demo --output table

# Cause 2: NSG blocks health probe
# Azure Load Balancer probes port 80/443 — NSG must allow this
az network nsg rule list --resource-group rg-nginx-demo --nsg-name <your-nsg>

# Fix: add health probe annotation
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set "controller.service.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path=/healthz"
```

### NGINX on Azure VM cannot be reached from outside

```bash
# Step 1 — Check NSG rules in Azure Portal or CLI
az network nsg rule list \
  --resource-group rg-nginx-demo \
  --nsg-name <your-nsg-name> \
  --output table
# Verify port 80 and 443 have Allow rules

# Step 2 — Check NGINX is listening
sudo ss -tlnp | grep nginx
# Must show 0.0.0.0:80

# Step 3 — Test from within the VM
curl http://localhost
# If this works but external does not, it is NSG or Azure firewall
```

---

## 8. Performance Debugging

### Check NGINX worker count

```bash
# Number of CPU cores on the server
nproc

# In nginx.conf, worker_processes should match
grep worker_processes /etc/nginx/nginx.conf
# Best practice: worker_processes auto;   # ← auto detects CPU count
```

### Check active connections

```bash
# Enable the status page in nginx.conf
location /nginx_status {
    stub_status;
    allow 127.0.0.1;       # ← only allow localhost to see this
    deny all;
}

# Read the status page
curl http://127.0.0.1/nginx_status
# Output:
# Active connections: 5
# server accepts handled requests
#  100 100 200
# Reading: 0 Writing: 1 Waiting: 4
```

### High load debugging

```bash
# Check how many NGINX worker processes are running
ps aux | grep nginx

# Check CPU and memory usage of NGINX
top -p $(pgrep -d',' nginx)

# Check error log for upstream connection issues (indicates backend is overloaded)
sudo grep "upstream" /var/log/nginx/error.log | tail -20
```

---

## 9. Full Debug Workflow — When Something Stops Working

Follow this workflow in order every time NGINX stops working:

```
1. Does the server/pod respond at all?
   ─ No → Is NGINX running? (systemctl status nginx / kubectl get pods -n ingress-nginx)
   ─ Yes → Continue to step 2

2. What HTTP status code are you getting?
   ─ 502 → Backend is down
   ─ 503 → No healthy backends / service misconfigured
   ─ 504 → Backend too slow
   ─ 404 → Path routing wrong
   ─ 403 → Access control / file permission
   ─ 499 → Client timeout (not NGINX)
   ─ 413 → Request body too large

3. Check the error log for the exact error message
   ─ sudo tail -50 /var/log/nginx/error.log
   ─ kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

4. Is the config valid?
   ─ sudo nginx -t

5. Can NGINX reach the backend directly?
   ─ curl http://127.0.0.1:3001         (on-prem)
   ─ kubectl exec -it <pod> -- curl http://product-service.dev.svc   (K8s)

6. Is DNS / hostname resolving correctly?
   ─ nslookup yourdomain.com
   ─ curl -H "Host: shop.local" http://<ip>   (test without DNS)

7. Are there firewall/NSG rules blocking traffic?
   ─ sudo ufw status                   (on-prem)
   ─ az network nsg rule list ...      (Azure)
```

---

## What to Do Next

Read [07-nginx-cheatsheet.md](07-nginx-cheatsheet.md) for quick reference during daily use.
