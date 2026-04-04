# Docker Complete Guide

## Table of Contents
1. [Overview & Why Docker](#overview--why-docker)
2. [Local Setup](#local-setup)
3. [Online/Cloud Setup](#onlinecloud-setup)
4. [Configuration Deep Dive](#configuration-deep-dive)
5. [Integration with Existing Tools](#integration-with-existing-tools)
6. [Real-World Scenarios](#real-world-scenarios)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Cheat Sheet](#cheat-sheet)

---

## Overview & Why Docker

### Containers vs Virtual Machines

Before containers, applications were deployed on **Virtual Machines (VMs)**. A VM emulates an entire computer — CPU, memory, disk, network — by running on a **hypervisor** (VMware, Hyper-V, VirtualBox, KVM). This means each VM includes a full OS installation, making them:

- **Heavy**: A VM might be 10–50 GB
- **Slow to start**: Boot time of 30–90 seconds
- **Resource-intensive**: Each VM needs its own OS kernel, memory, CPU allocation

**Containers** take a fundamentally different approach. They share the host OS kernel and isolate only the application and its dependencies using Linux kernel features (namespaces, cgroups):

| Aspect | Containers | Virtual Machines |
|--------|-----------|-----------------|
| Size | Megabytes | Gigabytes |
| Startup time | Milliseconds to seconds | Minutes |
| OS overhead | Shares host kernel | Full OS per VM |
| Isolation | Process-level | Full hardware |
| Portability | Very high | Medium |
| Performance | Near-native | 5-15% overhead |
| Security boundary | Weaker (shared kernel) | Stronger |

**When to use VMs still:** When you need strong security isolation (multi-tenant environments), different OS kernels (running Windows and Linux workloads), or hardware-level isolation.

### Docker Architecture

Docker uses a **client-server architecture**:

```
┌─────────────┐         REST API / Unix Socket        ┌────────────────────┐
│ Docker CLI  │ ─────────────────────────────────────► │  Docker Daemon     │
│ (docker)    │                                        │  (dockerd)         │
└─────────────┘                                        │                    │
                                                       │  ┌──────────────┐  │
                                                       │  │  Container 1 │  │
                                                       │  │  Container 2 │  │
                                                       │  │  Container N │  │
                                                       │  └──────────────┘  │
                                                       └────────────────────┘
                                                                │
                                                                ▼
                                                       ┌────────────────────┐
                                                       │  Docker Registry   │
                                                       │  (Docker Hub,      │
                                                       │   JFrog, ACR, ECR) │
                                                       └────────────────────┘
```

**Key components:**
- **Docker CLI** (`docker`): The command-line interface users interact with
- **Docker Daemon** (`dockerd`): Background service managing containers, images, networks, volumes
- **Docker Registry**: Storage for container images (Docker Hub is public; you can run private registries)
- **containerd**: Low-level container runtime Docker uses internally (also used directly by Kubernetes)
- **runc**: OCI-compliant container runtime that actually creates and starts containers

### Image Layers

Docker images are built in **layers**. Each instruction in a `Dockerfile` creates a new read-only layer:

```
┌──────────────────────────────────┐
│  Layer 5: COPY app.jar /app/     │  ← Your application code
├──────────────────────────────────┤
│  Layer 4: RUN apt-get install    │  ← System dependencies
├──────────────────────────────────┤
│  Layer 3: RUN useradd appuser    │  ← User creation
├──────────────────────────────────┤
│  Layer 2: FROM eclipse-temurin   │  ← JDK base layer
├──────────────────────────────────┤
│  Layer 1: FROM ubuntu:22.04      │  ← Base OS layer
└──────────────────────────────────┘
         Read-only layers (image)

┌──────────────────────────────────┐
│  Writable container layer        │  ← Created when container starts
└──────────────────────────────────┘
```

**Why layers matter:**
- Layers are **cached** — if a layer hasn't changed, Docker reuses it (huge speed boost for rebuilds)
- Layers are **shared** — multiple images sharing the same base layer store it only once on disk
- Order matters for cache efficiency — put frequently-changing instructions (COPY app code) last

---

## Local Setup

### Docker Engine on Ubuntu

```bash
# Remove old versions
sudo apt remove docker docker-engine docker.io containerd runc 2>/dev/null

# Install prerequisites
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
sudo systemctl enable --now docker

# Add your user to the docker group (log out and back in after this)
sudo usermod -aG docker $USER

# Verify
docker version
docker run hello-world
```

### Docker Desktop on macOS

```bash
# Using Homebrew
brew install --cask docker

# Or download from https://www.docker.com/products/docker-desktop/
# After installation, start Docker Desktop from Applications
```

**macOS-specific notes:**
- Docker Desktop runs a lightweight Linux VM (using Apple Hypervisor)
- Performance is slightly lower than native Linux
- Enable VirtioFS in settings for better bind mount performance

### Docker Compose

Docker Compose is now a Docker CLI plugin (compose V2):

```bash
# Already included with Docker Engine installation above
docker compose version

# Verify (should show Docker Compose version 2.x)
docker compose version
# Docker Compose version v2.21.0
```

For legacy `docker-compose` (V1):
```bash
# Not recommended — use the V2 plugin instead
# pip install docker-compose  # legacy approach
```

### Configure Docker Daemon

Edit `/etc/docker/daemon.json` to configure the Docker daemon:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "registry-mirrors": [],
  "insecure-registries": []
}
```

```bash
sudo systemctl restart docker
```

---

## Online/Cloud Setup

### Play with Docker

[Play with Docker](https://labs.play-with-docker.com/) provides a free, browser-based Docker environment:

1. Go to [https://labs.play-with-docker.com/](https://labs.play-with-docker.com/)
2. Sign in with Docker Hub credentials
3. Click **+ ADD NEW INSTANCE**
4. You have a full Linux VM with Docker installed, valid for 4 hours

Great for learning and testing without any local installation.

### Killercoda

[Killercoda](https://killercoda.com/playgrounds/scenario/docker) provides persistent Docker playground scenarios:

1. Navigate to [https://killercoda.com/](https://killercoda.com/)
2. Search for "Docker" scenarios
3. Provides step-by-step guided scenarios with a terminal

### Azure Container Instances (Quick Testing)

```bash
# Run a container in Azure without Kubernetes
az container create \
  --resource-group my-rg \
  --name test-container \
  --image nginx:latest \
  --ports 80 \
  --dns-name-label my-test-app-$(openssl rand -hex 4)

az container show \
  --resource-group my-rg \
  --name test-container \
  --query instanceView.state
```

---

## Configuration Deep Dive

### Dockerfile Best Practices

#### Multi-Stage Build for Java Spring Boot

```dockerfile
# Dockerfile for Java Spring Boot Application

# ─── Stage 1: Build ───────────────────────────────────────────────────────────
# Use a full JDK image for building — it has Maven/Gradle and all build tools
FROM eclipse-temurin:17-jdk-jammy AS builder

# Set working directory for the build stage
WORKDIR /build

# Copy dependency files first (optimizes layer caching)
# If pom.xml doesn't change, Maven dependencies are cached
COPY pom.xml .
COPY .mvn/ .mvn/
COPY mvnw .

# Download dependencies in a separate layer (cached unless pom.xml changes)
RUN ./mvnw dependency:resolve -q

# Now copy source code (changes more frequently)
COPY src/ src/

# Build the application, skipping tests (tests run separately in CI)
RUN ./mvnw package -DskipTests -q

# ─── Stage 2: Extract layers (Spring Boot 2.3+) ───────────────────────────────
# Use Spring Boot's layered JAR feature to optimise Docker layer caching
FROM eclipse-temurin:17-jdk-jammy AS extractor
WORKDIR /extract
COPY --from=builder /build/target/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# ─── Stage 3: Runtime ─────────────────────────────────────────────────────────
# Use a minimal JRE image — no build tools, smaller attack surface
FROM eclipse-temurin:17-jre-jammy AS runtime

# Security: run as non-root user
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --home /app appuser

WORKDIR /app

# Copy extracted layers in order from least to most frequently changed
# This maximises cache reuse when only app code changes
COPY --from=extractor --chown=appuser:appgroup /extract/dependencies/ ./
COPY --from=extractor --chown=appuser:appgroup /extract/spring-boot-loader/ ./
COPY --from=extractor --chown=appuser:appgroup /extract/snapshot-dependencies/ ./
COPY --from=extractor --chown=appuser:appgroup /extract/application/ ./

# Switch to non-root user
USER appuser

# Document the port the application listens on (doesn't actually publish it)
EXPOSE 8080

# Health check — Docker will mark the container unhealthy if this fails
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Use exec form (not shell form) to ensure PID 1 receives signals
ENTRYPOINT ["java", "org.springframework.boot.loader.JarLauncher"]
```

#### Multi-Stage Build for Node.js

```dockerfile
# Dockerfile for Node.js Application

# ─── Stage 1: Dependencies ────────────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy package files only — layer cached until package.json changes
COPY package.json package-lock.json ./

# Install production dependencies only
RUN npm ci --only=production && \
    # Remove npm cache to reduce image size
    npm cache clean --force

# ─── Stage 2: Build ───────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
# Install ALL dependencies (including devDependencies for build tools)
RUN npm ci

COPY . .

# Build the application (TypeScript compilation, bundling, etc.)
RUN npm run build

# ─── Stage 3: Runtime ─────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

# Install dumb-init for proper signal handling in containers
RUN apk add --no-cache dumb-init

# Security: run as non-root
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser

WORKDIR /app

# Copy only production dependencies from deps stage
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy built application from builder stage
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --chown=appuser:appgroup package.json .

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Use dumb-init to handle signals correctly (avoids zombie processes)
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/index.js"]
```

#### Multi-Stage Build for Python

```dockerfile
# Dockerfile for Python Application

# ─── Stage 1: Build dependencies ─────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build tools needed for compiling Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies into a directory we'll copy to the final image
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Only install runtime system dependencies (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Security: run as non-root
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --home /app appuser

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY --chown=appuser:appgroup src/ ./src/
COPY --chown=appuser:appgroup app.py .

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

### .dockerignore

The `.dockerignore` file prevents unnecessary files from being sent to the Docker build context (speeds up builds and reduces layer size):

```dockerignore
# Version control
.git
.gitignore
.gitattributes

# CI/CD
.github
.gitlab-ci.yml
Jenkinsfile

# Documentation
*.md
docs/
LICENSE

# IDE
.vscode
.idea
*.iml
*.swp

# Build output (will be rebuilt inside container)
target/
build/
dist/
node_modules/

# Test files
**/*_test.go
**/*.test.ts
**/*.spec.js
test/
tests/
__tests__/

# Terraform
**/.terraform
*.tfstate
*.tfvars
*.tfplan

# Docker-specific
Dockerfile*
docker-compose*.yml
.dockerignore

# Secrets (NEVER include in images)
.env
.env.*
*.pem
*.key
secrets/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/
```

### docker-compose.yaml for Local Development

```yaml
# docker-compose.yml — Local development environment

version: "3.9"

# Shared networking — all services can reach each other by service name
networks:
  app-network:
    driver: bridge

# Persistent storage volumes
volumes:
  postgres-data:
  redis-data:
  maven-cache:

services:
  # ─── Application ─────────────────────────────────────────────────────────────
  app:
    build:
      context: .
      dockerfile: Dockerfile
      # Use the builder stage for dev (includes dev tools)
      target: builder
      args:
        APP_ENV: development
    image: myapp:dev
    container_name: myapp-dev
    ports:
      - "8080:8080"
      # Remote debug port
      - "5005:5005"
    environment:
      - SPRING_PROFILES_ACTIVE=dev
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/myappdb
      - SPRING_DATASOURCE_USERNAME=myapp
      - SPRING_DATASOURCE_PASSWORD=localpassword
      - SPRING_REDIS_HOST=redis
      - JAVA_TOOL_OPTIONS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005
    volumes:
      # Mount source code for live reload (requires Spring DevTools)
      - ./src:/build/src:ro
      # Mount Maven cache to speed up rebuilds
      - maven-cache:/root/.m2
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s

  # ─── PostgreSQL ───────────────────────────────────────────────────────────────
  postgres:
    image: postgres:15-alpine
    container_name: myapp-postgres
    ports:
      - "5432:5432"  # Expose for local DB clients (DBeaver, etc.)
    environment:
      POSTGRES_DB: myappdb
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: localpassword
    volumes:
      # Persist data across container restarts
      - postgres-data:/var/lib/postgresql/data
      # Run init scripts on first start
      - ./scripts/db-init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - app-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp -d myappdb"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─── Redis ────────────────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: myapp-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

  # ─── SonarQube (local quality checks) ────────────────────────────────────────
  sonarqube:
    image: sonarqube:community
    container_name: myapp-sonarqube
    ports:
      - "9000:9000"
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
    volumes:
      - sonarqube-data:/opt/sonarqube/data
      - sonarqube-logs:/opt/sonarqube/logs
    networks:
      - app-network
    profiles:
      # Only started with: docker compose --profile quality up
      - quality

volumes:
  sonarqube-data:
  sonarqube-logs:
```

```bash
# Start all services
docker compose up -d

# Start specific services
docker compose up -d app postgres redis

# View logs
docker compose logs -f app

# Start with quality profile (includes SonarQube)
docker compose --profile quality up -d

# Stop all services
docker compose down

# Stop and remove volumes (fresh start)
docker compose down -v
```

### Image Scanning with Trivy

[Trivy](https://github.com/aquasecurity/trivy) is a comprehensive security scanner for container images:

```bash
# Install Trivy on Ubuntu
sudo apt install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update && sudo apt install trivy

# Scan an image for vulnerabilities
trivy image myapp:latest

# Scan with severity filter (only HIGH and CRITICAL)
trivy image --severity HIGH,CRITICAL myapp:latest

# Exit with non-zero code if vulnerabilities found (use in CI)
trivy image --exit-code 1 --severity CRITICAL myapp:latest

# Scan and output as JSON for processing
trivy image --format json --output trivy-report.json myapp:latest

# Scan a Dockerfile for misconfigurations
trivy config --exit-code 1 ./Dockerfile

# Scan for secrets in the image filesystem
trivy image --scanners secret myapp:latest

# Scan the image and generate SARIF output (upload to GitHub Security)
trivy image --format sarif --output trivy.sarif myapp:latest
```

### Build Arguments and Environment Variables

```dockerfile
# Using build arguments (set at build time, not stored in final image)
ARG APP_VERSION=1.0.0
ARG BUILD_DATE
ARG GIT_COMMIT

# Label the image with build metadata
LABEL org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="https://github.com/your-org/your-repo"

# ENV variables are available at runtime
ENV APP_VERSION=${APP_VERSION} \
    PORT=8080 \
    LOG_LEVEL=INFO
```

```bash
# Pass build args at build time
docker build \
  --build-arg APP_VERSION=2.1.0 \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  -t myapp:2.1.0 .
```

---

## Integration with Existing Tools

### JFrog Artifactory Integration

**Authenticate and push/pull images:**

```bash
# Login to JFrog Artifactory Docker registry
docker login your-org.jfrog.io \
  --username your-username \
  --password your-api-key

# Tag your image with the JFrog registry URL
docker tag myapp:latest your-org.jfrog.io/docker-local/myapp:latest
docker tag myapp:latest your-org.jfrog.io/docker-local/myapp:1.0.0

# Push image
docker push your-org.jfrog.io/docker-local/myapp:latest
docker push your-org.jfrog.io/docker-local/myapp:1.0.0

# Pull image
docker pull your-org.jfrog.io/docker-local/myapp:1.0.0
```

**Dockerfile configured to pull base images from JFrog (air-gapped environments):**

```dockerfile
# Instead of pulling from Docker Hub, pull from your JFrog proxy cache
FROM your-org.jfrog.io/docker-remote/eclipse-temurin:17-jre-jammy

# JFrog "docker-remote" repository proxies and caches Docker Hub images
# This ensures you always use scanned, approved base images
WORKDIR /app
COPY --chown=appuser:appgroup app.jar .
USER appuser
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Configure Docker daemon to use JFrog as registry mirror:**

```json
// /etc/docker/daemon.json
{
  "registry-mirrors": ["https://your-org.jfrog.io/artifactory/api/docker/docker-remote"]
}
```

### Jenkins Integration

**Complete Jenkinsfile: Build → Scan → Push to JFrog:**

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        JFROG_REGISTRY  = 'your-org.jfrog.io'
        JFROG_REPO      = 'docker-local'
        IMAGE_NAME      = 'myapp'
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE_NAME = "${JFROG_REGISTRY}/${JFROG_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
        JFROG_CREDS     = credentials('jfrog-credentials')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build \
                      --build-arg APP_VERSION=${IMAGE_TAG} \
                      --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                      --build-arg GIT_COMMIT=${GIT_COMMIT} \
                      --tag ${FULL_IMAGE_NAME} \
                      --tag ${JFROG_REGISTRY}/${JFROG_REPO}/${IMAGE_NAME}:latest \
                      .
                """
            }
        }

        stage('Scan with Trivy') {
            steps {
                sh """
                    # Run Trivy scan — fail build on CRITICAL vulnerabilities
                    trivy image \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --format table \
                      ${FULL_IMAGE_NAME}
                """
            }
            post {
                always {
                    // Generate HTML report regardless of scan result
                    sh """
                        trivy image \
                          --format template \
                          --template "@/usr/local/share/trivy/templates/html.tpl" \
                          --output trivy-report.html \
                          ${FULL_IMAGE_NAME}
                    """
                    publishHTML(target: [
                        reportName: 'Trivy Security Report',
                        reportDir: '.',
                        reportFiles: 'trivy-report.html',
                        keepAll: true
                    ])
                }
            }
        }

        stage('Push to JFrog') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                sh """
                    echo \${JFROG_CREDS_PSW} | \
                      docker login ${JFROG_REGISTRY} \
                        -u \${JFROG_CREDS_USR} \
                        --password-stdin

                    docker push ${FULL_IMAGE_NAME}
                    docker push ${JFROG_REGISTRY}/${JFROG_REPO}/${IMAGE_NAME}:latest
                """
            }
            post {
                always {
                    sh 'docker logout ${JFROG_REGISTRY}'
                }
            }
        }

        stage('Update Deployment Manifest') {
            when {
                branch 'main'
            }
            steps {
                // Update the image tag in the GitOps repo
                withCredentials([usernamePassword(credentialsId: 'github-token',
                                                  usernameVariable: 'GIT_USER',
                                                  passwordVariable: 'GIT_TOKEN')]) {
                    sh """
                        git clone https://\${GIT_USER}:\${GIT_TOKEN}@github.com/your-org/gitops-repo.git
                        cd gitops-repo
                        sed -i "s|image: .*${IMAGE_NAME}:.*|image: ${FULL_IMAGE_NAME}|g" \
                          apps/myapp/deployment.yaml
                        git config user.email "jenkins@ci"
                        git config user.name "Jenkins CI"
                        git add apps/myapp/deployment.yaml
                        git commit -m "ci: update ${IMAGE_NAME} image to ${IMAGE_TAG}"
                        git push
                    """
                }
            }
        }
    }

    post {
        always {
            // Clean up local images to free disk space
            sh """
                docker rmi ${FULL_IMAGE_NAME} || true
                docker rmi ${JFROG_REGISTRY}/${JFROG_REPO}/${IMAGE_NAME}:latest || true
                docker system prune -f
            """
        }
        failure {
            slackSend channel: '#builds',
                      color: 'danger',
                      message: "Docker build FAILED: ${IMAGE_NAME}:${IMAGE_TAG} — ${env.BUILD_URL}"
        }
    }
}
```

### Kubernetes Integration

**Deploying Docker images to Kubernetes:**

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      # Reference the secret for authenticating with JFrog registry
      imagePullSecrets:
        - name: jfrog-registry-secret

      containers:
        - name: myapp
          # Full image path including JFrog registry
          image: your-org.jfrog.io/docker-local/myapp:1.2.3
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 5
```

**Create the imagePullSecret for JFrog:**

```bash
# Create a Kubernetes secret for JFrog registry authentication
kubectl create secret docker-registry jfrog-registry-secret \
  --namespace production \
  --docker-server=your-org.jfrog.io \
  --docker-username=your-username \
  --docker-password=your-api-key \
  --docker-email=your@email.com

# Verify the secret was created
kubectl get secret jfrog-registry-secret -o yaml -n production
```

### SonarQube in Docker

**Run SonarQube scanner as a Docker container:**

```bash
# Run SonarQube server locally
docker run -d \
  --name sonarqube \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  sonarqube:community

# Wait for startup
until curl -s http://localhost:9000/api/system/status | grep -q '"status":"UP"'; do
  echo "Waiting for SonarQube..."
  sleep 5
done

# Run scanner against your project
docker run --rm \
  --network host \
  -v "$(pwd):/usr/src" \
  sonarsource/sonar-scanner-cli \
  sonar-scanner \
    -Dsonar.projectKey=myapp \
    -Dsonar.sources=./src \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.login=your-sonar-token
```

---

## Real-World Scenarios

### Scenario 1: Multi-Stage Build for Java Spring Boot

```bash
# Build the production image
docker build \
  --build-arg APP_VERSION=2.0.0 \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  --tag mycompany/spring-app:2.0.0 \
  --tag mycompany/spring-app:latest \
  .

# Check image size (multi-stage should be much smaller than a fat JAR in full JDK)
docker images mycompany/spring-app

# Run and test locally
docker run -d \
  --name spring-app \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=dev \
  mycompany/spring-app:2.0.0

docker logs -f spring-app

# Test the health endpoint
curl http://localhost:8080/actuator/health

# Inspect image layers
docker history mycompany/spring-app:2.0.0
```

### Scenario 2: Build, Scan, and Push to JFrog Artifactory

```bash
# Configure JFrog credentials
export JFROG_URL="your-org.jfrog.io"
export JFROG_USER="your-username"
export JFROG_PASS="your-api-key"
export APP_VERSION="1.2.3"
export IMAGE="${JFROG_URL}/docker-local/myapp:${APP_VERSION}"

# Build
docker build \
  --build-arg APP_VERSION=${APP_VERSION} \
  --tag ${IMAGE} \
  .

# Scan with Trivy — exit 1 on CRITICAL findings
trivy image \
  --exit-code 1 \
  --severity CRITICAL,HIGH \
  --format table \
  ${IMAGE}

echo "Security scan passed. Pushing to JFrog..."

# Login and push
echo "${JFROG_PASS}" | docker login "${JFROG_URL}" -u "${JFROG_USER}" --password-stdin
docker push ${IMAGE}

# Add latest tag
docker tag ${IMAGE} ${JFROG_URL}/docker-local/myapp:latest
docker push ${JFROG_URL}/docker-local/myapp:latest

# Logout
docker logout "${JFROG_URL}"

echo "Image pushed: ${IMAGE}"
```

### Scenario 3: Docker Networking for Microservices Local Dev

```yaml
# docker-compose.microservices.yml

version: "3.9"

# Separate networks per concern — services only see what they need to
networks:
  frontend-network:    # API Gateway ↔ Frontend
    driver: bridge
  backend-network:     # Internal services communication
    driver: bridge
  data-network:        # Services ↔ Databases (isolated)
    driver: bridge

services:
  # API Gateway — the only service exposed to the host
  api-gateway:
    image: your-org.jfrog.io/docker-local/api-gateway:latest
    ports:
      - "8080:8080"
    networks:
      - frontend-network
      - backend-network
    environment:
      - USER_SERVICE_URL=http://user-service:8081
      - ORDER_SERVICE_URL=http://order-service:8082
      - PRODUCT_SERVICE_URL=http://product-service:8083

  # User Service — backend only, not exposed to host
  user-service:
    image: your-org.jfrog.io/docker-local/user-service:latest
    networks:
      - backend-network
      - data-network
    environment:
      - DB_URL=jdbc:postgresql://user-db:5432/userdb

  # Order Service
  order-service:
    image: your-org.jfrog.io/docker-local/order-service:latest
    networks:
      - backend-network
      - data-network
    environment:
      - DB_URL=jdbc:postgresql://order-db:5432/orderdb
      - RABBIT_URL=amqp://rabbitmq:5672

  # Product Service
  product-service:
    image: your-org.jfrog.io/docker-local/product-service:latest
    networks:
      - backend-network
      - data-network
    environment:
      - DB_URL=jdbc:postgresql://product-db:5432/productdb

  # Message broker — backend only
  rabbitmq:
    image: rabbitmq:3-management-alpine
    ports:
      - "15672:15672"  # Management UI only
    networks:
      - backend-network

  # Databases — isolated in data-network
  user-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: userdb
      POSTGRES_PASSWORD: localpass
    networks:
      - data-network
    volumes:
      - user-db-data:/var/lib/postgresql/data

  order-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orderdb
      POSTGRES_PASSWORD: localpass
    networks:
      - data-network
    volumes:
      - order-db-data:/var/lib/postgresql/data

  product-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: productdb
      POSTGRES_PASSWORD: localpass
    networks:
      - data-network
    volumes:
      - product-db-data:/var/lib/postgresql/data

volumes:
  user-db-data:
  order-db-data:
  product-db-data:
```

```bash
# Start the microservices stack
docker compose -f docker-compose.microservices.yml up -d

# Verify all containers are running
docker compose -f docker-compose.microservices.yml ps

# Test service-to-service communication
docker exec api-gateway curl -s http://user-service:8081/health
docker exec api-gateway curl -s http://order-service:8082/health

# Confirm isolation: user-service CANNOT reach user-db from api-gateway
# (api-gateway is not in data-network)
docker exec api-gateway ping user-db  # Should fail — correct isolation!
```

---

## Verification & Testing

### Container Health Verification

```bash
# List running containers with status
docker ps
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container health status
docker inspect --format='{{.State.Health.Status}}' container-name

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' container-name

# View container resource usage
docker stats --no-stream

# View detailed container info
docker inspect container-name | jq '.[0].State'
```

### Image Verification

```bash
# View image metadata
docker inspect image-name:tag

# View image layers and sizes
docker history --no-trunc image-name:tag

# Check image size
docker images --filter reference="myapp*"

# Verify labels
docker inspect --format='{{json .Config.Labels}}' image-name:tag | jq .

# Scan for vulnerabilities
trivy image --severity HIGH,CRITICAL image-name:tag

# Verify the image runs as non-root
docker run --rm image-name:tag whoami  # Should NOT output "root"
docker run --rm image-name:tag id      # Should show non-zero UID
```

### Testing with Container Structure Tests

```yaml
# container-structure-test.yaml
schemaVersion: "2.0.0"

commandTests:
  - name: "Java version"
    command: "java"
    args: ["-version"]
    expectedError: ["version \"17"]

  - name: "App runs as non-root"
    command: "id"
    args: []
    expectedOutput: ["uid=(?!0)"]

fileExistenceTests:
  - name: "Application jar exists"
    path: "/app/app.jar"
    shouldExist: true

  - name: "No sensitive files"
    path: "/app/.env"
    shouldExist: false

metadataTest:
  exposedPorts: ["8080"]
  user: "appuser"
```

```bash
# Install and run container structure tests
curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-linux-amd64
chmod +x container-structure-test-linux-amd64
./container-structure-test-linux-amd64 test \
  --image myapp:latest \
  --config container-structure-test.yaml
```

---

## Troubleshooting Guide

### Issue 1: Cannot Connect to Docker Daemon

```
Error: Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Fix:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
# Or add user to docker group:
sudo usermod -aG docker $USER && newgrp docker
```

### Issue 2: Image Pull Fails (Credentials)

```
Error response from daemon: pull access denied
```

**Fix:**
```bash
docker login your-registry.example.com
# Or for JFrog:
docker login your-org.jfrog.io -u user -p api-key
```

### Issue 3: Port Already in Use

```
Error: Bind for 0.0.0.0:8080 failed: port is already allocated
```

**Fix:**
```bash
# Find what's using the port
sudo ss -tlnp | grep 8080
# Or use a different host port:
docker run -p 8081:8080 myapp:latest
```

### Issue 4: Container Exits Immediately

**Fix:**
```bash
# Check logs
docker logs container-name

# Run interactively to debug
docker run -it --entrypoint /bin/sh myapp:latest

# Check exit code
docker inspect container-name --format='{{.State.ExitCode}}'
```

### Issue 5: Out of Disk Space

```
Error: no space left on device
```

**Fix:**
```bash
# Remove stopped containers, unused images, volumes, networks
docker system prune -a --volumes

# More selective cleanup
docker container prune    # Remove stopped containers
docker image prune -a     # Remove unused images
docker volume prune       # Remove unused volumes
docker network prune      # Remove unused networks

# Check disk usage
docker system df
```

### Issue 6: Build Cache Issues (Stale Cache)

**Fix:**
```bash
# Force rebuild without cache
docker build --no-cache -t myapp:latest .

# Remove specific intermediate image layers
docker builder prune
```

### Issue 7: Container Can't Reach External Network

**Fix:**
```bash
# Check iptables / firewall rules
sudo iptables -L DOCKER-USER

# Restart Docker
sudo systemctl restart docker

# Use host networking (quick test — not for production)
docker run --network=host myapp:latest
```

### Issue 8: Permission Denied on Volume Mount

```
Permission denied writing to /app/data
```

**Fix:**
```bash
# Check the UID inside the container
docker run --rm myapp:latest id

# Fix ownership on host
sudo chown -R 1000:1000 ./data  # Replace 1000 with the container UID

# Or use :z/:Z for SELinux
docker run -v $(pwd)/data:/app/data:z myapp:latest
```

### Issue 9: Multi-Stage Build Layer Not Found

```
Error: failed to solve: failed to read dockerfile: failed to parse stage name
```

**Fix:** Ensure stage names use AS keyword and match exactly:
```dockerfile
FROM eclipse-temurin:17 AS builder    # Define stage
FROM eclipse-temurin:17-jre AS runtime
COPY --from=builder /build/app.jar .  # Reference stage name exactly
```

### Issue 10: Docker Compose Services Can't Communicate

**Fix:**
```bash
# Use service names as hostnames (not localhost!)
# In docker-compose.yml:
# service: "db"
# connection string: jdbc:postgresql://db:5432/mydb  ← use service name

# Verify they're on the same network
docker network inspect myapp_default

# Check DNS resolution inside container
docker exec app-container nslookup db
```

---

## Cheat Sheet

### Docker Image Commands

| Command | Description |
|---------|-------------|
| `docker build -t name:tag .` | Build image from Dockerfile in current directory |
| `docker build --no-cache -t name:tag .` | Build without using cache |
| `docker build --target stage -t name:tag .` | Build specific multi-stage target |
| `docker images` | List local images |
| `docker pull image:tag` | Pull image from registry |
| `docker push image:tag` | Push image to registry |
| `docker tag src:tag dst:tag` | Create a new tag for an image |
| `docker rmi image:tag` | Remove a local image |
| `docker image prune -a` | Remove all unused images |
| `docker inspect image:tag` | Show image metadata as JSON |
| `docker history image:tag` | Show image layers |
| `docker save -o out.tar image:tag` | Save image to tar archive |
| `docker load -i out.tar` | Load image from tar archive |

### Docker Container Commands

| Command | Description |
|---------|-------------|
| `docker run -d -p 8080:80 image:tag` | Run container in background |
| `docker run -it image:tag /bin/bash` | Run interactively with shell |
| `docker run --rm image:tag` | Run and auto-remove when stopped |
| `docker run --name myname image:tag` | Run with a specific name |
| `docker run -e KEY=VALUE image:tag` | Set environment variable |
| `docker run -v /host:/container image:tag` | Bind mount volume |
| `docker ps` | List running containers |
| `docker ps -a` | List all containers (including stopped) |
| `docker stop container` | Gracefully stop container (SIGTERM) |
| `docker kill container` | Force stop container (SIGKILL) |
| `docker rm container` | Remove stopped container |
| `docker rm -f container` | Force remove running container |
| `docker logs -f container` | Follow container logs |
| `docker exec -it container /bin/sh` | Open shell in running container |
| `docker cp src container:/dst` | Copy files to/from container |
| `docker stats` | Live resource usage |
| `docker inspect container` | Show container details as JSON |

### Docker Compose Commands

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start all services in background |
| `docker compose up -d service` | Start specific service |
| `docker compose down` | Stop and remove containers |
| `docker compose down -v` | Also remove volumes |
| `docker compose logs -f service` | Follow logs for a service |
| `docker compose ps` | List service containers |
| `docker compose build service` | Build a service image |
| `docker compose pull` | Pull latest images |
| `docker compose exec service sh` | Shell into a running service |
| `docker compose restart service` | Restart a service |
| `docker compose scale service=3` | Scale a service to 3 replicas |

### Registry Commands

| Command | Description |
|---------|-------------|
| `docker login registry.example.com` | Authenticate to a registry |
| `docker logout registry.example.com` | Remove stored credentials |
| `docker search ubuntu` | Search Docker Hub |

---

*This guide covers Docker as used in the context of the DevOps Final Project. For the latest documentation, see [https://docs.docker.com](https://docs.docker.com).*
