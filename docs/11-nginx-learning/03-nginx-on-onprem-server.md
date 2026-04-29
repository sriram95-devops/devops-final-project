# Guide 03 — NGINX on an On-Premises Server

## Goal of This Guide

By the end you will have NGINX running on a physical server or on-prem VM that:
- Routes traffic to 3 backend services
- Handles HTTPS with a self-signed certificate
- Runs as a systemd service (auto-starts on reboot)
- Has access logs and error logs that you can monitor

**This guide uses Ubuntu 22.04 LTS** — the most common on-prem Linux server OS.

---

## 1. What "On-Prem" Means in This Context

On-premises (on-prem) = a server you physically own or control in your data center or office.

Examples:
- A physical server under your desk or in a server room
- A VMware or Hyper-V virtual machine on hardware you manage
- A VirtualBox VM you created for testing
- A Raspberry Pi running Ubuntu Server

The key difference from cloud: **you manage the hardware, OS, networking, and security yourself.**

---

## 2. Architecture: What We Will Build

```
                    On-Prem Network
                         │
              External IP: 192.168.1.100
                         │
              ┌──────────▼──────────┐
              │   Ubuntu 22.04 VM   │
              │                     │
              │  ┌───────────────┐  │
              │  │  NGINX :80    │  │
              │  │  NGINX :443   │  │
              │  └──────┬────────┘  │
              │         │           │
              │   ┌─────┼─────┐     │
              │   │     │     │     │
              │  :3000 :3001 :3002  │
              │   │     │     │     │
              │  API  Product User  │
              │  GW   Service Svc   │
              └─────────────────────┘
```

---

## 3. Provision the Ubuntu Server

### If you are using VirtualBox (on-prem lab)

```bash
# Download Ubuntu 22.04 ISO from ubuntu.com
# Create a new VM:
#   - RAM: 2GB minimum
#   - Disk: 20GB
#   - Network: Bridged Adapter (so it gets a real IP on your network)
# Install Ubuntu Server (minimal install is fine)
```

### Initial server setup after Ubuntu install

```bash
# Update the OS
sudo apt update && sudo apt upgrade -y

# Install useful tools
sudo apt install curl wget net-tools ufw -y

# Check the server IP
ip addr show
# Look for inet 192.168.x.x under your network interface (eth0 or enp0s3)
```

---

## 4. Install NGINX

```bash
# Install NGINX from Ubuntu's official repo
sudo apt install nginx -y

# Start and enable (auto-start on boot)
sudo systemctl start nginx
sudo systemctl enable nginx

# Check status
sudo systemctl status nginx
# Expected:
# ● nginx.service - A high performance web server and a reverse proxy server
#      Loaded: loaded (/lib/systemd/system/nginx.service; enabled)
#      Active: active (running)

# Verify NGINX is listening
sudo ss -tlnp | grep nginx
# Expected:
# LISTEN  0  511  0.0.0.0:80   0.0.0.0:*  users:(("nginx",...))
```

### Open firewall ports

```bash
# Allow HTTP and HTTPS through the firewall
sudo ufw allow 'Nginx Full'    # ← opens port 80 and 443
sudo ufw allow OpenSSH         # ← keep SSH open so you don't lock yourself out
sudo ufw enable

# Verify
sudo ufw status
# Expected:
# Nginx Full     ALLOW
# OpenSSH        ALLOW
```

---

## 5. Deploy Three Backend Services

In a real setup you would have real apps. For this guide, we create 3 simple HTTP servers to simulate them.

```bash
# Install Python (usually already installed)
sudo apt install python3 -y

# Create 3 simple web roots
sudo mkdir -p /srv/api-gateway /srv/product-service /srv/user-service

echo '{"service": "api-gateway", "status": "ok"}' | sudo tee /srv/api-gateway/index.html
echo '{"service": "product-service", "status": "ok"}' | sudo tee /srv/product-service/index.html
echo '{"service": "user-service", "status": "ok"}' | sudo tee /srv/user-service/index.html

# Create systemd services for each fake app
# (In production these would be your real app units)
```

Create `/etc/systemd/system/api-gateway.service`:

```bash
sudo tee /etc/systemd/system/api-gateway.service <<EOF
[Unit]
Description=API Gateway (fake for testing)
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 3000 --directory /srv/api-gateway
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
EOF
```

