# Podman Complete Guide

## Table of Contents
1. [Overview & Why Podman](#overview--why-podman)
2. [Local Setup](#local-setup)
3. [Online/Cloud Setup](#onlinecloud-setup)
4. [Configuration Deep Dive](#configuration-deep-dive)
5. [Integration with Existing Tools](#integration-with-existing-tools)
6. [Real-World Scenarios](#real-world-scenarios)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Cheat Sheet](#cheat-sheet)

---

## Overview & Why Podman

### What is Podman?

Podman (Pod Manager) is a daemonless, rootless container engine developed by Red Hat. It is a drop-in replacement for Docker in most scenarios, providing the same command-line interface (`podman` replaces `docker`) while addressing several architectural concerns.

### Rootless Containers

The biggest differentiator between Podman and Docker is that Podman runs containers **without requiring root privileges**:

| Aspect | Docker | Podman |
|--------|--------|--------|
| Daemon | Requires `dockerd` (runs as root) | No daemon — forks containers directly |
| Root required | Yes (for daemon) | No — users run containers as themselves |
| Privilege escalation risk | Higher (Docker socket = root shell) | Lower — no privileged daemon |
| Systemd integration | Via docker.socket | Native — can run as user services |
| Pods | No (use docker-compose) | Yes — native pod support |
| Docker compatibility | N/A | High — same CLI, same image format |
| OCI compliance | Yes | Yes |
| Image format | OCI + Docker v2 | OCI + Docker v2 |
| Compose | docker compose | podman-compose |

**Why rootless matters in enterprise security:**
- In Docker, the Docker socket (`/var/run/docker.sock`) is effectively a root shell. Anyone who can write to the socket can escape the container and compromise the host.
- With Podman, each user runs containers under their own UID, using user namespaces to map UIDs inside containers.
- This aligns with the **principle of least privilege** — a compromised container process cannot escalate to root on the host.

### Daemonless Architecture

Docker uses a long-running daemon (`dockerd`) that all container operations go through:

```
Docker:   docker CLI → dockerd (root) → containerd → runc → container
Podman:   podman CLI ────────────────────────────── → runc → container
```

Podman forks container processes directly from the calling process. This has several implications:

- **No single point of failure**: A Docker daemon crash kills all containers. With Podman, each container process is independent.
- **Systemd-friendly**: Containers can be managed directly by systemd as user or system services.
- **Fork/exec model**: Containers appear as normal user processes in `ps aux`.

### OCI Compliance

Both Docker and Podman produce and consume **OCI (Open Container Initiative)** compliant images and containers. This means:

- Images built with `podman build` (using Buildah under the hood) can be pushed to any OCI-compliant registry (JFrog, ACR, Docker Hub, Quay.io)
- Images pulled by Podman can be run by Docker and vice versa
- Kubernetes (`containerd`, `CRI-O`) can run images built by either tool

### Comparison Summary

```
Use Docker when:
  ✓ Team is already using Docker, minimal migration effort needed
  ✓ Docker Desktop on macOS/Windows is convenient for developers
  ✓ Jenkins Docker plugin is used

Use Podman when:
  ✓ Security policy prohibits root-owned daemons on build hosts
  ✓ Running on RHEL/Fedora/CentOS where Podman is default
  ✓ Need rootless container support in CI/CD
  ✓ Want native pod semantics similar to Kubernetes
  ✓ Want containers managed by systemd
```

---

## Local Setup

### Install Podman on Ubuntu/Debian

```bash
# Ubuntu 22.04+
sudo apt update
sudo apt install -y podman

# Verify installation
podman version
podman info

# Test with hello-world
podman run hello-world
```

For Ubuntu 20.04, add the Kubic repository for a newer version:

```bash
. /etc/os-release
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | \
  sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list

curl -L "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | \
  sudo apt-key add -

sudo apt update && sudo apt install -y podman
```

### Install Podman on macOS

```bash
# Using Homebrew — Podman on macOS uses a Linux VM (like Docker Desktop)
brew install podman

# Initialize the Podman machine (Linux VM)
podman machine init

# Start the machine
podman machine start

# Verify
podman version
podman machine list
```

### Install Podman on RHEL/Fedora/CentOS

```bash
# Podman is the default on RHEL 8+ — may already be installed
sudo dnf install -y podman podman-compose

# Verify
podman version
```

### Configure Rootless Podman

Rootless containers require user namespaces and `/etc/subuid` and `/etc/subgid` entries:

```bash
# Check if your user has subuid/subgid configured
cat /etc/subuid | grep $USER
cat /etc/subgid | grep $USER

# If not present, add them:
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# Reload namespaces
podman system migrate

# Test rootless container
podman run --rm alpine id
# Expected: uid=0(root) gid=0(root) — inside container root maps to YOUR UID on host
```

### Install podman-compose

```bash
# Install via pip
pip3 install podman-compose

# Or via package manager on Fedora/RHEL
sudo dnf install podman-compose

# Verify
podman-compose version
```

### Podman Desktop

Podman Desktop provides a Docker Desktop-like GUI:

1. Download from [https://podman-desktop.io/](https://podman-desktop.io/)
2. Available for macOS, Windows, and Linux
3. Features: Container management, image browser, volume/network management, Kubernetes integration, Extensions

```bash
# On macOS via Homebrew
brew install --cask podman-desktop

# On Linux (Flatpak)
flatpak install flathub io.podman_desktop.PodmanDesktop
```

### Docker Compatibility (Alias)

To use `docker` commands transparently with Podman:

```bash
# Create alias (add to ~/.bashrc or ~/.zshrc)
alias docker=podman
alias docker-compose=podman-compose

# Or install the docker-compatibility package (RHEL/Fedora)
sudo dnf install podman-docker
# This creates a docker → podman symlink and docker.socket → podman.socket alias
```

---

## Online/Cloud Setup

### Killercoda Podman Playground

[Killercoda](https://killercoda.com/) provides free browser-based environments with Podman installed:

1. Go to [https://killercoda.com/](https://killercoda.com/)
2. Search for "Podman" scenarios
3. Use a full Linux environment with Podman pre-installed

### Azure Red Hat OpenShift (ARO)

OpenShift uses CRI-O (which shares the same container runtime as Podman) as its container runtime:

```bash
# Connect to OpenShift cluster
oc login --token=your-token --server=https://your-cluster.openshift.com

# OpenShift uses Podman/Buildah tooling under the hood
# Build images using BuildConfig (server-side builds using Buildah)
oc new-build --binary --name=myapp -l app=myapp
oc start-build myapp --from-dir=. --follow
```

### Using Podman in GitHub Actions

```yaml
# .github/workflows/build.yml
name: Build with Podman

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Podman
        run: |
          sudo apt update
          sudo apt install -y podman

      - name: Build image
        run: podman build -t myapp:${{ github.sha }} .

      - name: Push to registry
        run: |
          podman login -u ${{ secrets.JFROG_USER }} \
                       -p ${{ secrets.JFROG_PASS }} \
                       your-org.jfrog.io
          podman push myapp:${{ github.sha }} \
            your-org.jfrog.io/docker-local/myapp:${{ github.sha }}
```

---

## Configuration Deep Dive

### Rootless Containers Setup

Understanding UID mapping in rootless containers:

```bash
# Run a container — inside the container you appear as root
podman run --rm -it alpine sh
# id → uid=0(root) gid=0(root) — appears as root INSIDE container

# On the HOST, this process runs as your actual user
# Open another terminal and check:
ps aux | grep alpine
# Shows: youruser  12345  ...  alpine sh  ← Runs as your UID, not root!

# Force a specific user inside the container
podman run --rm --user 1000:1000 alpine id
# uid=1000 gid=1000

# Run with specific host-to-container UID mapping
podman run --rm --userns=keep-id alpine id
# Maps YOUR host UID to the same UID inside the container
```

**Storage location for rootless containers:**

```bash
# Rootless containers and images are stored per-user
~/.local/share/containers/storage/

# Configuration
~/.config/containers/

# Override storage location
export CONTAINERS_STORAGE_CONF=~/.config/containers/storage.conf
```

**Rootless container configuration file:**

```ini
# ~/.config/containers/containers.conf

[containers]
# Default capabilities for rootless containers
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "FSETID",
    "KILL",
    "NET_BIND_SERVICE",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
    "SYS_CHROOT"
]

# Default environment variables
default_env = [
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
]

[network]
# Default network for new containers
default_network = "podman"
```

### Podman Pods

Podman supports **pods** — a group of containers sharing a network namespace, similar to Kubernetes pods. This is a unique feature not available in Docker.

```bash
# Create a pod (creates an infra/pause container that holds the network namespace)
podman pod create --name myapp-pod -p 8080:8080

# Add containers to the pod
podman run -d \
  --pod myapp-pod \
  --name app \
  myapp:latest

podman run -d \
  --pod myapp-pod \
  --name sidecar \
  nginx:alpine

# List pods
podman pod ls

# List all containers including pod members
podman ps -a --pod

# View pod details
podman pod inspect myapp-pod

# Stop and remove the entire pod (and all its containers)
podman pod stop myapp-pod
podman pod rm myapp-pod
```

**Containers within a pod share localhost:**

```bash
# app container can reach sidecar on localhost:80
# sidecar container can reach app on localhost:8080
# This mirrors Kubernetes pod behaviour exactly
podman exec app curl http://localhost:80  # Reaches nginx sidecar
```

### Generating Kubernetes YAML from Podman Pods

One of Podman's most powerful features is generating Kubernetes manifests from running pods:

```bash
# Create a pod that mirrors what you want in Kubernetes
podman pod create --name webapp -p 8080:8080 -p 5432:5432

podman run -d \
  --pod webapp \
  --name webapp-app \
  -e DB_HOST=localhost \
  -e DB_PORT=5432 \
  myapp:latest

podman run -d \
  --pod webapp \
  --name webapp-db \
  -e POSTGRES_PASSWORD=secret \
  -v webapp-pgdata:/var/lib/postgresql/data \
  postgres:15-alpine

# Generate Kubernetes YAML from the running pod
podman generate kube webapp > webapp-pod.yaml

# The generated YAML is valid Kubernetes PodSpec YAML
cat webapp-pod.yaml
```

**Example of generated Kubernetes YAML:**

```yaml
# Generated by podman generate kube
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: webapp
  name: webapp
spec:
  containers:
  - name: webapp-app
    image: myapp:latest
    env:
    - name: DB_HOST
      value: localhost
    - name: DB_PORT
      value: "5432"
    ports:
    - containerPort: 8080
      hostPort: 8080
      protocol: TCP
  - name: webapp-db
    image: postgres:15-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: secret
    volumeMounts:
    - mountPath: /var/lib/postgresql/data
      name: webapp-pgdata
  volumes:
  - name: webapp-pgdata
    persistentVolumeClaim:
      claimName: webapp-pgdata
```

```bash
# Play back the YAML with Podman (re-creates the pod)
podman play kube webapp-pod.yaml

# Deploy to Kubernetes
kubectl apply -f webapp-pod.yaml
```

### podman-compose for Local Development

`podman-compose` is compatible with Docker Compose files:

```yaml
# docker-compose.yml (same format, works with both docker compose and podman-compose)
version: "3.9"

services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DB_URL=postgresql://postgres:5432/mydb
    depends_on:
      - postgres

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_PASSWORD: localpass
      POSTGRES_DB: mydb
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

```bash
# Run with podman-compose
podman-compose up -d

# Or use podman's built-in compose support (Podman 4.7+)
podman compose up -d

# View running services
podman-compose ps

# Stop services
podman-compose down
```

### Running Podman Containers as Systemd Services

Podman integrates natively with systemd for managing containers as services:

```bash
# Create and start a container
podman run -d \
  --name myapp \
  --restart=always \
  -p 8080:8080 \
  myapp:latest

# Generate a systemd unit file for this container
podman generate systemd \
  --name myapp \
  --files \
  --new  # --new: recreate container on start (recommended)

# Move the unit file to user's systemd directory
mkdir -p ~/.config/systemd/user/
mv container-myapp.service ~/.config/systemd/user/

# Enable and start as a user service (no sudo needed!)
systemctl --user daemon-reload
systemctl --user enable --now container-myapp.service

# Check status
systemctl --user status container-myapp.service

# Enable lingering (service persists after user logout)
loginctl enable-linger $USER
```

---

## Integration with Existing Tools

### Kubernetes Integration

**Option 1: Generate K8s manifests from Podman pods (covered above)**

**Option 2: Use Podman to build and push images for Kubernetes deployment**

```bash
# Build and push image (same as Docker workflow)
podman build -t myapp:1.0.0 .
podman login your-org.jfrog.io -u user -p token
podman push myapp:1.0.0 your-org.jfrog.io/docker-local/myapp:1.0.0

# Kubernetes picks up the image from JFrog
kubectl set image deployment/myapp app=your-org.jfrog.io/docker-local/myapp:1.0.0
```

**Option 3: Use Podman play kube for local Kubernetes-like testing**

```bash
# Test your Kubernetes manifests locally with Podman before deploying to K8s
podman play kube kubernetes/deployment.yaml

# This runs the K8s pod spec locally using Podman
# Useful for rapid iteration without a real Kubernetes cluster
podman pod ls
podman ps

# Stop and clean up
podman play kube --down kubernetes/deployment.yaml
```

### JFrog Integration

Podman supports the same registry authentication as Docker:

```bash
# Login to JFrog
podman login your-org.jfrog.io \
  --username your-username \
  --password your-api-key

# Tag and push to JFrog
podman tag myapp:latest your-org.jfrog.io/docker-local/myapp:latest
podman push your-org.jfrog.io/docker-local/myapp:latest

# Pull from JFrog
podman pull your-org.jfrog.io/docker-local/myapp:1.2.3

# Inspect auth configuration
cat ~/.config/containers/auth.json
```

**Use JFrog as a remote cache/proxy for base images:**

```bash
# Configure registries.conf to use JFrog as a mirror for docker.io
cat > ~/.config/containers/registries.conf << 'EOF'
[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "your-org.jfrog.io/docker-remote"
insecure = false
EOF

# Now pulls from docker.io are transparently proxied through JFrog
podman pull ubuntu:22.04
# Fetches from your-org.jfrog.io/docker-remote/ubuntu:22.04 (cached in JFrog)
```

### Jenkins Integration — Using Podman Instead of Docker

The Docker plugin for Jenkins can be configured to use Podman with some configuration:

**Option 1: Replace docker binary with podman**

```bash
# On the Jenkins agent, create a docker → podman shim
sudo ln -s /usr/bin/podman /usr/local/bin/docker
# Jenkins Docker commands will now use Podman
```

**Option 2: Use Podman directly in Jenkinsfile**

```groovy
// Jenkinsfile using Podman natively
pipeline {
    agent {
        label 'podman-agent'  // Jenkins agent with Podman installed
    }

    environment {
        JFROG_REGISTRY = 'your-org.jfrog.io'
        IMAGE_NAME     = 'myapp'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        JFROG_CREDS    = credentials('jfrog-credentials')
    }

    stages {
        stage('Build with Podman') {
            steps {
                sh """
                    podman build \
                      --tag ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:${IMAGE_TAG} \
                      --tag ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:latest \
                      .
                """
            }
        }

        stage('Scan with Trivy') {
            steps {
                sh """
                    trivy image \
                      --exit-code 1 \
                      --severity CRITICAL \
                      ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }

        stage('Push with Podman') {
            steps {
                sh """
                    echo \${JFROG_CREDS_PSW} | \
                      podman login ${JFROG_REGISTRY} \
                        -u \${JFROG_CREDS_USR} \
                        --password-stdin

                    podman push ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:${IMAGE_TAG}
                    podman push ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:latest
                """
            }
            post {
                always {
                    sh "podman logout ${JFROG_REGISTRY} || true"
                }
            }
        }
    }

    post {
        always {
            sh """
                podman rmi ${JFROG_REGISTRY}/docker-local/${IMAGE_NAME}:${IMAGE_TAG} || true
                podman system prune -f || true
            """
        }
    }
}
```

**Option 3: Run Podman in a rootless Jenkins agent pod (Kubernetes)**

```yaml
# jenkins-agent-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-podman-agent
spec:
  containers:
  - name: podman
    image: quay.io/podman/stable:latest
    command: ["sleep", "infinity"]
    securityContext:
      # Podman needs these capabilities for rootless operation in K8s
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 1000
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
    - name: storage
      mountPath: /home/podman/.local/share/containers
  volumes:
  - name: storage
    emptyDir: {}
```

---

## Real-World Scenarios

### Scenario 1: Run a Container Rootless with Podman

```bash
# Pull a web server image as a regular user (no sudo)
podman pull nginx:alpine

# Run the web server on port 8080 (ports < 1024 require root — use 1024+)
podman run -d \
  --name my-nginx \
  -p 8080:80 \
  -v $(pwd)/html:/usr/share/nginx/html:ro,Z \
  nginx:alpine

# The :Z label is SELinux context — required on RHEL/Fedora systems
# Use :z (shared) or :Z (private) for SELinux-labeled volumes

# Verify it's running as your user
ps aux | grep nginx
# Shows: youruser  ...  nginx: master process nginx ...

# Test
curl http://localhost:8080

# Check the container details
podman container inspect my-nginx | jq '.[0].HostConfig.PortBindings'

# Clean up
podman stop my-nginx && podman rm my-nginx
```

### Scenario 2: Create a Pod with Multiple Containers

```bash
# Create a pod that groups an app and its sidecar log collector
podman pod create \
  --name webapp-pod \
  --publish 8080:8080 \
  --publish 9090:9090

# Add the main application container to the pod
podman run -d \
  --pod webapp-pod \
  --name webapp \
  -e LOG_DIR=/var/log/app \
  -v app-logs:/var/log/app \
  myapp:latest

# Add a log shipper sidecar (shares network namespace with webapp)
podman run -d \
  --pod webapp-pod \
  --name log-shipper \
  -v app-logs:/var/log/app:ro \
  fluent/fluent-bit:latest

# Add a Prometheus metrics exporter sidecar
podman run -d \
  --pod webapp-pod \
  --name metrics \
  -e APP_URL=http://localhost:8080/metrics \
  prom/pushgateway:latest

# List the pod and its containers
podman pod inspect webapp-pod
podman pod stats webapp-pod

# The sidecar can reach the app on localhost because they share a network namespace
podman exec log-shipper curl http://localhost:8080/health  # ← localhost works!

# Stop the entire pod (stops all containers)
podman pod stop webapp-pod

# Generate systemd unit for the pod
podman generate systemd --pod --name webapp-pod --files --new
```

### Scenario 3: Generate K8s Manifests from a Podman Pod

This scenario demonstrates the development workflow: design your pod locally with Podman, then export it to Kubernetes YAML.

```bash
# Step 1: Design the pod locally

# Create a multi-container pod
podman pod create --name order-service-pod -p 8082:8082

# Application container
podman run -d \
  --pod order-service-pod \
  --name order-app \
  --env-file .env.local \
  -e DB_HOST=localhost \
  -e REDIS_HOST=localhost \
  order-service:1.0.0

# Redis sidecar cache
podman run -d \
  --pod order-service-pod \
  --name order-redis \
  redis:7-alpine

# Step 2: Test locally
curl http://localhost:8082/orders

# Step 3: Export to Kubernetes YAML
podman generate kube order-service-pod --service > order-service-k8s.yaml

# Podman generates both a Pod spec and a Service spec
cat order-service-k8s.yaml

# Step 4: Review and edit the YAML
# Add resource limits, liveness/readiness probes, etc.
# The generated YAML is a starting point, not production-ready as-is

# Step 5: Play it back with Podman to verify YAML is valid
podman pod rm order-service-pod  # Remove original pod
podman play kube order-service-k8s.yaml  # Recreate from YAML

# Step 6: Apply to Kubernetes
# First, fix the image references to point to your JFrog registry
sed -i 's|order-service:1.0.0|your-org.jfrog.io/docker-local/order-service:1.0.0|g' \
  order-service-k8s.yaml

kubectl apply -f order-service-k8s.yaml -n production
kubectl get pods -n production
```

---

## Verification & Testing

### Basic Verification

```bash
# Check Podman version and runtime info
podman version
podman info

# Check rootless configuration
podman info | grep -E "rootless|cgroupVersion"

# List images
podman images

# List running containers
podman ps

# List all containers
podman ps -a

# List pods
podman pod ls

# Check system resource usage
podman system df

# Perform a system health check
podman system check
```

### Testing Rootless Behaviour

```bash
# Verify no containers are running as root on the host
podman run -d --name test-rootless alpine sleep 3600

# On the HOST, find the process and verify UID
PID=$(podman inspect test-rootless --format '{{.State.Pid}}')
ps -o user,pid,comm -p $PID
# Should show YOUR username, not root

# Inside the container it appears as root
podman exec test-rootless id
# uid=0(root) gid=0(root)

# Verify the kernel-level UID mapping
cat /proc/$PID/status | grep -E "Uid|Gid"
# Shows: Uid: 1000 1000 1000 1000 (your UID, not 0)

# Clean up
podman rm -f test-rootless
```

### Network Verification

```bash
# List Podman networks
podman network ls

# Inspect default network
podman network inspect podman

# Test connectivity between containers in a pod
podman pod create --name test-pod -p 9999:80
podman run -d --pod test-pod --name server nginx:alpine
podman run -d --pod test-pod --name client alpine sleep 3600
podman exec client wget -qO- http://localhost:80  # Works — same network namespace
podman pod rm -f test-pod
```

---

## Troubleshooting Guide

### Issue 1: newuidmap / newgidmap Error

```
Error: cannot setup namespace using newuidmap: no subuid ranges found for user
```

**Fix:**
```bash
# Check if subuid/subgid are configured
grep $USER /etc/subuid /etc/subgid

# If not, add them
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
podman system migrate
```

### Issue 2: Can't Bind to Port < 1024

```
Error: rootlessport cannot expose privileged port 80
```

**Fix:** Use a port >= 1024, or configure `net.ipv4.ip_unprivileged_port_start`:
```bash
# Use 8080 instead of 80
podman run -p 8080:80 nginx

# Or lower the unprivileged port threshold (system-wide)
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-podman.conf
sudo sysctl --system
```

### Issue 3: Volume Mount Permission Denied

```
Error: permission denied: /path/to/host/dir
```

**Fix:**
```bash
# Use :Z for SELinux systems
podman run -v /host/path:/container/path:Z myimage

# Or fix ownership to match container UID
podman unshare chown 1000:1000 /host/path
```

### Issue 4: Image Not Found in Registry

```
Error: trying to reuse blob sha256:... at destination: unauthorized
```

**Fix:**
```bash
# Re-authenticate
podman login your-registry.example.com

# Check auth config
cat ~/.config/containers/auth.json
```

### Issue 5: Podman Machine Not Running (macOS)

```
Error: Cannot connect to Podman. Is the podman socket running?
```

**Fix:**
```bash
podman machine start
podman machine list  # Verify it's running
```

### Issue 6: podman-compose vs docker compose Differences

Some Docker Compose features aren't fully supported by podman-compose.

**Fix:** Use `podman compose` (Podman 4.7+) which uses the Docker Compose binary:
```bash
# Install docker-compose binary
pip3 install docker-compose

# Use podman compose (wraps docker-compose with podman socket)
podman compose up -d
```

### Issue 7: SELinux Denying Container Access

```
AVC avc: denied { read } for pid=... comm="nginx" name="index.html"
```

**Fix:**
```bash
# Use :Z label on volume mounts (relabels the volume for the container)
podman run -v /host/html:/usr/share/nginx/html:ro,Z nginx

# Or temporarily set SELinux to permissive for debugging (NOT for production)
sudo setenforce 0
```

### Issue 8: Containers Not Persisting After Reboot

**Fix:** Generate and enable a systemd service:
```bash
podman generate systemd --name mycontainer --files --new
mv container-mycontainer.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now container-mycontainer.service
loginctl enable-linger $USER  # Persist after logout
```

### Issue 9: Network Issues Between Pods

**Fix:**
```bash
# Containers in different pods need to be on the same Podman network
podman network create shared-net

podman run -d --network shared-net --name service-a myapp-a:latest
podman run -d --network shared-net --name service-b myapp-b:latest

# Now service-b can reach service-a at http://service-a:8080
podman exec service-b curl http://service-a:8080/health
```

### Issue 10: Buildah vs Podman Build Confusion

Podman uses Buildah for building images. If `podman build` fails:

```bash
# Check if buildah is installed
which buildah
buildah version

# Try building directly with buildah
buildah bud -t myapp:latest .

# Use --format oci or --format docker explicitly
podman build --format docker -t myapp:latest .
```

---

## Cheat Sheet

### Core Podman Commands

| Command | Description |
|---------|-------------|
| `podman version` | Show Podman version |
| `podman info` | Show system and runtime information |
| `podman run -d image` | Run container in background |
| `podman run -it image sh` | Run container interactively |
| `podman run --rm image` | Run and remove on exit |
| `podman ps` | List running containers |
| `podman ps -a` | List all containers |
| `podman stop container` | Stop a container |
| `podman rm container` | Remove a container |
| `podman rm -f container` | Force remove running container |
| `podman images` | List local images |
| `podman pull image:tag` | Pull an image |
| `podman push image:tag` | Push an image to registry |
| `podman build -t name:tag .` | Build image from Dockerfile |
| `podman tag src:tag dst:tag` | Tag an image |
| `podman rmi image:tag` | Remove an image |
| `podman logs -f container` | Follow container logs |
| `podman exec -it container sh` | Open shell in running container |
| `podman inspect container` | Show container details |
| `podman stats` | Live resource usage |
| `podman system df` | Show disk usage |
| `podman system prune` | Remove unused resources |
| `podman login registry` | Authenticate to registry |
| `podman logout registry` | Remove stored credentials |

### Pod Commands

| Command | Description |
|---------|-------------|
| `podman pod create --name name -p 8080:80` | Create a pod with port mapping |
| `podman pod ls` | List pods |
| `podman pod inspect name` | Show pod details |
| `podman pod start name` | Start a pod |
| `podman pod stop name` | Stop a pod |
| `podman pod rm name` | Remove a pod |
| `podman pod rm -f name` | Force remove pod and containers |
| `podman pod stats name` | Resource usage for pod |
| `podman run -d --pod name image` | Add container to a pod |
| `podman generate kube name` | Generate K8s YAML from pod |
| `podman play kube pod.yaml` | Create pod from K8s YAML |
| `podman play kube --down pod.yaml` | Remove pod created from YAML |

### Machine Commands (macOS/Windows)

| Command | Description |
|---------|-------------|
| `podman machine init` | Initialize a new machine (VM) |
| `podman machine start` | Start the Podman machine |
| `podman machine stop` | Stop the Podman machine |
| `podman machine list` | List Podman machines |
| `podman machine inspect` | Show machine details |
| `podman machine rm` | Remove a machine |
| `podman machine ssh` | SSH into the machine |

### Comparison: Docker vs Podman Commands

| Docker | Podman | Notes |
|--------|--------|-------|
| `docker run` | `podman run` | Identical syntax |
| `docker build` | `podman build` | Identical syntax |
| `docker push` | `podman push` | Identical syntax |
| `docker pull` | `podman pull` | Identical syntax |
| `docker ps` | `podman ps` | Identical syntax |
| `docker exec` | `podman exec` | Identical syntax |
| `docker logs` | `podman logs` | Identical syntax |
| `docker-compose` | `podman-compose` | Similar, minor differences |
| N/A | `podman pod create` | Pods are Podman-specific |
| N/A | `podman generate kube` | Podman-specific |
| N/A | `podman play kube` | Podman-specific |
| N/A | `podman unshare` | Rootless user namespace entry |
| `docker system prune` | `podman system prune` | Identical |
| `docker login` | `podman login` | Identical |

---

*This guide covers Podman as used in the context of the DevOps Final Project. For the latest documentation, see [https://docs.podman.io](https://docs.podman.io).*
