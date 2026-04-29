# Guide 01 — What is NGINX and How It Works

## 1. Plain English Explanation

Imagine you run a hotel. Guests (web requests) arrive at the front door and ask for different things:
- "I want to go to the restaurant" → send them to Floor 1
- "I want the gym" → send them to Floor 3
- "I want room 404" → that room does not exist, send a 404 error

**NGINX is the hotel receptionist.** It receives every request that arrives and decides where to send it.

Without NGINX, every app needs its own door (public IP / port). With NGINX, one door handles everything.

---

## 2. What NGINX Actually Is

NGINX (pronounced "engine-x") is three things in one:

| Role | What It Does | Example |
|------|-------------|---------|
| **Web server** | Serves static files (HTML, CSS, images) directly | Serve a React build folder |
| **Reverse proxy** | Forwards requests to a backend app | Forward `/api` to Node.js on port 3000 |
| **Load balancer** | Splits traffic across multiple copies of an app | Round-robin across 3 API pods |

In DevOps and Kubernetes, we mostly use it as a **reverse proxy and load balancer**.

---

## 3. Key Terms Dictionary

Learn these terms before reading anything else. You will see them everywhere.

| Term | Plain English Meaning |
|------|-----------------------|
| **Upstream** | The backend server(s) that NGINX forwards requests to. "Upstream" = behind NGINX. |
| **Downstream** | The client (browser, mobile app, curl) that sent the request to NGINX. |
| **Reverse proxy** | NGINX receives a request and sends it to another server. The client only talks to NGINX, never directly to the backend. |
| **Proxy pass** | The instruction in NGINX config that says "send this request to THIS address". |
| **Server block** | One block of config that handles one domain (e.g., `api.myapp.com`). Like a virtual host. |
| **Location block** | Inside a server block, routes a specific path (e.g., `/api/products` → product service). |
| **Ingress** | In Kubernetes: an object that tells NGINX Ingress Controller how to route traffic into the cluster. |
| **Ingress Controller** | The NGINX pod running inside Kubernetes that reads Ingress objects and configures itself. |
| **SSL termination** | NGINX handles HTTPS encryption. The backend app receives plain HTTP. |
| **Load balancing** | NGINX splits requests across multiple backend servers to share the load. |
| **Rate limiting** | NGINX blocks or slows clients that send too many requests per second. |
| **502 Bad Gateway** | NGINX could reach the backend but the backend sent an invalid response (or is not running). |
| **504 Gateway Timeout** | NGINX forwarded the request but the backend took too long to respond. |

---

## 4. How a Request Flows Through NGINX

### Scenario: Browser hits `https://shop.myapp.com/api/products`

```
Browser
  │
  │  HTTPS request: GET /api/products
  ▼
NGINX (port 443)
  │  1. Terminate SSL (decrypt HTTPS → HTTP)
  │  2. Match server block for shop.myapp.com
  │  3. Match location block for /api/products
  │  4. proxy_pass → product-service:3001
  ▼
product-service (port 3001)
  │  Process request, query database
  ▼
NGINX
  │  Receive response from product-service
  │  Re-encrypt (HTTP → HTTPS)
  ▼
Browser
  Gets the JSON product list
```

### ASCII Architecture Diagram — Multiple Containers Behind NGINX

```
                    Internet
                       │
                   HTTPS :443
                       │
             ┌─────────▼──────────┐
             │       NGINX        │
             │  (reverse proxy /  │
             │   load balancer)   │
             └──┬────────┬────────┘
                │        │        │
         /api/  │  /user/ │  /     │
         products│  service│  (root)│
                │        │        │
       ┌────────▼┐ ┌─────▼──┐ ┌──▼──────────┐
       │ product- │ │  user- │ │ api-gateway │
       │ service  │ │service │ │             │
       │ :3001    │ │ :3002  │ │    :3000    │
       └────────┬─┘ └──────┬─┘ └──────┬─────┘
                │           │          │
                └───────────▼──────────┘
                         Database
```

---

## 5. NGINX vs Other Tools

