# ArgoCD GitOps Complete Guide

## Table of Contents
1. [Overview & Why ArgoCD](#overview--why-argocd)
2. [GitOps Workflow Setup with ArgoCD](#gitops-workflow-setup-with-argocd)
3. [Repository Structure for GitOps](#repository-structure-for-gitops)
4. [App-of-Apps Pattern](#app-of-apps-pattern)
5. [ApplicationSet for Multi-Cluster, Multi-Env Deployment](#applicationset-for-multi-cluster-multi-env-deployment)
6. [Sync Policies](#sync-policies)
7. [Environment Promotion](#environment-promotion)
8. [Secrets Management with ArgoCD](#secrets-management-with-argocd)
9. [Integration with Jenkins](#integration-with-jenkins)
10. [Integration with JFrog](#integration-with-jfrog)
11. [Real-World Scenarios](#real-world-scenarios)
12. [Verification & Testing](#verification--testing)
13. [Troubleshooting Guide](#troubleshooting-guide)
14. [Cheat Sheet](#cheat-sheet)

---

## Overview & Why ArgoCD

### GitOps Principles

GitOps is a set of practices that uses Git as the single source of truth for both application code and infrastructure configuration. It applies the core DevOps workflow (code review, version control, CI/CD) to infrastructure and deployments.

**The four GitOps principles (OpenGitOps):**

1. **Declarative**: The desired state of the system is expressed declaratively. Kubernetes manifests, Helm charts, and Kustomize overlays define *what* should be running, not *how* to get there.

2. **Versioned and Immutable**: The desired state is stored in a way that enforces immutability and complete version history. Git provides this — every change is a commit, commits can be tagged, and the entire history is preserved.

3. **Pulled Automatically**: Software agents automatically pull the desired state from Git and apply it to the target system. This is the "pull model" vs the "push model" used by traditional CI/CD pipelines.

4. **Continuously Reconciled**: Software agents continuously observe the actual system state and reconcile it with the desired state from Git. If someone manually modifies a Kubernetes resource, the GitOps agent will revert it.

### Why ArgoCD?

ArgoCD is a **Kubernetes-native GitOps continuous delivery tool**. It runs inside your Kubernetes cluster and continuously watches Git repositories, reconciling the cluster state with the desired state in Git.

**Key capabilities:**

| Feature | Description |
|---------|-------------|
| UI Dashboard | Rich web UI showing application health, sync status, and resource topology |
| Multi-cluster | Manage multiple Kubernetes clusters from a single ArgoCD instance |
| Multi-tenancy | Projects and RBAC isolate teams and their applications |
| App-of-Apps | Manage groups of applications hierarchically |
| ApplicationSets | Template-driven deployment across clusters and environments |
| Sync Hooks | Pre/post-sync hooks for database migrations, validations |
| Rollback | One-click rollback to any previous Git commit |
| Notifications | Slack, email, webhook notifications on sync events |
| SSO | OIDC, SAML, LDAP, GitHub, GitLab authentication |

**ArgoCD vs FluxCD:**

| Aspect | ArgoCD | FluxCD |
|--------|--------|--------|
| UI | Rich dashboard (core feature) | Minimal (requires Weave GitOps UI) |
| Architecture | Central server + agents | Kubernetes controllers |
| Multi-tenancy | Projects + RBAC | Tenant configuration |
| Image automation | Via Argo Image Updater | Built-in ImagePolicy controller |
| ApplicationSets | Yes — powerful templating | Generator-based approach |
| CLI | argocd CLI | flux CLI |
| Best for | Teams that value visibility and UI | Automation-focused, controller-native |

### How ArgoCD Works

```
Developer commits to Git
        │
        ▼
Git Repository (config-repo)
   └── apps/myapp/deployment.yaml (desired state)
        │
        ▼  ArgoCD polls / webhook trigger
ArgoCD Application Controller
   │
   ├── Compares desired state (Git) vs actual state (Kubernetes)
   │
   ├── If diff detected → sync (apply manifests to cluster)
   │
   └── If self-heal enabled → auto-sync on drift
        │
        ▼
Kubernetes Cluster (actual state)
   └── Pod running myapp:1.2.3
```

---

## GitOps Workflow Setup with ArgoCD

### Install ArgoCD on Kubernetes

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD from the official manifest
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s

# Check ArgoCD pods
kubectl get pods -n argocd
```

**Expected pods:**
- `argocd-server` — API server and UI
- `argocd-application-controller` — Watches K8s cluster and reconciles
- `argocd-repo-server` — Clones Git repos and generates manifests
- `argocd-dex-server` — SSO connector (Dex)
- `argocd-redis` — State cache
- `argocd-notifications-controller` — Sends alerts

### Access the ArgoCD UI

```bash
# Get the initial admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080 in your browser
# Username: admin
# Password: (from the command above)
```

For production, expose via LoadBalancer or Ingress:

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

### Install and Configure ArgoCD CLI

```bash
# Install argocd CLI on Linux
curl -sSL -o argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# On macOS
brew install argocd

# Login
argocd login localhost:8080 \
  --username admin \
  --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d) \
  --insecure

# Change admin password
argocd account update-password

# List apps
argocd app list
```

---

## Repository Structure for GitOps

A clean GitOps setup separates application code from deployment configuration into two repositories:

### App Repository (Source Code Repo)

```
app-repo/                        ← Application source code
├── src/                         ← Application source files
├── Dockerfile                   ← Container build definition
├── Jenkinsfile                  ← CI pipeline: build, test, scan, push image
└── pom.xml / package.json       ← Build tool config
```

The CI pipeline (Jenkins) runs on the app-repo. It builds, tests, and pushes the Docker image, then updates the image tag in the config-repo.

### Config Repository (GitOps Repo)

```
config-repo/                     ← GitOps desired state (what ArgoCD watches)
├── apps/                        ← ArgoCD Application manifests
│   ├── app-of-apps.yaml         ← Root app that manages all other apps
│   └── myapp/
│       ├── dev.yaml             ← ArgoCD Application for dev environment
│       ├── staging.yaml         ← ArgoCD Application for staging
│       └── prod.yaml            ← ArgoCD Application for prod
├── environments/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patch-image.yaml    ← Image tag for dev
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── patch-image.yaml
│   └── prod/
│       ├── kustomization.yaml
│       └── patch-image.yaml
└── base/
    ├── kustomization.yaml
    ├── deployment.yaml          ← Base Deployment manifest
    ├── service.yaml             ← Base Service manifest
    └── configmap.yaml           ← Base ConfigMap
```

**base/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      imagePullSecrets:
        - name: jfrog-registry-secret
      containers:
      - name: myapp
        image: your-org.jfrog.io/docker-local/myapp:PLACEHOLDER
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
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

**environments/prod/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Override namespace for this environment
namespace: production

# Scale replicas for production
replicas:
  - name: myapp
    count: 3

# Override image tag (updated by CI pipeline)
images:
  - name: your-org.jfrog.io/docker-local/myapp
    newTag: "1.2.3"

# Add environment-specific labels
commonLabels:
  environment: production

# Apply environment-specific patches
patches:
  - path: patch-resources.yaml  # Production resource limits
```

---

## App-of-Apps Pattern

The App-of-Apps pattern uses a "root" ArgoCD Application that manages other ArgoCD Applications. This enables hierarchical management of multiple applications.

```
App-of-Apps (root)
├── Application: frontend
├── Application: user-service
├── Application: order-service
├── Application: product-service
└── Application: notification-service
```

**apps/app-of-apps.yaml (root Application):**

```yaml
# This Application watches the apps/ directory in the config-repo
# When a new Application YAML is added, ArgoCD automatically manages it
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  # Finalizer ensures ArgoCD deletes child apps when this app is deleted
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/config-repo.git
    targetRevision: HEAD
    # Path to the directory containing child Application manifests
    path: apps

  destination:
    server: https://kubernetes.default.svc  # Local cluster
    namespace: argocd  # ArgoCD Applications live in argocd namespace

  syncPolicy:
    automated:
      prune: true      # Remove child apps not in Git
      selfHeal: true   # Re-sync if manually modified
    syncOptions:
      - CreateNamespace=true
```

**apps/myapp/prod.yaml (child Application):**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app: myapp
    environment: prod
spec:
  project: production-project  # ArgoCD Project for RBAC

  source:
    repoURL: https://github.com/your-org/config-repo.git
    targetRevision: HEAD
    path: environments/prod  # Kustomize overlay for prod

  destination:
    server: https://kubernetes.default.svc
    namespace: production

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

```bash
# Deploy the App-of-Apps
kubectl apply -f apps/app-of-apps.yaml -n argocd

# ArgoCD will now discover and manage all apps in the apps/ directory
argocd app list

# Sync the root app (which will trigger sync of all child apps)
argocd app sync app-of-apps --cascade
```

---

## ApplicationSet for Multi-Cluster, Multi-Env Deployment

ApplicationSet controller generates multiple ArgoCD Applications from a template.

### List Generator (Multi-Environment)

```yaml
# applicationset/myapp-environments.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-environments
  namespace: argocd
spec:
  generators:
  # List generator: create one Application per environment entry
  - list:
      elements:
      - environment: dev
        namespace: development
        cluster: https://kubernetes.default.svc
        replicaCount: "1"
        imageTag: "latest"
      - environment: staging
        namespace: staging
        cluster: https://staging-cluster.example.com
        replicaCount: "2"
        imageTag: "1.2.3"
      - environment: prod
        namespace: production
        cluster: https://prod-cluster.example.com
        replicaCount: "5"
        imageTag: "1.2.2"  # Prod may lag behind staging for stability

  template:
    metadata:
      name: myapp-{{environment}}  # Generates: myapp-dev, myapp-staging, myapp-prod
      labels:
        app: myapp
        environment: "{{environment}}"
    spec:
      project: "{{environment}}-project"
      source:
        repoURL: https://github.com/your-org/config-repo.git
        targetRevision: HEAD
        path: environments/{{environment}}
      destination:
        server: "{{cluster}}"
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Git Generator (Directory-Based)

```yaml
# Automatically create an Application for every directory in environments/
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-git-generator
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/your-org/config-repo.git
      revision: HEAD
      directories:
        - path: environments/*  # Matches: environments/dev, environments/staging, etc.

  template:
    metadata:
      name: myapp-{{path.basename}}  # Uses directory name as app name
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/config-repo.git
        targetRevision: HEAD
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Cluster Generator (Multi-Cluster)

```yaml
# Deploy to all registered clusters with a specific label
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-all-clusters
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          deploy-myapp: "true"  # Only clusters with this label

  template:
    metadata:
      name: myapp-{{name}}  # {{name}} = cluster name in ArgoCD
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/config-repo.git
        targetRevision: HEAD
        path: environments/{{metadata.labels.environment}}
      destination:
        server: "{{server}}"  # {{server}} = cluster API URL
        namespace: myapp
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

---

## Sync Policies

### Manual Sync (Default)

```yaml
# No syncPolicy.automated — requires manual sync trigger
spec:
  syncPolicy: {}
```

```bash
# Manually trigger sync
argocd app sync myapp-prod

# Sync with specific options
argocd app sync myapp-prod \
  --prune \
  --force \
  --timeout 120
```

### Automated Sync with Self-Heal

```yaml
spec:
  syncPolicy:
    automated:
      # Automatically sync when Git changes are detected
      # Without this, changes in Git require a manual sync
      prune: true      # Delete resources removed from Git
      selfHeal: true   # Re-sync if cluster state drifts from Git

    syncOptions:
      # Only apply resources that are out of sync (faster)
      - ApplyOutOfSyncOnly=true

      # Use server-side apply (handles large resources, field managers)
      - ServerSideApply=true

      # Automatically create the destination namespace if it doesn't exist
      - CreateNamespace=true

      # Respect PodDisruptionBudgets during sync
      - RespectIgnoreDifferences=true

    # Retry configuration for transient failures
    retry:
      limit: 5
      backoff:
        duration: 5s      # Initial wait between retries
        factor: 2          # Exponential backoff multiplier
        maxDuration: 3m    # Maximum wait between retries
```

### Sync Hooks

Hooks allow running actions at specific points in the sync lifecycle:

```yaml
# Run a database migration Job BEFORE syncing the app
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    # PreSync: runs before any resources are applied
    argocd.argoproj.io/hook: PreSync
    # Delete the job when it succeeds (keeps cluster clean)
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: migration
        image: your-org.jfrog.io/docker-local/myapp:1.2.3
        command: ["./run-migrations.sh"]
      restartPolicy: Never
```

```yaml
# Run a smoke test AFTER sync
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: test
        image: curlimages/curl:latest
        command:
          - /bin/sh
          - -c
          - |
            curl -f http://myapp:8080/actuator/health || exit 1
      restartPolicy: Never
```

---

## Environment Promotion

### Branch-Based Strategy

```
Git Branches:
  main     → automatically deployed to dev
  staging  → after QA approval, manually promoted to staging
  prod     → after staging validation, tagged for prod deployment
```

```yaml
# ArgoCD Application for dev (tracks main branch)
spec:
  source:
    targetRevision: main  # HEAD of main branch

# ArgoCD Application for staging
spec:
  source:
    targetRevision: staging  # HEAD of staging branch

# ArgoCD Application for prod
spec:
  source:
    targetRevision: v1.2.3   # Specific tag for prod (immutable)
```

### Image Tag Promotion Strategy

The most common GitOps promotion pattern: update the image tag in the config-repo to promote between environments.

```bash
#!/bin/bash
# promote.sh — Promote image tag from dev to staging

SOURCE_ENV="dev"
TARGET_ENV="staging"
APP="myapp"

# Get the current image tag from dev
CURRENT_TAG=$(cat environments/${SOURCE_ENV}/kustomization.yaml | \
  grep -A1 'name: your-org.jfrog.io/docker-local/myapp' | \
  grep newTag | awk '{print $2}' | tr -d '"')

echo "Promoting ${APP}:${CURRENT_TAG} from ${SOURCE_ENV} to ${TARGET_ENV}"

# Update the target environment's kustomization
cd environments/${TARGET_ENV}
kustomize edit set image \
  "your-org.jfrog.io/docker-local/${APP}=${CURRENT_TAG}"

# Commit and push
git add kustomization.yaml
git commit -m "promote: ${APP}:${CURRENT_TAG} from ${SOURCE_ENV} to ${TARGET_ENV}

Promoted by: ${USER:-ci}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push

echo "Promotion complete. ArgoCD will deploy ${TARGET_ENV} automatically."
```

---

## Secrets Management with ArgoCD

### Option 1: Sealed Secrets (Bitnami)

Sealed Secrets encrypts Kubernetes secrets so they can be safely committed to Git.

```bash
# Install the Sealed Secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --version 2.13.0

# Install kubeseal CLI
curl -sSL \
  https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/kubeseal-linux-amd64 \
  -o kubeseal
chmod +x kubeseal && sudo mv kubeseal /usr/local/bin/

# Create a regular Kubernetes secret (NOT committed to Git)
kubectl create secret generic jfrog-registry-secret \
  --namespace production \
  --docker-server=your-org.jfrog.io \
  --docker-username=your-user \
  --docker-password=your-token \
  --dry-run=client \
  -o yaml > secret.yaml

# Seal it — produces a SealedSecret that IS safe to commit
kubeseal \
  --namespace production \
  --format yaml \
  < secret.yaml \
  > sealed-secret.yaml

# The sealed-secret.yaml can be committed to Git
# ArgoCD deploys it; the controller decrypts it into a real Secret
git add sealed-secret.yaml
git commit -m "feat: add jfrog registry sealed secret for production"
git push

rm secret.yaml  # Never commit the plain secret!
```

### Option 2: External Secrets Operator (ESO)

ESO reads secrets from external stores (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault) and creates Kubernetes Secrets.

```yaml
# Install ESO via Helm (or ArgoCD Application)
# helm install external-secrets external-secrets/external-secrets -n external-secrets

# SecretStore: tells ESO how to connect to Azure Key Vault
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault-store
  namespace: production
spec:
  provider:
    azurekv:
      tenantId: "your-tenant-id"
      vaultUrl: "https://prod-platform-kv.vault.azure.net"
      authType: ManagedIdentity  # Uses AKS pod identity

---
# ExternalSecret: defines which secrets to sync from Key Vault
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: jfrog-registry-credentials
  namespace: production
spec:
  refreshInterval: 1h  # Re-sync from Key Vault every hour

  secretStoreRef:
    kind: SecretStore
    name: azure-keyvault-store

  target:
    name: jfrog-registry-secret  # Name of the created Kubernetes Secret
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "your-org.jfrog.io": {
                "username": "{{ .jfrog-username }}",
                "password": "{{ .jfrog-token }}"
              }
            }
          }

  data:
  - secretKey: jfrog-username
    remoteRef:
      key: jfrog-username  # Key Vault secret name
  - secretKey: jfrog-token
    remoteRef:
      key: jfrog-api-token
```

---

## Integration with Jenkins

**Full Jenkins → ArgoCD GitOps pipeline:**

Jenkins builds the image and updates the config-repo with the new image tag. ArgoCD detects the Git change and auto-deploys.

```groovy
// Jenkinsfile — CI/CD pipeline with ArgoCD GitOps

pipeline {
    agent any

    environment {
        JFROG_REGISTRY  = 'your-org.jfrog.io'
        JFROG_REPO      = 'docker-local'
        APP_NAME        = 'myapp'
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE      = "${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG}"
        GITOPS_REPO     = 'https://github.com/your-org/config-repo.git'
        GITOPS_BRANCH   = 'main'
        TARGET_ENV      = 'dev'
        JFROG_CREDS     = credentials('jfrog-credentials')
        GIT_CREDS       = credentials('github-token')
    }

    stages {
        stage('Build & Push Image') {
            steps {
                sh """
                    docker build -t ${FULL_IMAGE} .
                    echo \${JFROG_CREDS_PSW} | \
                      docker login ${JFROG_REGISTRY} -u \${JFROG_CREDS_USR} --password-stdin
                    docker push ${FULL_IMAGE}
                    docker logout ${JFROG_REGISTRY}
                """
            }
        }

        stage('Update GitOps Repo') {
            steps {
                sh """
                    # Clone the config (GitOps) repo
                    git clone https://\${GIT_CREDS_USR}:\${GIT_CREDS_PSW}@github.com/your-org/config-repo.git
                    cd config-repo

                    git config user.email "jenkins@ci.local"
                    git config user.name "Jenkins CI"

                    # Update the image tag in the dev environment
                    cd environments/${TARGET_ENV}
                    kustomize edit set image \
                      "${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}=${IMAGE_TAG}"

                    git add kustomization.yaml
                    git commit -m "ci: update ${APP_NAME} to ${IMAGE_TAG} in ${TARGET_ENV}

App: ${APP_NAME}
Image: ${FULL_IMAGE}
Jenkins Build: ${env.BUILD_URL}
Git Commit: ${GIT_COMMIT}"

                    git push origin ${GITOPS_BRANCH}
                    cd ../..
                    rm -rf config-repo
                """
            }
        }

        stage('Wait for ArgoCD Sync') {
            steps {
                // Optionally wait for ArgoCD to confirm deployment
                sh """
                    argocd app wait ${APP_NAME}-${TARGET_ENV} \
                      --timeout 300 \
                      --health
                    argocd app get ${APP_NAME}-${TARGET_ENV}
                """
            }
        }
    }
}
```

---

## Integration with JFrog

ArgoCD itself doesn't pull images — Kubernetes does. The integration point is updating the image tag in the config-repo (which Jenkins does after pushing to JFrog).

**Configure ArgoCD to use images from JFrog:**

1. **Create the imagePullSecret** in the deployment namespace:
```bash
kubectl create secret docker-registry jfrog-registry-secret \
  --namespace production \
  --docker-server=your-org.jfrog.io \
  --docker-username=your-service-account \
  --docker-password=your-jfrog-api-key \
  -n production
```

2. **Reference it in the base Deployment** (managed by ArgoCD):
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: jfrog-registry-secret
```

3. **Use JFrog image tag in kustomization.yaml** (updated by Jenkins CI):
```yaml
images:
  - name: your-org.jfrog.io/docker-local/myapp
    newTag: "123-abc1234"  # Jenkins updates this value
```

**ArgoCD Image Updater** (optional — automatically watches JFrog for new tags):

```yaml
# Install Argo CD Image Updater
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Annotate an Application to auto-update image tags from JFrog
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-dev
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: |
      myapp=your-org.jfrog.io/docker-local/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
    argocd-image-updater.argoproj.io/myapp.semver-constraint: "~1.2"
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
```

---

## Real-World Scenarios

### Scenario 1: Deploy App to 3 Environments from Single GitOps Repo

```bash
# Initial setup — create environments directory structure
mkdir -p config-repo/environments/{dev,staging,prod}
mkdir -p config-repo/base

# base/kustomization.yaml
cat > config-repo/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF

# environments/dev/kustomization.yaml
cat > config-repo/environments/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: development
images:
  - name: your-org.jfrog.io/docker-local/myapp
    newTag: "latest"
replicas:
  - name: myapp
    count: 1
EOF

# Push to Git
cd config-repo && git add . && git commit -m "feat: initial gitops structure" && git push

# Create ArgoCD ApplicationSet for all environments
kubectl apply -f - << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        namespace: development
      - env: staging
        namespace: staging
      - env: prod
        namespace: production
  template:
    metadata:
      name: myapp-{{env}}
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/config-repo.git
        targetRevision: HEAD
        path: environments/{{env}}
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF

# Verify
argocd app list
kubectl get pods -n development
kubectl get pods -n staging
kubectl get pods -n production
```

### Scenario 2: App-of-Apps for Microservices

```bash
# Config repo structure for microservices
config-repo/
├── apps/
│   ├── root-app.yaml          ← App-of-Apps (deploy this once)
│   ├── frontend/
│   │   ├── dev.yaml
│   │   └── prod.yaml
│   ├── user-service/
│   │   ├── dev.yaml
│   │   └── prod.yaml
│   └── order-service/
│       ├── dev.yaml
│       └── prod.yaml

# Deploy only the root app — it manages everything else
kubectl apply -f config-repo/apps/root-app.yaml -n argocd

# ArgoCD discovers and syncs all child apps automatically
argocd app list
# NAME                    CLUSTER     NAMESPACE  STATUS  HEALTH
# root-app                in-cluster  argocd     Synced  Healthy
# frontend-dev            in-cluster  dev        Synced  Healthy
# frontend-prod           in-cluster  prod       Synced  Healthy
# user-service-dev        in-cluster  dev        Synced  Healthy
# order-service-dev       in-cluster  dev        Synced  Healthy
```

### Scenario 3: Automated Rollback on Failed Sync

ArgoCD can automatically rollback to the last successful deployment:

```bash
# Enable auto-rollback via ArgoCD sync hooks
# Add a PostSync hook that tests the app and fails if unhealthy

# If the PostSync hook fails, ArgoCD marks the sync as Failed
# You can then trigger rollback:
argocd app rollback myapp-prod

# Or set up automated rollback with a notification + webhook:
# 1. Configure Argo CD Notifications to trigger on sync failure
# 2. Webhook calls a rollback script

# argocd-notifications-cm.yaml
cat << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [rollback-on-failure]
  template.rollback-on-failure: |
    webhook:
      rollback-webhook:
        method: POST
        body: |
          {
            "app": "{{.app.metadata.name}}",
            "action": "rollback"
          }
  service.webhook.rollback-webhook: |
    url: https://your-automation-server/rollback
    headers:
    - name: Authorization
      value: Bearer $WEBHOOK_TOKEN
EOF

# Manual rollback to a specific revision
argocd app history myapp-prod    # List revision history
argocd app rollback myapp-prod 5  # Rollback to revision 5 (a specific Git commit)

# Verify rollback
argocd app get myapp-prod
kubectl get pods -n production
```

---

## Verification & Testing

```bash
# Check application sync status
argocd app get myapp-prod

# View all applications
argocd app list

# Check application health
argocd app get myapp-prod --show-operation

# Compare Git vs cluster state (shows diff without syncing)
argocd app diff myapp-prod

# View sync history
argocd app history myapp-prod

# Force a refresh (re-check Git)
argocd app get myapp-prod --refresh

# Manually trigger sync
argocd app sync myapp-prod

# Get ArgoCD server info
argocd version

# Check registered clusters
argocd cluster list

# Check registered repositories
argocd repo list

# Validate application manifests without applying
kubectl apply --dry-run=client -f environments/prod/kustomization.yaml
kustomize build environments/prod | kubectl apply --dry-run=client -f -
```

---

## Troubleshooting Guide

### Issue 1: Application Stuck in "OutOfSync"

**Cause:** Resources differ between Git and cluster, but can't be auto-synced.

**Fix:**
```bash
argocd app diff myapp-prod       # See what's different
argocd app sync myapp-prod --force  # Force sync
# Or check for ignored differences in the app spec
```

### Issue 2: ComparisonError — Unable to Parse Kustomize Output

**Fix:**
```bash
# Test kustomize build locally
kustomize build environments/prod

# Check for YAML syntax errors
yamllint environments/prod/kustomization.yaml
```

### Issue 3: Repository Not Accessible

```
rpc error: code = Unknown desc = authentication required
```

**Fix:**
```bash
# Add/update repository credentials in ArgoCD
argocd repo add https://github.com/your-org/config-repo.git \
  --username your-user \
  --password your-token

# Or via SSH key
argocd repo add git@github.com:your-org/config-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

### Issue 4: Sync Fails Due to Missing Namespace

**Fix:** Add `CreateNamespace=true` to syncOptions:
```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

### Issue 5: Prune Disabled — Resources Not Deleted

**Fix:** Either enable `prune: true` in automated sync policy, or manually prune:
```bash
argocd app sync myapp-prod --prune
```

### Issue 6: SelfHeal Reverts Manual Changes Unexpectedly

**Cause:** `selfHeal: true` is working as intended — it reverts manual changes.

**Fix:** If you need to make a temporary change, temporarily disable self-heal:
```bash
argocd app set myapp-prod --self-heal=false
# Make your change
# Re-enable:
argocd app set myapp-prod --self-heal=true
```

### Issue 7: ApplicationSet Not Creating Applications

**Fix:**
```bash
kubectl get applicationset -n argocd
kubectl describe applicationset myapp-environments -n argocd
# Check for generator errors in the status
```

---

## Cheat Sheet

| Command | Description |
|---------|-------------|
| `argocd login server:port` | Login to ArgoCD server |
| `argocd app list` | List all applications |
| `argocd app get app-name` | Get application details |
| `argocd app sync app-name` | Manually trigger sync |
| `argocd app sync app-name --prune` | Sync and prune deleted resources |
| `argocd app sync app-name --force` | Force sync (replace resources) |
| `argocd app diff app-name` | Show diff between Git and cluster |
| `argocd app history app-name` | Show sync history |
| `argocd app rollback app-name N` | Rollback to revision N |
| `argocd app delete app-name` | Delete application (keeps K8s resources) |
| `argocd app delete app-name --cascade` | Delete app and K8s resources |
| `argocd app set app-name --sync-policy automated` | Enable auto-sync |
| `argocd app set app-name --self-heal` | Enable self-healing |
| `argocd app wait app-name --health` | Wait until app is healthy |
| `argocd cluster list` | List registered clusters |
| `argocd cluster add context-name` | Register a new cluster |
| `argocd repo list` | List registered repositories |
| `argocd repo add URL --username U --password P` | Add a repository |
| `argocd proj list` | List projects |
| `argocd proj create project-name` | Create a project |
| `argocd account list` | List accounts |
| `argocd account update-password` | Change your password |
| `argocd version` | Show ArgoCD CLI and server version |

---

*This guide covers ArgoCD as used in the context of the DevOps Final Project. For the latest documentation, see [https://argo-cd.readthedocs.io](https://argo-cd.readthedocs.io).*
