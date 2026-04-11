# ArgoCD GitOps Patterns Guide

> **This guide focuses on GitOps-specific patterns and workflows.**
> For installation, cluster setup, RBAC, configuration deep-dive, and a full CLI reference, see [01-cicd/argocd-complete-guide.md](../01-cicd/argocd-complete-guide.md).

---

## Table of Contents

1. [GitOps Principles](#gitops-principles)
2. [ArgoCD vs FluxCD](#argocd-vs-fluxcd)
3. [Repository Structure for GitOps](#repository-structure-for-gitops)
4. [App-of-Apps Pattern](#app-of-apps-pattern)
5. [ApplicationSet - Multi-Cluster & Multi-Env](#applicationset--multi-cluster--multi-env)
6. [Sync Policies & Hooks](#sync-policies--hooks)
7. [Environment Promotion](#environment-promotion)
8. [Secrets Management](#secrets-management)
9. [Real-World Scenarios](#real-world-scenarios)
10. [Troubleshooting (GitOps-Specific)](#troubleshooting-gitops-specific)

---

## GitOps Principles

GitOps uses Git as the single source of truth for both application code and infrastructure. The four OpenGitOps principles:

| # | Principle | What it means |
|---|-----------|---------------|
| 1 | **Declarative** | Desired state is expressed in files (manifests, Helm, Kustomize) � not imperative scripts |
| 2 | **Versioned & Immutable** | Git provides full history; every change is a commit; earlier states can be restored |
| 3 | **Pulled Automatically** | An agent (ArgoCD) pulls desired state from Git and applies it � no pipeline writes to the cluster |
| 4 | **Continuously Reconciled** | The agent constantly compares live state to Git and corrects drift |

### Push-Based CI/CD vs Pull-Based GitOps

```
Push model (traditional CI/CD):
  Git push ? Jenkins ? kubectl apply ? Cluster
  Problem: pipeline has cluster write access; drift is not corrected automatically

Pull model (GitOps):
  Git push ? ArgoCD detects change ? ArgoCD applies to cluster
  Benefit: cluster credentials never leave the cluster; drift is auto-corrected
```

---

## ArgoCD vs FluxCD

| Aspect | ArgoCD | FluxCD |
|--------|--------|--------|
| UI | Rich dashboard (core feature) | Minimal (requires Weave GitOps) |
| Architecture | Central API server + controllers | Pure Kubernetes controllers |
| Multi-tenancy | Projects + RBAC | Tenant configuration |
| Image automation | Via Argo Image Updater | Built-in ImagePolicy controller |
| ApplicationSets | Yes � powerful templating | Generator-based |
| CLI | `argocd` | `flux` |
| Best for | Teams that value visibility and UI | Automation-first, controller-native |

---

## Repository Structure for GitOps

The cleanest GitOps setup uses **two separate repositories**:

### App Repository (Source Code)

```
app-repo/
+-- src/                      ? Application source code
+-- Dockerfile                ? Image build definition
+-- Jenkinsfile               ? CI: build, test, scan, push image, then update config-repo
+-- pom.xml / package.json
```

The CI pipeline runs here. It builds and pushes the Docker image, then commits the new image tag into the **config-repo**.

### Config Repository (GitOps Repo � what ArgoCD watches)

```
config-repo/
+-- apps/                         ? ArgoCD Application manifests
�   +-- app-of-apps.yaml          ? Root app that manages all child apps
�   +-- myapp/
�       +-- dev.yaml
�       +-- staging.yaml
�       +-- prod.yaml
+-- base/                         ? Shared Kubernetes manifests (Kustomize base)
�   +-- kustomization.yaml
�   +-- deployment.yaml
�   +-- service.yaml
+-- environments/                 ? Per-environment Kustomize overlays
    +-- dev/
    �   +-- kustomization.yaml    ? Overrides: image tag, replicas, namespace
    �   +-- patch-resources.yaml
    +-- staging/
    �   +-- kustomization.yaml
    �   +-- patch-resources.yaml
    +-- prod/
        +-- kustomization.yaml
        +-- patch-resources.yaml
```

### Base Deployment (`base/deployment.yaml`)

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
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
```

### Production Overlay (`environments/prod/kustomization.yaml`)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: production

replicas:
  - name: myapp
    count: 3

# CI pipeline updates this value on each successful build
images:
  - name: your-org.jfrog.io/docker-local/myapp
    newTag: "1.2.3"

commonLabels:
  environment: production

patches:
  - path: patch-resources.yaml   # Production resource limits
```

---

## App-of-Apps Pattern

A single **root Application** manages a directory of other ArgoCD Application manifests. Adding a new service = adding a YAML file and pushing to Git.

```
app-of-apps (root)
+-- frontend-dev / frontend-prod
+-- user-service-dev / user-service-prod
+-- order-service-dev / order-service-prod
```

### Root Application

```yaml
# apps/app-of-apps.yaml � deploy this once manually
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # deletes child apps when root is deleted
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/config-repo.git
    targetRevision: HEAD
    path: apps                    # ArgoCD watches this entire directory
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd             # Applications live in the argocd namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Child Application Example

```yaml
# apps/myapp/prod.yaml
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
  project: production-project
  source:
    repoURL: https://github.com/your-org/config-repo.git
    targetRevision: HEAD
    path: environments/prod
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
# Deploy the root app once � it picks up every child app in apps/
kubectl apply -f apps/app-of-apps.yaml -n argocd

# Sync root app (triggers sync of all children)
argocd app sync app-of-apps --cascade

# List all auto-discovered apps
argocd app list
```

---

## ApplicationSet - Multi-Cluster & Multi-Env

`ApplicationSet` generates multiple ArgoCD Applications from a template, eliminating repetitive per-environment YAML.

### List Generator (explicit environments)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - environment: dev
            namespace: development
            cluster: https://kubernetes.default.svc
            imageTag: "latest"
          - environment: staging
            namespace: staging
            cluster: https://staging-cluster.example.com
            imageTag: "1.2.3"
          - environment: prod
            namespace: production
            cluster: https://prod-cluster.example.com
            imageTag: "1.2.2"   # Prod intentionally lags staging

  template:
    metadata:
      name: myapp-{{environment}}   # Creates: myapp-dev, myapp-staging, myapp-prod
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

### Git Generator (directory-based � auto-discover environments)

```yaml
# Automatically creates one Application per subdirectory of environments/
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
          - path: environments/*   # Matches environments/dev, environments/staging, etc.

  template:
    metadata:
      name: myapp-{{path.basename}}   # Directory name becomes app name
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

### Cluster Generator (multi-cluster rollout)

```yaml
# Deploy to every ArgoCD-registered cluster that has the label deploy-myapp=true
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
            deploy-myapp: "true"

  template:
    metadata:
      name: myapp-{{name}}   # {{name}} = ArgoCD cluster name
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/config-repo.git
        targetRevision: HEAD
        path: environments/{{metadata.labels.environment}}
      destination:
        server: "{{server}}"   # {{server}} = cluster API URL
        namespace: myapp
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

---

## Sync Policies & Hooks

### Automated Sync with Full Options

```yaml
spec:
  syncPolicy:
    automated:
      prune: true        # Delete resources removed from Git
      selfHeal: true     # Revert manual cluster changes
      allowEmpty: false  # Prevent accidental deletion of all resources
    syncOptions:
      - ApplyOutOfSyncOnly=true    # Only apply changed resources (faster)
      - ServerSideApply=true       # Handles large resources and field managers
      - CreateNamespace=true       # Auto-create the destination namespace
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Sync Hooks

Hooks run Jobs at specific points in the sync lifecycle.

```yaml
# PreSync hook � database migration runs BEFORE any manifests are applied
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded   # Clean up on success
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
# PostSync hook � smoke test runs AFTER all resources are synced and healthy
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
            - curl -f http://myapp:8080/actuator/health || exit 1
      restartPolicy: Never
```

Available hook phases: `PreSync`, `Sync`, `PostSync`, `SyncFail`, `PostDelete`

---

## Environment Promotion

### Strategy 1: Image Tag Promotion (most common)

The CI pipeline updates the image tag in config-repo after a successful build. To promote, update the tag in the next environment.

```bash
#!/usr/bin/env bash
# promote.sh � promote image tag from one environment to another
# Usage: ./promote.sh dev staging

SOURCE_ENV="${1:-dev}"
TARGET_ENV="${2:-staging}"
APP="myapp"

# Read current tag from source environment
CURRENT_TAG=$(grep 'newTag:' "environments/${SOURCE_ENV}/kustomization.yaml" \
  | awk '{print $2}' | tr -d '"')

echo "Promoting ${APP}:${CURRENT_TAG} from ${SOURCE_ENV} to ${TARGET_ENV}"

cd "environments/${TARGET_ENV}"
kustomize edit set image \
  "your-org.jfrog.io/docker-local/${APP}=${CURRENT_TAG}"

git add kustomization.yaml
git commit -m "promote: ${APP}:${CURRENT_TAG} from ${SOURCE_ENV} to ${TARGET_ENV}

Promoted by: ${USER:-ci}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push

echo "Done. ArgoCD will auto-deploy ${TARGET_ENV}."
```

### Strategy 2: Branch-Based Promotion

```yaml
# dev tracks main (auto-deployed on every merge)
spec:
  source:
    targetRevision: main

# staging tracks staging branch (promotion = merge PR into staging)
spec:
  source:
    targetRevision: staging

# prod is pinned to an immutable tag
spec:
  source:
    targetRevision: v1.2.3
```

### Jenkins ? GitOps Config Repo Pipeline

```groovy
pipeline {
    agent any
    environment {
        JFROG_REGISTRY = 'your-org.jfrog.io'
        APP_NAME       = 'myapp'
        IMAGE_TAG      = "${env.BUILD_NUMBER}-${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE     = "${JFROG_REGISTRY}/docker-local/${APP_NAME}:${IMAGE_TAG}"
        TARGET_ENV     = 'dev'
        JFROG_CREDS    = credentials('jfrog-credentials')
        GIT_CREDS      = credentials('github-token')
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
        stage('Update Config Repo') {
            steps {
                sh """
                    git clone https://\${GIT_CREDS_USR}:\${GIT_CREDS_PSW}@github.com/your-org/config-repo.git
                    cd config-repo
                    git config user.email "jenkins@ci.local"
                    git config user.name "Jenkins CI"

                    cd environments/${TARGET_ENV}
                    kustomize edit set image \
                      "${JFROG_REGISTRY}/docker-local/${APP_NAME}=${IMAGE_TAG}"

                    git add kustomization.yaml
                    git commit -m "ci: update ${APP_NAME} to ${IMAGE_TAG} in ${TARGET_ENV}"
                    git push origin main
                    cd ../..
                    rm -rf config-repo
                """
            }
        }
        stage('Wait for ArgoCD Rollout') {
            steps {
                sh "argocd app wait ${APP_NAME}-${TARGET_ENV} --timeout 300 --health"
            }
        }
    }
}
```

---

## Secrets Management

Never commit plain Kubernetes Secrets to Git. Two recommended approaches:

### Option 1: Sealed Secrets (Bitnami)

Encrypts secrets client-side so the encrypted form is safe to commit.

```bash
# Install the controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets --namespace kube-system

# Install kubeseal CLI
curl -sSL https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/kubeseal-linux-amd64 \
  -o /usr/local/bin/kubeseal && chmod +x /usr/local/bin/kubeseal

# Create a plain secret (never committed)
kubectl create secret docker-registry jfrog-registry-secret \
  --namespace production \
  --docker-server=your-org.jfrog.io \
  --docker-username=your-user \
  --docker-password=your-token \
  --dry-run=client -o yaml > secret.yaml

# Seal it � this output IS safe to commit
kubeseal --namespace production --format yaml < secret.yaml > sealed-secret.yaml

git add sealed-secret.yaml && git commit -m "feat: sealed jfrog registry secret" && git push
rm secret.yaml   # Never commit the plain secret
```

The in-cluster Sealed Secrets controller decrypts `SealedSecret` objects into regular `Secret` resources.

### Option 2: External Secrets Operator (ESO)

Syncs secrets from Azure Key Vault, AWS Secrets Manager, or HashiCorp Vault into Kubernetes Secrets.

```yaml
# SecretStore � how to connect to Azure Key Vault
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
      authType: ManagedIdentity
```

```yaml
# ExternalSecret � what to sync and how to map it
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: jfrog-registry-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: azure-keyvault-store
  target:
    name: jfrog-registry-secret
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"your-org.jfrog.io":{"username":"{{ .jfrog-username }}","password":"{{ .jfrog-token }}"}}}
  data:
    - secretKey: jfrog-username
      remoteRef:
        key: jfrog-username
    - secretKey: jfrog-token
      remoteRef:
        key: jfrog-api-token
```

Both `SecretStore` and `ExternalSecret` contain no secret values and are safe to commit to Git.

---

## Real-World Scenarios

### Scenario 1: Bootstrap 3 Environments from a Single GitOps Repo

```bash
mkdir -p config-repo/{base,environments/{dev,staging,prod},apps}
cd config-repo && git add . && git commit -m "feat: initial gitops structure" && git push

kubectl apply -f - <<'EOF'
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

argocd app list
```

### Scenario 2: Rollback on Sync Failure

```bash
# View history and rollback to a specific revision
argocd app history myapp-prod
argocd app rollback myapp-prod 5
argocd app get myapp-prod
```

To automate rollback, configure ArgoCD Notifications to call a webhook on `SyncFailed`:

```yaml
# argocd-notifications-cm data section
trigger.on-sync-failed: |
  - when: app.status.operationState.phase in ['Error', 'Failed']
    send: [rollback-webhook]
template.rollback-webhook: |
  webhook:
    rollback:
      method: POST
      body: '{"app":"{{.app.metadata.name}}","action":"rollback"}'
service.webhook.rollback: |
  url: https://your-automation-server/rollback
  headers:
    - name: Authorization
      value: Bearer $WEBHOOK_TOKEN
```

---

## Troubleshooting (GitOps-Specific)

> For general ArgoCD troubleshooting (pods not starting, permission denied, image pull failures), see [01-cicd/argocd-complete-guide.md � Troubleshooting](../01-cicd/argocd-complete-guide.md#8-troubleshooting-guide).

### Kustomize Build Fails

```bash
kustomize build environments/prod          # reproduce locally
yamllint environments/prod/kustomization.yaml
kustomize build environments/prod | kubectl apply --dry-run=client -f -
```

### ApplicationSet Not Creating Applications

```bash
kubectl get applicationset -n argocd
kubectl describe applicationset myapp-environments -n argocd
# Check .status.conditions for generator errors
```

### Self-Heal Reverts a Needed Temporary Change

```bash
argocd app set myapp-prod --self-heal=false
# make temporary change
argocd app set myapp-prod --self-heal=true
```

### Config Repo Changes Not Picked Up

```bash
argocd app get myapp-dev --refresh   # force re-fetch Git (bypass cache)
kubectl logs -l app.kubernetes.io/name=argocd-repo-server -n argocd --tail=50
```

### Prune Deleting Resources Unexpectedly

```bash
argocd app diff myapp-prod             # inspect diff before syncing
argocd app set myapp-prod --auto-prune=false   # disable until investigated
```

---

*For the complete ArgoCD operational reference � installation, RBAC, SSO, multi-cluster setup, and the full CLI cheat sheet � see [01-cicd/argocd-complete-guide.md](../01-cicd/argocd-complete-guide.md).*