| Tool | Best For | When NOT to use it |
|------|----------|--------------------|
| **NGINX** | High-performance reverse proxy, static files, K8s ingress | You need deep protocol support (gRPC first class) |
| **Apache** | Legacy apps, `.htaccess` support | High concurrent load (NGINX handles it better) |
| **Traefik** | Auto-discovery in Docker/K8s | When you need very granular annotation control |
| **HAProxy** | TCP load balancing, extreme performance | When you need to serve static files |
| **Istio** | East-west traffic between pods (service mesh) | North-south (external) traffic — use NGINX for that |

**Rule of thumb:**
- External traffic (browser → cluster) → **NGINX Ingress**
- Internal traffic (pod A → pod B) → **Istio** or **Kubernetes Service**

---

## 6. NGINX Config File Structure

Understanding the config file structure is essential. Here is a minimal working config:

```nginx
# /etc/nginx/nginx.conf

events {
    worker_connections 1024;   # ← NGINX: max simultaneous connections per worker
}

http {

    # Define the backend servers (upstream group)
    upstream product_backend {
        server product-service:3001;   # ← NGINX: backend server 1
        server product-service:3002;   # ← NGINX: backend server 2 (load balance between both)
    }

    server {
        listen 80;                          # ← NGINX: listen on port 80 (HTTP)
        server_name shop.myapp.com;         # ← NGINX: only handle requests for this domain

        location /api/products {
            proxy_pass http://product_backend;              # ← NGINX: forward to upstream group
            proxy_set_header Host $host;                    # ← NGINX: pass original hostname to backend
            proxy_set_header X-Real-IP $remote_addr;       # ← NGINX: pass real client IP to backend
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  # ← NGINX: full IP chain
        }

        location /api/users {
            proxy_pass http://user-service:3002;   # ← NGINX: different path → different service
        }

        location / {
            proxy_pass http://api-gateway:3000;    # ← NGINX: catch-all → api-gateway
        }
    }
}
```

### Mandatory Lines Table — nginx.conf

| Line | Why It Is Mandatory |
|------|---------------------|
| `listen 80` | Without this, NGINX does not know which port to accept requests on |
| `server_name` | Routes requests to the right server block when multiple domains share one IP |
| `proxy_pass` | This is the core instruction — without it NGINX does not forward anything |
| `proxy_set_header Host $host` | Backend app needs the original hostname, not NGINX's internal hostname |
| `proxy_set_header X-Real-IP $remote_addr` | Your app logs would show NGINX's IP instead of the real client IP |
| `proxy_set_header X-Forwarded-For` | Required for proper IP logging, rate limiting, and security rules |

---

## 7. The Three NGINX Deployment Patterns

### Pattern 1 — On a Server (bare metal / VM)

```
Internet → Port 443 → NGINX (running as systemd service) → App on localhost:3000
```

NGINX is installed directly on the OS. Config lives in `/etc/nginx/`.

### Pattern 2 — In a Docker Container

```
Internet → Port 443 → NGINX container → App container (same Docker network)
```

NGINX runs as a container. Config is mounted or baked into the image.

### Pattern 3 — In Kubernetes (NGINX Ingress Controller)

```
Internet → Load Balancer IP → NGINX Ingress Controller Pod → ClusterIP Service → App Pod
```

NGINX runs as a Kubernetes Deployment. You configure it using `Ingress` objects, not `nginx.conf` directly.

---

## 8. What You Will Build in the Next Guides

| Guide | You Will Build |
|-------|---------------|
| Guide 02 | NGINX on your local machine + test in VS Code |
| Guide 03 | NGINX on Ubuntu on-prem server routing 3 services |
| Guide 04 | NGINX Ingress in Minikube routing api-gateway, product-service, user-service |
| Guide 05 | NGINX on Azure VM + AKS with Azure Load Balancer |
| Guide 06 | Diagnose 502, 504, 404, connection refused in every environment |

---

## What to Do Next

Read [02-nginx-on-local-and-vscode.md](02-nginx-on-local-and-vscode.md) to install NGINX on your Windows machine and test it in VS Code.