```bash
# Do the same for product-service and user-service
sudo tee /etc/systemd/system/product-service.service <<EOF
[Unit]
Description=Product Service (fake for testing)
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 3001 --directory /srv/product-service
Restart=always
User=www-data
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/user-service.service <<EOF
[Unit]
Description=User Service (fake for testing)
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 3002 --directory /srv/user-service
Restart=always
User=www-data
[Install]
WantedBy=multi-user.target
EOF

# Start and enable all three
sudo systemctl daemon-reload
sudo systemctl enable --now api-gateway product-service user-service

# Verify they are running
sudo systemctl status api-gateway product-service user-service
curl http://localhost:3000   # Expected: {"service": "api-gateway", ...}
curl http://localhost:3001   # Expected: {"service": "product-service", ...}
curl http://localhost:3002   # Expected: {"service": "user-service", ...}
```

---

## 6. Configure NGINX as Reverse Proxy

### Create the NGINX site config

```bash
sudo nano /etc/nginx/sites-available/myapp
```

```nginx
# Define upstream groups for load balancing (even with 1 server, use upstream for future scaling)
upstream api_gateway {
    server 127.0.0.1:3000;              # ← NGINX: api-gateway backend
    # Add more lines here to scale: server 127.0.0.1:3003;
}

upstream product_backend {
    server 127.0.0.1:3001;              # ← NGINX: product-service backend
}

upstream user_backend {
    server 127.0.0.1:3002;              # ← NGINX: user-service backend
}

server {
    listen 80;                           # ← NGINX: accept HTTP on port 80
    server_name _;                       # ← NGINX: _ means "accept any hostname" (on-prem no domain)

    # Logging — write to separate file for this app
    access_log /var/log/nginx/myapp_access.log;   # ← NGINX: access log per app
    error_log  /var/log/nginx/myapp_error.log;    # ← NGINX: error log per app

    # Route 1: /api/products → product service
    location /api/products {
        proxy_pass http://product_backend;
        proxy_set_header Host $host;                           # ← NGINX: forward hostname
        proxy_set_header X-Real-IP $remote_addr;              # ← NGINX: forward real client IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 10s;                             # ← NGINX: timeout connecting to backend
        proxy_read_timeout 30s;                                # ← NGINX: timeout waiting for backend response
    }

    # Route 2: /api/users → user service
    location /api/users {
        proxy_pass http://user_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Route 3: everything else → api-gateway
    location / {
        proxy_pass http://api_gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Connection "";                        # ← NGINX: keep-alive support
    }
}
```

### Enable the site and test

```bash
# Enable (create symlink)
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp

# Disable default NGINX page
sudo rm -f /etc/nginx/sites-enabled/default

# Test config syntax — ALWAYS do this before reload
sudo nginx -t
# Expected:
# nginx: configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# Reload (no downtime)
sudo nginx -s reload

# Test routing from the server itself
curl http://localhost/api/products   # → product-service
curl http://localhost/api/users      # → user-service
curl http://localhost/               # → api-gateway
```

---

## 7. Add HTTPS with a Self-Signed Certificate

In on-prem without a public domain, you use a self-signed certificate. For a real domain, see the Let's Encrypt section below.

```bash
# Generate self-signed certificate (valid for 365 days)
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/myapp.key \
    -out /etc/nginx/ssl/myapp.crt \
    -subj "/CN=myapp.local/O=MyOrg/C=US"
# Expected: Generates myapp.key and myapp.crt
```

Update the NGINX config to add HTTPS:

```bash
sudo nano /etc/nginx/sites-available/myapp
```

