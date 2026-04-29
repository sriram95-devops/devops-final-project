# Guide 08 — Testing NGINX and Seeing It Work Visually

## Goal of This Guide

This guide gives you **runnable exercises** for every environment.
After each exercise you will see real output that proves NGINX is working.

Sections:
1. Test tools you will use
2. Exercise: test local NGINX (on-prem / Windows / WSL)
3. Exercise: test routing to multiple services
4. Exercise: test NGINX in Kubernetes (Minikube)
5. Exercise: visual NGINX status page in the browser
6. Exercise: watch live traffic flow in the terminal
7. Exercise: simulate failures and watch NGINX respond
8. Exercise: load test and watch NGINX handle it
9. Visual dashboards (Grafana + NGINX metrics)

---

## 1. Test Tools You Will Use

Install these once — you will use them across all exercises.

```bash
# curl — the primary HTTP testing tool
curl --version
# If not installed on Ubuntu: sudo apt install curl -y

# hey — HTTP load generator (shows requests per second, latency)
# Install on Linux:
wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O hey
chmod +x hey && sudo mv hey /usr/local/bin/hey
hey --version

# watch — repeat a command every N seconds
# Already installed on Ubuntu. On Windows WSL:
sudo apt install procps -y

# httpie — human-friendly curl alternative (optional but nice)
sudo apt install httpie -y
http --version
```

**VS Code extensions needed:**
- `REST Client` by Huachao Mao — send HTTP requests from `.http` files, see responses in VS Code
- `NGINX Configuration` by shanoor — syntax highlighting for nginx.conf

---

## 2. Exercise: Verify NGINX Is Running (On-Prem / WSL)

**Goal:** Confirm NGINX is alive and serving a response.

### Step 1 — Start NGINX

```bash
sudo systemctl start nginx
sudo systemctl status nginx
```

You will see (green Active):
```
● nginx.service - A high performance web server...
     Active: active (running) since Tue 2026-04-29 10:00:00 UTC; 5s ago
```

### Step 2 — Test with curl

```bash
curl -I http://localhost
```

You will see:
```
HTTP/1.1 200 OK
Server: nginx/1.24.0
Content-Type: text/html
Content-Length: 615
```

`200 OK` = NGINX is running and responding.

### Step 3 — Open in browser (WSL)

```bash
# Get your WSL IP
hostname -I | awk '{print $1}'
# e.g., 172.22.100.5
```

Open browser on Windows: `http://172.22.100.5`

You will see the **NGINX Welcome Page** — a grey page with "Welcome to nginx!".

### Step 4 — Confirm which config NGINX is using

```bash
sudo nginx -T | head -30
```

You will see the full merged config printed to the terminal. This proves exactly what NGINX loaded.

---

## 3. Exercise: Test Routing to Multiple Services

**Goal:** Prove NGINX sends `/api/products` to service A and `/api/users` to service B.

### Step 1 — Start two fake backend services

Open two terminals in VS Code (or two WSL windows):

```bash
# Terminal 1 — fake product service on port 3001
mkdir -p /tmp/products
echo '{"service":"product-service","status":"ok","items":["laptop","phone"]}' > /tmp/products/index.html
python3 -m http.server 3001 --directory /tmp/products
```

```bash
# Terminal 2 — fake user service on port 3002
mkdir -p /tmp/users
echo '{"service":"user-service","status":"ok","users":["alice","bob"]}' > /tmp/users/index.html
python3 -m http.server 3002 --directory /tmp/users
```

### Step 2 — Write the NGINX routing config

```bash
sudo tee /etc/nginx/sites-available/test-routing <<'EOF'
server {
    listen 8080;
    server_name localhost;

    location /api/products {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host $host;
    }

    location /api/users {
        proxy_pass http://127.0.0.1:3002/;
        proxy_set_header Host $host;
    }

    location / {
        return 200 '{"message":"NGINX routing is working. Try /api/products or /api/users"}';
        add_header Content-Type application/json;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/test-routing /etc/nginx/sites-enabled/test-routing
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo nginx -s reload
```

### Step 3 — Test each route

```bash
# Test root
curl http://localhost:8080/
```
Expected output:
```json
{"message":"NGINX routing is working. Try /api/products or /api/users"}
```

```bash
# Test product route
curl http://localhost:8080/api/products
```
Expected output:
```json
{"service":"product-service","status":"ok","items":["laptop","phone"]}
```

```bash
# Test user route
curl http://localhost:8080/api/users
```
Expected output:
```json
{"service":"user-service","status":"ok","users":["alice","bob"]}
```

