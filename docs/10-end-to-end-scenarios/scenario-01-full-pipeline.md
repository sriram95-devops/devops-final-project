# Scenario 01: Full CI/CD Pipeline
# Code Commit → Jenkins → SonarQube → Docker → JFrog → ArgoCD → Kubernetes → Prometheus → Grafana → Slack

## Overview

This scenario walks through the **complete end-to-end DevOps pipeline** from a developer pushing code to a fully monitored production deployment.

**Estimated Time:** 2–3 hours to set up, 5 minutes per pipeline run after setup

```mermaid
flowchart LR
    A[Developer\nGit Push] --> B[Jenkins\nCI Pipeline]
    B --> C[SonarQube\nQuality Gate]
    C --> D[Docker Build\nMulti-stage]
    D --> E[JFrog\nArtifactory]
    E --> F[ArgoCD\nGitOps Sync]
    F --> G[Kubernetes\nDeploy]
    G --> H[Prometheus\nScrape Metrics]
    H --> I[Grafana\nDashboard]
    H --> J[Alertmanager\nSlack Notify]
```

---

## Prerequisites

```bash
# Verify all tools are running
kubectl get pods -A | grep -E "jenkins|sonarqube|argocd|prometheus|grafana"

# Verify JFrog is accessible
curl -s -u admin:password https://mycompany.jfrog.io/artifactory/api/system/ping

# Verify Slack webhook works
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Pipeline scenario test"}' \
  https://hooks.slack.com/services/<TEAM_ID>/<CHANNEL_ID>/<TOKEN>
```

---

## Step 1: Application Repository Structure

```
myapp/
├── src/
│   └── main/
│       └── java/com/myapp/
│           └── Application.java
├── Dockerfile
├── Jenkinsfile
├── sonar-project.properties
└── pom.xml
```

### Dockerfile (multi-stage)

```dockerfile
# Stage 1: Build
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B        # Cache dependencies layer
COPY src ./src
RUN mvn clean package -DskipTests -B    # Build JAR

# Stage 2: Runtime (minimal image)
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
# Copy only the JAR from build stage
COPY --from=builder /app/target/*.jar app.jar
# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### sonar-project.properties

```properties
# SonarQube project configuration
sonar.projectKey=myapp
sonar.projectName=My Application
sonar.projectVersion=1.0
sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target/classes
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
```

---

## Step 2: GitOps Configuration Repository

**Separate repo for Kubernetes manifests (GitOps best practice):**

```
myapp-config/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml
│   └── prod/
│       ├── kustomization.yaml
│       └── patch-replicas.yaml
└── helm/
    └── values-prod.yaml
```

### base/deployment.yaml

```yaml
# base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 2                            # Overridden per environment
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        prometheus.io/scrape: "true"     # Enable Prometheus scraping
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      imagePullSecrets:
      - name: jfrog-pull-secret          # Secret to pull from JFrog
      containers:
      - name: myapp
        image: mycompany.jfrog.io/docker-local/myapp:latest  # Updated by Jenkins
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 5
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "production"
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

### base/kustomization.yaml

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
```

### overlays/prod/kustomization.yaml

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod                          # Deploy to prod namespace
bases:
- ../../base
patchesStrategicMerge:
- patch-replicas.yaml
images:
- name: mycompany.jfrog.io/docker-local/myapp
  newTag: "REPLACE_IMAGE_TAG"            # Jenkins updates this value
```

### overlays/prod/patch-replicas.yaml

```yaml
# overlays/prod/patch-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3                            # 3 replicas in prod
```

---

## Step 3: ArgoCD Application

```yaml
# argocd-app-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-prod
  namespace: argocd
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: "deployments"
    notifications.argoproj.io/subscribe.on-sync-failed.slack: "alerts-critical"
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/myapp-config.git
    targetRevision: main
    path: overlays/prod                  # Use production overlay
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: true                        # Remove resources not in Git
      selfHeal: true                     # Revert manual K8s changes
    syncOptions:
    - CreateNamespace=true              # Create namespace if missing
```

```bash
kubectl apply -f argocd-app-prod.yaml

# Verify ArgoCD app is synced
argocd app get myapp-prod
```

---

## Step 4: Complete Jenkinsfile