```nginx
upstream api_gateway    { server 127.0.0.1:3000; }
upstream product_backend { server 127.0.0.1:3001; }
upstream user_backend   { server 127.0.0.1:3002; }

# HTTP → redirect to HTTPS
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;              # ← NGINX: force HTTPS, redirect all HTTP
}

# HTTPS server
server {
    listen 443 ssl;                                    # ← NGINX: listen on HTTPS port
    server_name _;

    ssl_certificate     /etc/nginx/ssl/myapp.crt;      # ← NGINX: path to certificate
    ssl_certificate_key /etc/nginx/ssl/myapp.key;      # ← NGINX: path to private key
    ssl_protocols       TLSv1.2 TLSv1.3;               # ← NGINX: only allow secure TLS versions
    ssl_ciphers         HIGH:!aNULL:!MD5;               # ← NGINX: disable weak ciphers

    access_log /var/log/nginx/myapp_access.log;
    error_log  /var/log/nginx/myapp_error.log;

    location /api/products {
        proxy_pass http://product_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;      # ← NGINX: tell backend the original protocol was HTTPS
    }

    location /api/users {
        proxy_pass http://user_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }

    location / {
        proxy_pass http://api_gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

```bash
sudo nginx -t && sudo nginx -s reload

# Test HTTPS (skip cert validation for self-signed)
curl -k https://localhost/api/products
# Expected: {"service": "product-service", "status": "ok"}
```

### Mandatory Lines Table — HTTPS server block

| Line | Why It Is Mandatory |
|------|---------------------|
| `listen 443 ssl` | Without `ssl`, NGINX listens on 443 but does not handle SSL handshake |
| `ssl_certificate` | Path to the certificate file — NGINX will refuse to start if missing |
| `ssl_certificate_key` | Path to the private key — must match the certificate |
| `ssl_protocols TLSv1.2 TLSv1.3` | Without this, NGINX may allow old insecure TLS 1.0 and 1.1 |
| `ssl_ciphers HIGH:!aNULL:!MD5` | Without this, weak ciphers could be used, enabling decryption attacks |
| `X-Forwarded-Proto https` | Without this, backend thinks request came via HTTP and may redirect users to HTTP |

---

## 8. Let's Encrypt (Free HTTPS for a Real Domain)

If your on-prem server has a real public domain name pointing to it:

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Get a certificate automatically
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com   # <-- REPLACE with your domain

# Certbot edits nginx.conf automatically and adds:
# ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem
# ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem

# Test auto-renewal
sudo certbot renew --dry-run
# Expected: Congratulations, all renewals succeeded
```

---

## 9. NGINX Management Commands on a Server

```bash
# Check NGINX is running
sudo systemctl status nginx

# Start NGINX
sudo systemctl start nginx

# Stop NGINX
sudo systemctl stop nginx

# Restart NGINX (brief downtime — use reload instead)
sudo systemctl restart nginx

# Reload config without downtime (ALWAYS use this in production)
sudo nginx -s reload

# Test config file before applying
sudo nginx -t

# See which version is installed
nginx -v

# See what modules are compiled in
nginx -V 2>&1 | grep --color 'configure arguments'

# List all active NGINX processes
ps aux | grep nginx

# Check what ports NGINX is listening on
sudo ss -tlnp | grep nginx

# Watch access log in real time
sudo tail -f /var/log/nginx/access.log

# Watch error log in real time
sudo tail -f /var/log/nginx/error.log
```

---

## 10. Scenario — One of My Services Goes Down

**Goal:** Understand what happens in NGINX when a backend crashes.

**Trigger — Kill the product service:**
```bash
sudo systemctl stop product-service
```

**Observe — Test the route:**
```bash
curl http://localhost/api/products
# Expected error:
# <html><head><title>502 Bad Gateway</title></head>...
```

**Check the error log:**
```bash
sudo tail /var/log/nginx/myapp_error.log
# You will see:
# [error] connect() failed (111: Connection refused) while connecting to upstream
# upstream: "http://127.0.0.1:3001"
```

**Fix — Restart the service:**
```bash
sudo systemctl start product-service
curl http://localhost/api/products
# Should return the JSON response again
```

**Fix — Add a fallback page for when backend is down:**

```nginx
location /api/products {
    proxy_pass http://product_backend;
    proxy_set_header Host $host;
    # Return a custom 502 page instead of the default NGINX error
    error_page 502 /502.json;
}

location = /502.json {
    internal;
    return 502 '{"error": "product service is temporarily unavailable"}';
    add_header Content-Type application/json;
}
```

---

## What to Do Next

Read [04-nginx-in-kubernetes-pods.md](04-nginx-in-kubernetes-pods.md) to run NGINX Ingress inside a Kubernetes cluster and route traffic to pods.