### Step 4 — Prove which backend handled the request (using verbose headers)

```bash
curl -v http://localhost:8080/api/products 2>&1 | grep -E "< HTTP|< Server|< Content"
```

You will see:
```
< HTTP/1.1 200 OK
< Server: SimpleHTTP/0.6 Python/3.10.12    ← this proves NGINX forwarded to the Python server
< Content-type: application/json
```

### Step 5 — Test in VS Code REST Client

Create `test-nginx.http` in your project folder:

```http
### Test NGINX root
GET http://localhost:8080/

### Test product service via NGINX
GET http://localhost:8080/api/products

### Test user service via NGINX
GET http://localhost:8080/api/users
```

Click `Send Request` above each line. You will see the response appear in a panel on the right in VS Code.

---

## 4. Exercise: Test NGINX Ingress in Kubernetes (Minikube)

**Goal:** Prove NGINX Ingress routes traffic to the correct pod.

### Step 1 — Check everything is running

```bash
# Check NGINX Ingress Controller
kubectl get pods -n ingress-nginx
# All pods must be Running 1/1

# Check your app pods
kubectl get pods -n dev
# api-gateway, product-service, user-service must all be Running

# Check the Ingress object has an address
kubectl get ingress -n dev
# ADDRESS column must show an IP, not be empty
```

### Step 2 — Test with port-forward (no DNS needed)

```bash
# Start port-forward in background
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 &

# Test each route — the Host header tells NGINX which Ingress to match
curl -H "Host: shop.local" http://localhost:8080/
```
Expected:
```
Hello from api-gateway
```

```bash
curl -H "Host: shop.local" http://localhost:8080/api/products
```
Expected:
```
Hello from product-service
```

```bash
curl -H "Host: shop.local" http://localhost:8080/api/users
```
Expected:
```
Hello from user-service
```

### Step 3 — Prove NGINX hit the right pod by watching pod logs

Open two terminals:

```bash
# Terminal 1 — watch product-service pod logs
kubectl logs -n dev deployment/product-service -f
```

```bash
# Terminal 2 — send a request
curl -H "Host: shop.local" http://localhost:8080/api/products
```

In Terminal 1 you will see the request appear in the logs immediately:
```
2026/04/29 10:30:00 [info] request from 10.244.0.x "GET /api/products HTTP/1.1" → processed
```

This proves NGINX Ingress routed to the correct pod.

### Step 4 — Visual: see the routing rules NGINX generated

```bash
# View the actual nginx.conf inside the Ingress Controller pod
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
  cat /etc/nginx/nginx.conf | grep -A10 "shop.local"
```

You will see NGINX configuration blocks that were auto-generated from your Ingress object:
```nginx
## start server shop.local
server {
    server_name shop.local ;
    ...
    location ~* "^/api/products" {
        ...
        proxy_pass http://upstream_balancer;
```

---

## 5. Exercise: Visual NGINX Status Page in the Browser

**Goal:** See a live dashboard of NGINX connections in real time.

### Step 1 — Enable the status page

```bash
sudo tee /etc/nginx/sites-available/status-page <<'EOF'
server {
    listen 8081;                    # use a separate port for the status page
    server_name localhost;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;            # only localhost can see it
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/status-page /etc/nginx/sites-enabled/status-page
sudo nginx -t && sudo nginx -s reload
```

### Step 2 — View the status page

```bash
curl http://localhost:8081/nginx_status
```

You will see:
```
Active connections: 3
server accepts handled requests
 1024 1024 4096
Reading: 0 Writing: 1 Waiting: 2
```

What each number means:

| Field | Meaning |
|-------|---------|
| `Active connections` | Connections currently open (including waiting ones) |
| `accepts` | Total connections NGINX has ever accepted |
| `handled` | Total connections successfully handled (should equal accepts) |
| `requests` | Total HTTP requests processed |
| `Reading` | Requests where NGINX is reading the request header right now |
| `Writing` | Requests where NGINX is sending a response right now |
| `Waiting` | Keep-alive connections sitting idle (not active) |

### Step 3 — Watch the numbers change in real time

```bash
# Run this in one terminal — refreshes every 1 second
watch -n1 "curl -s http://localhost:8081/nginx_status"
```

```bash
# In another terminal — send repeated requests to see the numbers go up
for i in {1..20}; do curl -s http://localhost:8080/api/products > /dev/null; done
```

You will see the `requests` counter increase in the watch terminal.

---

## 6. Exercise: Watch Live Traffic Flow in the Terminal