```groovy
// Jenkinsfile — Complete CI/CD Pipeline
// Code → SonarQube → Docker Build → JFrog → ArgoCD → K8s → Slack
pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: maven
    image: maven:3.9-eclipse-temurin-17
    command: [sleep]
    args: [infinity]
  - name: docker
    image: docker:24-dind
    securityContext:
      privileged: true
  - name: tools
    image: argoproj/argocd:v2.9.0
    command: [sleep]
    args: [infinity]
'''
        }
    }

    environment {
        APP_NAME          = 'myapp'
        JFROG_REGISTRY    = 'mycompany.jfrog.io'
        JFROG_REPO        = 'docker-local'
        IMAGE_TAG         = "${BUILD_NUMBER}"
        FULL_IMAGE        = "${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG}"
        CONFIG_REPO       = 'https://github.com/myorg/myapp-config.git'
        ARGOCD_SERVER     = 'argocd.mycompany.com'
        SLACK_CHANNEL     = '#deployments'
        SONAR_PROJECT_KEY = 'myapp'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                slackSend channel: env.SLACK_CHANNEL, color: '#439FE0',
                    message: "🔄 *Pipeline Started* | `${env.JOB_NAME}` #${env.BUILD_NUMBER} | Branch: `${env.GIT_BRANCH}`"
            }
        }

        stage('Unit Tests') {
            steps {
                container('maven') {
                    sh 'mvn test -B'
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                container('maven') {
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            mvn sonar:sonar \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.host.url=${SONAR_HOST_URL} \
                              -Dsonar.login=${SONAR_AUTH_TOKEN}
                        """
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                success {
                    slackSend channel: env.SLACK_CHANNEL, color: 'good',
                        message: "✅ *SonarQube Quality Gate Passed* | No critical issues found"
                }
                failure {
                    slackSend channel: env.SLACK_CHANNEL, color: 'danger',
                        message: "❌ *SonarQube Quality Gate FAILED* | Check: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                container('docker') {
                    sh """
                        docker build \
                          -t ${FULL_IMAGE} \
                          -t ${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:latest \
                          --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                          .
                    """
                }
            }
        }

        stage('Security Scan') {
            steps {
                container('docker') {
                    sh """
                        # Scan image with Trivy before pushing
                        docker run --rm \
                          -v /var/run/docker.sock:/var/run/docker.sock \
                          aquasec/trivy:latest image \
                          --exit-code 1 \
                          --severity CRITICAL \
                          ${FULL_IMAGE} || true
                    """
                }
            }
        }

        stage('Push to JFrog') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'jfrog-credentials',
                        usernameVariable: 'JFROG_USER',
                        passwordVariable: 'JFROG_PASS'
                    )]) {
                        sh """
                            docker login ${JFROG_REGISTRY} -u ${JFROG_USER} -p ${JFROG_PASS}
                            docker push ${FULL_IMAGE}
                            docker push ${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:latest
                        """
                    }
                }
            }
            post {
                success {
                    slackSend channel: env.SLACK_CHANNEL, color: 'good',
                        message: "📦 *Image Pushed to JFrog* | `${FULL_IMAGE}`"
                }
            }
        }

        stage('Update GitOps Config') {
            steps {
                container('tools') {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-credentials',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_PASS'
                    )]) {
                        sh """
                            # Clone config repo
                            git clone https://${GIT_USER}:${GIT_PASS}@github.com/myorg/myapp-config.git /tmp/config
                            cd /tmp/config

                            # Update image tag in prod overlay
                            sed -i 's/newTag: .*/newTag: "${IMAGE_TAG}"/' overlays/prod/kustomization.yaml

                            # Commit and push
                            git config user.email "jenkins@mycompany.com"
                            git config user.name "Jenkins"
                            git add overlays/prod/kustomization.yaml
                            git commit -m "ci: update myapp to ${IMAGE_TAG} [skip ci]"
                            git push origin main
                        """
                    }
                }
            }
        }

        stage('ArgoCD Sync') {
            steps {
                container('tools') {
                    withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_TOKEN')]) {
                        sh """
                            # Login to ArgoCD
                            argocd login ${ARGOCD_SERVER} \
                              --auth-token ${ARGOCD_TOKEN} \
                              --insecure

                            # Trigger sync
                            argocd app sync myapp-prod \
                              --server ${ARGOCD_SERVER} \
                              --auth-token ${ARGOCD_TOKEN} \
                              --insecure

                            # Wait for healthy state
                            argocd app wait myapp-prod \
                              --health \
                              --timeout 300 \
                              --server ${ARGOCD_SERVER} \
                              --auth-token ${ARGOCD_TOKEN} \
                              --insecure
                        """
                    }
                }
            }
            post {
                success {
                    slackSend channel: env.SLACK_CHANNEL, color: 'good',
                        message: "🚀 *Deployment Successful!* | `${APP_NAME}` version `${IMAGE_TAG}` is live in Production"
                }
                failure {
                    slackSend channel: env.SLACK_CHANNEL, color: 'danger',
                        message: "💥 *Deployment FAILED!* | `${APP_NAME}` version `${IMAGE_TAG}` | <${env.BUILD_URL}|View Logs>"
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    # Verify pods are running
                    kubectl get pods -n prod -l app=${APP_NAME}

                    # Check rollout status
                    kubectl rollout status deployment/${APP_NAME} -n prod --timeout=120s

                    # Smoke test
                    POD=\$(kubectl get pod -n prod -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
                    kubectl exec \$POD -n prod -- wget -qO- http://localhost:8080/actuator/health
                """
            }
        }
    }

    post {
        success {
            slackSend channel: env.SLACK_CHANNEL, color: 'good',
                message: "✅ *Pipeline COMPLETE* | `${env.JOB_NAME}` #${env.BUILD_NUMBER} | Duration: ${currentBuild.durationString} | <${env.BUILD_URL}|View Build>"
        }
        failure {
            sh """
                # Auto-rollback on pipeline failure
                kubectl rollout undo deployment/${APP_NAME} -n prod || true
            """
            slackSend channel: env.SLACK_CHANNEL, color: 'danger',
                message: "❌ *Pipeline FAILED + Auto-Rollback* | `${env.JOB_NAME}` #${env.BUILD_NUMBER} | <${env.BUILD_URL}console|View Logs>"
        }
    }
}
```

