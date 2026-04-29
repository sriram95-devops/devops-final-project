# Guide 02 — NGINX on Local Machine and VS Code

## Goal of This Guide

By the end of this guide you will:
- Have NGINX running on your Windows machine
- Serve a local project with NGINX
- Test with VS Code and browser
- Route two local apps through one NGINX instance

---

## 1. Install NGINX on Windows

### Option A — Using Chocolatey (recommended)

```bash
# Install Chocolatey first if you don't have it (run in PowerShell as Admin)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install NGINX
choco install nginx -y

# Verify install
nginx -v
# Expected: nginx/1.x.x
```

### Option B — Manual Download

```bash
# 1. Download from https://nginx.org/en/download.html
#    Choose: nginx/Windows-1.x.x (Stable version)
# 2. Extract to C:\nginx
# 3. Add C:\nginx to your PATH in System Environment Variables
# 4. Open a new terminal and verify:
nginx -v
```

### Option C — Using WSL (Windows Subsystem for Linux) — Best for DevOps

```bash
# Inside WSL terminal (Ubuntu)
sudo apt update && sudo apt install nginx -y

# Start NGINX
sudo systemctl start nginx
sudo systemctl enable nginx   # start on boot

# Verify it is running
sudo systemctl status nginx
# Expected: Active: active (running)

# Test from Windows browser: http://localhost
# You will see the NGINX welcome page
```

---

## 2. NGINX File Locations

| Environment | Config file | Sites folder | Logs |
|-------------|-------------|--------------|------|
| **Windows** | `C:\nginx\conf\nginx.conf` | `C:\nginx\conf\` | `C:\nginx\logs\` |
| **WSL / Ubuntu** | `/etc/nginx/nginx.conf` | `/etc/nginx/sites-available/` | `/var/log/nginx/` |
| **Docker** | `/etc/nginx/nginx.conf` (inside container) | — | stdout/stderr |

---

## 3. VS Code Setup for NGINX

### Install the NGINX extension

```
1. Open VS Code
2. Press Ctrl+Shift+X (Extensions panel)
3. Search: "NGINX Configuration"
4. Install: "NGINX Configuration" by shanoor
   — Gives syntax highlighting + autocomplete for nginx.conf
```

### Open the NGINX config in VS Code

```bash
# WSL / Ubuntu
code /etc/nginx/nginx.conf

# Windows
code C:\nginx\conf\nginx.conf
```

You will see syntax highlighting like this:

```nginx
server {                    # ← highlighted as block keyword
    listen 80;              # ← directive highlighted
    server_name localhost;  # ← value highlighted
}
```

### VS Code Tasks — Run NGINX commands from VS Code

Create `.vscode/tasks.json` in your project folder:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "NGINX: Test Config",
            "type": "shell",
            "command": "sudo nginx -t",
            "problemMatcher": []
        },
        {
            "label": "NGINX: Reload Config",
            "type": "shell",
            "command": "sudo nginx -s reload",
            "problemMatcher": []
        },
        {
            "label": "NGINX: Start",
            "type": "shell",
            "command": "sudo systemctl start nginx",
            "problemMatcher": []
        },
        {
            "label": "NGINX: Stop",
            "type": "shell",
            "command": "sudo systemctl stop nginx",
            "problemMatcher": []
        },
        {
            "label": "NGINX: View Error Log",
            "type": "shell",
            "command": "sudo tail -50 /var/log/nginx/error.log",
            "problemMatcher": []
        }
    ]
}
```

Run tasks: Press `Ctrl+Shift+P` → `Tasks: Run Task` → select from the list.

---

## 4. Serve a Local Static Site

### Step 1 — Create a simple project

```bash
mkdir ~/myapp && cd ~/myapp
echo "<h1>Hello from NGINX!</h1>" > index.html
```

### Step 2 — Create an NGINX site config

```bash
sudo nano /etc/nginx/sites-available/myapp
```

Paste this config:

```nginx
server {
    listen 8080;                          # ← NGINX: port to listen on (not 80 to avoid conflict)
    server_name localhost;                # ← NGINX: only accept requests for localhost

    root /home/yourname/myapp;            # ← NGINX: folder to serve files from  # <-- REPLACE with your actual path
    index index.html;                     # ← NGINX: default file to serve

    location / {
        try_files $uri $uri/ =404;        # ← NGINX: try the exact file, then directory, else 404
    }
}
```

### Step 3 — Enable the site

```bash
# Create symlink to enable the site
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp

# Test the config (always do this before reloading)
sudo nginx -t
# Expected:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# Reload NGINX to apply changes
sudo nginx -s reload

# Test in browser or with curl
curl http://localhost:8080
# Expected: <h1>Hello from NGINX!</h1>
```