**Goal:** See every request arrive at NGINX in real time.

### Step 1 — Open the access log live

```bash
# Watch all requests in real time
sudo tail -f /var/log/nginx/access.log
```

### Step 2 — Send requests from another terminal

```bash
curl http://localhost:8080/api/products
curl http://localhost:8080/api/users
curl http://localhost:8080/nonexistent
```

In the log terminal you will see each request appear immediately:
```
127.0.0.1 - - [29/Apr/2026:10:30:01 +0000] "GET /api/products HTTP/1.1" 200 68 "-" "curl/7.81.0"
127.0.0.1 - - [29/Apr/2026:10:30:02 +0000] "GET /api/users HTTP/1.1" 200 55 "-" "curl/7.81.0"
127.0.0.1 - - [29/Apr/2026:10:30:03 +0000] "GET /nonexistent HTTP/1.1" 404 153 "-" "curl/7.81.0"
```

### Step 3 — Filter the log for only errors

```bash
# Show only 4xx and 5xx responses in real time
sudo tail -f /var/log/nginx/access.log | grep -E '" [45][0-9][0-9] '
```

Now when you send a bad request, only errors appear — clean signal/noise separation.

### Step 4 — Kubernetes: watch Ingress logs live

```bash
# Watch Ingress Controller logs — see every request NGINX processes
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f | \
  grep -v "health_check\|favicon"   # filter out noise
```

Send requests in another terminal:
```bash
curl -H "Host: shop.local" http://localhost:8080/api/products
```

You will see in the log:
```
10.244.0.1 - - [29/Apr/2026:10:30:01 +0000] "GET /api/products HTTP/1.1" 200 25 ...
```

---

## 7. Exercise: Simulate Failures and Watch NGINX Respond

**Goal:** Break something on purpose and see exactly what NGINX shows.

### Failure 1 — Kill a backend service

```bash
# Stop the product service
# On-prem: kill the Python server in Terminal 1 with Ctrl+C
# Kubernetes: kubectl scale deployment product-service -n dev --replicas=0

# Now test the route
curl -v http://localhost:8080/api/products
```

You will see:
```
< HTTP/1.1 502 Bad Gateway
<html><head><title>502 Bad Gateway</title></head>
```

Check the error log immediately:
```bash
sudo tail -5 /var/log/nginx/error.log
```
You will see:
```
[error] connect() failed (111: Connection refused) while connecting to upstream, 
upstream: "http://127.0.0.1:3001/"
```

Restart the service and test again:
```bash
# On-prem: restart the Python server
python3 -m http.server 3001 --directory /tmp/products &

curl http://localhost:8080/api/products
# Expected: 200 OK with JSON
```

### Failure 2 — Introduce a config syntax error

```bash
# Add a typo to the config
sudo sed -i 's/proxy_pass/proxey_pass/' /etc/nginx/sites-available/test-routing

# Try to reload
sudo nginx -s reload
```

You will see NGINX refuses to reload:
```
nginx: [error] invalid PID number "" in "/run/nginx.pid"
```

Check the config:
```bash
sudo nginx -t
```
You will see:
```
nginx: [emerg] unknown directive "proxey_pass" in /etc/nginx/sites-available/test-routing:5
nginx: configuration file /etc/nginx/nginx.conf test failed
```

NGINX tells you exactly which file and line. Fix it:
```bash
sudo sed -i 's/proxey_pass/proxy_pass/' /etc/nginx/sites-available/test-routing
sudo nginx -t && sudo nginx -s reload
```

### Failure 3 — Send a request that is too large

```bash
# Generate a 2MB file
dd if=/dev/zero bs=1M count=2 | base64 > /tmp/bigfile.txt

# Send it to NGINX (default max body is 1MB)
curl -X POST -d @/tmp/bigfile.txt http://localhost:8080/api/products
```

You will see:
```
<html><head><title>413 Request Entity Too Large</title></head>
```

Fix by adding to the NGINX config:
```bash
# Add to the server block:
# client_max_body_size 10M;
sudo nginx -t && sudo nginx -s reload

# Try again
curl -X POST -d @/tmp/bigfile.txt http://localhost:8080/api/products
# Now gets through to the backend
```

---

## 8. Exercise: Load Test and Watch NGINX Handle It

**Goal:** Send many requests at once and see how NGINX distributes them.

### Step 1 — Start 3 backend instances (to test load balancing)