---

## Step 5: Prometheus Monitoring

```yaml
# servicemonitor-myapp.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
    - prod
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 30s
```

```bash
kubectl apply -f servicemonitor-myapp.yaml

# Verify metrics are being scraped
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring &
# Open http://localhost:9090 → Status → Targets → search "myapp"
```

---

## Step 6: Grafana Dashboard

```bash
# Import Spring Boot dashboard
# Grafana → + → Import → ID: 12900 → Select Prometheus → Import

# Key metrics to watch:
# - HTTP request rate: rate(http_server_requests_seconds_count[5m])
# - Error rate: rate(http_server_requests_seconds_count{status=~"5.."}[5m])
# - JVM heap: jvm_memory_used_bytes{area="heap"}
# - P99 latency: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))
```

---

## Verification at Each Step

```bash
# Step 1: Jenkins build triggered
open http://jenkins.mycompany.com/job/myapp/lastBuild/

# Step 2: SonarQube quality gate
open http://sonarqube.mycompany.com/dashboard?id=myapp

# Step 3: Image in JFrog
curl -u admin:pass https://mycompany.jfrog.io/artifactory/api/storage/docker-local/myapp/${IMAGE_TAG}/

# Step 4: ArgoCD sync status
argocd app get myapp-prod
# Expected: Status: Synced, Health: Healthy

# Step 5: Kubernetes deployment
kubectl get pods -n prod -l app=myapp
kubectl rollout status deployment/myapp -n prod

# Step 6: Prometheus metrics
curl http://myapp.prod.svc.cluster.local/actuator/prometheus | head -20

# Step 7: Grafana dashboard
open http://grafana.mycompany.com/d/myapp-dashboard

# Step 8: Slack notifications
# Check #deployments channel in Slack — should show all pipeline stages
```

---

## Rollback Procedure

```bash
# Option 1: ArgoCD rollback (GitOps rollback)
argocd app history myapp-prod
argocd app rollback myapp-prod <REVISION>

# Option 2: Kubernetes rollback (immediate)
kubectl rollout undo deployment/myapp -n prod
kubectl rollout status deployment/myapp -n prod

# Option 3: Jenkins re-run previous build
# Jenkins → myapp job → Previous build → Rebuild
```

---

## Troubleshooting

| Stage | Issue | Fix |
|-------|-------|-----|
| Jenkins | Build not triggered | Check GitHub webhook → Jenkins URL → `/github-webhook/` |
| SonarQube | Quality gate timeout | Increase timeout in `waitForQualityGate`; check SonarQube load |
| Docker build | Layer cache miss | Add `.dockerignore`; check COPY order for caching |
| JFrog push | 401 Unauthorized | Re-create `jfrog-credentials` secret in Jenkins |
| ArgoCD sync | OutOfSync forever | Check if Git config repo URL is correct in ArgoCD app |
| K8s deploy | ImagePullBackOff | Verify `jfrog-pull-secret` is in `prod` namespace |
| Prometheus | Metrics not scraped | Verify `app` label matches ServiceMonitor selector |
| Slack | No notifications | Check Jenkins Slack plugin config; verify bot is in channel |