---

## 5. Route Two Local Apps Through NGINX

This is the core skill — one NGINX, two different backend apps.

### Scenario

You have two Node.js apps running locally:
- App 1: product service on port 3001
- App 2: user service on port 3002

You want to access both at `http://localhost:8080`:
- `http://localhost:8080/products` → app on port 3001
- `http://localhost:8080/users` → app on port 3002

### Step 1 — Start two fake backend apps (for testing)

```bash
# Terminal 1 — fake product service
python3 -m http.server 3001

# Terminal 2 — fake user service  
python3 -m http.server 3002
```

### Step 2 — Write the NGINX config

```bash
sudo nano /etc/nginx/sites-available/multi-app
```

```nginx
server {
    listen 8080;                         # ← NGINX: single entry point for all apps
    server_name localhost;

    # Route 1: /products → product service on 3001
    location /products {
        proxy_pass http://127.0.0.1:3001;           # ← NGINX: forward to product service
        proxy_set_header Host $host;                 # ← NGINX: pass real hostname
        proxy_set_header X-Real-IP $remote_addr;     # ← NGINX: pass real client IP
        proxy_http_version 1.1;                      # ← NGINX: use HTTP/1.1 (required for keep-alive)
        proxy_set_header Connection "";              # ← NGINX: enable keep-alive connections
    }

    # Route 2: /users → user service on 3002
    location /users {
        proxy_pass http://127.0.0.1:3002;           # ← NGINX: forward to user service
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Route 3: / → catch-all (optional)
    location / {
        return 200 "NGINX is running. Use /products or /users";  # ← NGINX: custom response for root
        add_header Content-Type text/plain;
    }
}
```

### Step 3 — Enable and test

```bash
sudo ln -s /etc/nginx/sites-available/multi-app /etc/nginx/sites-enabled/multi-app

# First remove the default site to free port 80 (or use 8080)
sudo rm /etc/nginx/sites-enabled/default

sudo nginx -t && sudo nginx -s reload

# Test routing
curl http://localhost:8080/products
curl http://localhost:8080/users
curl http://localhost:8080/
```

### Mandatory Lines Table — multi-app config

| Line | Why It Is Mandatory |
|------|---------------------|
| `proxy_pass http://127.0.0.1:3001` | Core instruction — without this, the request goes nowhere |
| `proxy_set_header Host $host` | Without this, backends see "127.0.0.1" as the hostname, not "localhost" |
| `proxy_set_header X-Real-IP $remote_addr` | Without this, all requests appear to come from 127.0.0.1 in your backend logs |
| `proxy_http_version 1.1` | HTTP 1.0 does not support keep-alive; 1.1 is required for efficient connections |
| `proxy_set_header Connection ""` | Clears the "Connection: close" header so connections can be reused |

---

## 6. Test Everything in VS Code

### Use VS Code's built-in terminal

```bash
# Test 1 — Is NGINX running?
sudo systemctl status nginx

# Test 2 — What ports is NGINX listening on?
sudo ss -tlnp | grep nginx

# Test 3 — Test the config file without restarting
sudo nginx -t

# Test 4 — Check access logs in real time
sudo tail -f /var/log/nginx/access.log

# Test 5 — Check error logs in real time  
sudo tail -f /var/log/nginx/error.log
```

### Use VS Code REST Client Extension for HTTP testing

Install the **REST Client** extension (by Huachao Mao) in VS Code.

Create `test.http` in your project:

```http
### Test root
GET http://localhost:8080

### Test products route
GET http://localhost:8080/products

### Test users route
GET http://localhost:8080/users
```

Press `Send Request` above each line to test without opening a browser.

---

## 7. Common Local Setup Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `bind() to 0.0.0.0:80 failed (13: Permission denied)` | Port 80 needs root on Linux | Use port 8080 or run with `sudo` |
| `nginx: [emerg] unknown directive` | Typo in nginx.conf | Run `sudo nginx -t` to find the line |
| `connect() failed (111: Connection refused)` | Backend app is not running | Start your Node/Python app first |
| `nginx: [emerg] open() "/etc/nginx/sites-enabled/..." failed` | Missing symlink | Run `sudo ln -s sites-available/x sites-enabled/x` |
| NGINX welcome page still shows after config change | Old config still active | `sudo nginx -s reload` (not restart) |

---

## What to Do Next

Read [03-nginx-on-onprem-server.md](03-nginx-on-onprem-server.md) to deploy NGINX on a real Ubuntu server with SSL and multiple services.