```bash
mkdir -p /tmp/backend1 /tmp/backend2 /tmp/backend3
echo '{"server":"backend-1"}' > /tmp/backend1/index.html
echo '{"server":"backend-2"}' > /tmp/backend2/index.html
echo '{"server":"backend-3"}' > /tmp/backend3/index.html

python3 -m http.server 4001 --directory /tmp/backend1 &
python3 -m http.server 4002 --directory /tmp/backend2 &
python3 -m http.server 4003 --directory /tmp/backend3 &
```

### Step 2 — Configure NGINX to load balance across them

```bash
sudo tee /etc/nginx/sites-available/loadbalance-test <<'EOF'
upstream test_backends {
    server 127.0.0.1:4001;
    server 127.0.0.1:4002;
    server 127.0.0.1:4003;
}

server {
    listen 9090;
    server_name localhost;

    location / {
        proxy_pass http://test_backends;
        proxy_set_header Host $host;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/loadbalance-test /etc/nginx/sites-enabled/loadbalance-test
sudo nginx -t && sudo nginx -s reload
```

### Step 3 — Send 30 requests and see them spread across all 3 backends

```bash
# Send 30 requests and capture which server responded
for i in {1..30}; do curl -s http://localhost:9090/; done
```

You will see the responses rotate:
```
{"server":"backend-1"}
{"server":"backend-2"}
{"server":"backend-3"}
{"server":"backend-1"}
{"server":"backend-2"}
...
```

This proves **round-robin load balancing** is working.

### Step 4 — Load test with `hey`

```bash
# Send 200 requests with 10 concurrent connections
hey -n 200 -c 10 http://localhost:9090/
```

You will see a report like:
```
Summary:
  Total:        0.8234 secs
  Slowest:      0.0523 secs
  Fastest:      0.0012 secs
  Average:      0.0041 secs
  Requests/sec: 242.87

Response time histogram:
  0.001 [80]   |████████████████████████
  0.003 [95]   |████████████████████████████
  0.005 [18]   |█████
  0.052 [7]    |██

Status code distribution:
  [200] 200 responses   ← all 200 requests succeeded
```

### Step 5 — Watch the access log during load test

```bash
# Terminal 1 — watch log with request count
sudo tail -f /var/log/nginx/access.log | while read line; do
  echo "$line"
done | pv -l -r > /dev/null
# This shows requests per second in real time
```

```bash
# Terminal 2 — send the load
hey -n 500 -c 20 http://localhost:9090/
```

---

## 9. Visual Dashboards — Grafana + NGINX Metrics

If you have Prometheus and Grafana running, you can see NGINX metrics visually.

### Enable NGINX metrics endpoint in Kubernetes

```bash
# Upgrade the Helm release to enable metrics
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.metrics.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"=true \
  --set controller.podAnnotations."prometheus\.io/port"=10254 \
  --reuse-values

# Verify metrics endpoint
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller-metrics 9913:10254
curl http://localhost:9913/metrics | grep nginx_ingress_controller_requests
```

You will see:
```
nginx_ingress_controller_requests{controller_class="nginx",ingress="ecommerce-ingress",
  namespace="dev",service="product-service",status="200"} 42
```

### Import Grafana Dashboard

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open browser: http://localhost:3000  (admin / prom-operator)
```

In Grafana:
1. Click `+` → `Import`
2. Enter Dashboard ID: `9614`  — this is the official NGINX Ingress Grafana dashboard
3. Click `Load` → `Import`

You will see panels showing:
- Requests per second (live graph)
- HTTP status codes over time (200 vs 4xx vs 5xx)
- Upstream response time
- Active connections

---

## Summary: How to Verify NGINX Works in Each Environment

| Environment | Quickest Visual Test |
|-------------|---------------------|
| **Local / on-prem** | `curl http://localhost:8080/` and `sudo tail -f /var/log/nginx/access.log` |
| **VS Code** | Create `test.http`, press `Send Request`, see response in side panel |
| **Minikube K8s** | `kubectl port-forward` then `curl -H "Host: ..." http://localhost:8080/` |
| **Azure VM** | `curl http://<public-ip>/api/products` from your local machine |
| **AKS** | `curl https://shop.yourdomain.com/api/products` after DNS points to Load Balancer IP |
| **Grafana** | Import dashboard ID `9614`, watch request graph fill in |

---

## What to Do Next

- [06-nginx-debug-troubleshoot.md](06-nginx-debug-troubleshoot.md) — fix any errors you hit during these exercises
- [07-nginx-cheatsheet.md](07-nginx-cheatsheet.md) — quick reference for commands used here
- [NGINX Ingress Complete Reference](../08-service-mesh-networking/nginx-ingress-guide.md) — advanced annotations and production config
