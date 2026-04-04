# FluxCD Complete Guide

## Table of Contents
1. [Overview & Why FluxCD](#overview--why-fluxcd)
2. [Local Setup](#local-setup)
3. [Online/Cloud Setup](#onlinecloud-setup)
4. [Configuration Deep Dive](#configuration-deep-dive)
5. [Integration with Existing Tools](#integration-with-existing-tools)
6. [Real-World Scenarios](#real-world-scenarios)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Cheat Sheet](#cheat-sheet)

---

## Overview & Why FluxCD

### What is FluxCD?

FluxCD is a **GitOps continuous delivery solution for Kubernetes**. It is a CNCF Graduated project and a Kubernetes-native collection of controllers that reconcile cluster state with the desired state stored in Git, OCI registries, or Helm repositories.

Flux v2 (the current major version) is built as a set of composable Kubernetes controllers, each responsible for a specific reconciliation concern:

| Controller | Responsibility |
|-----------|----------------|
| **Source Controller** | Fetches artifacts: Git repos, Helm repos, OCI registries, S3 buckets |
| **Kustomize Controller** | Applies Kustomize overlays and raw YAML from sources |
| **Helm Controller** | Manages Helm releases from HelmRepository sources |
| **Image Reflector Controller** | Scans container registries for new image tags |
| **Image Automation Controller** | Updates image tags in Git when new images are found |
| **Notification Controller** | Sends alerts to Slack, Teams, webhooks on events |

### FluxCD vs ArgoCD

Both are excellent GitOps tools. Understanding the differences helps you choose the right one:

| Aspect | FluxCD | ArgoCD |
|--------|--------|--------|
| **Architecture** | Multiple small Kubernetes controllers | Centralized server + Redis + Dex |
| **UI** | Minimal (Weave GitOps provides a GUI) | Rich built-in dashboard (core feature) |
| **Primary focus** | Automation, controller-native | Visibility, multi-cluster operations |
| **Image automation** | Built-in (Image Reflector + Automation) | Via Argo Image Updater (separate install) |
| **Multi-tenancy** | Tenant configuration files | ArgoCD Projects + RBAC |
| **Notification** | Notification Controller (native) | Notification Controller (native) |
| **Multi-cluster** | Supported (with Cluster API, Flux Sharding) | Native multi-cluster (central ArgoCD manages remotes) |
| **OCI sources** | Supports OCI artifacts as sources | Limited |
| **Installation** | `flux bootstrap` (GitOps itself!) | `kubectl apply` or Helm |
| **Learning curve** | Medium — Kubernetes-native YAML | Low — UI-driven |
| **CI integration** | git commit → Flux detects | git commit → ArgoCD webhook/poll |

**Key insight:** FluxCD bootstraps itself into the cluster via GitOps — the Flux controllers are managed by Flux. ArgoCD does not manage its own lifecycle.

**When to choose FluxCD:**
- You prefer Kubernetes-native CRDs over a central UI
- You want built-in image automation
- You are running Kubernetes without a persistent dashboard need
- You want a lighter-weight solution
- Security teams prefer no privileged central server

**When to choose ArgoCD:**
- Your team needs a visual dashboard for deployment visibility
- You manage many clusters from a single pane of glass
- You want a streamlined UI for approvals and rollbacks
- Your organization is already invested in ArgoCD

---

## Local Setup

### Install Flux CLI

```bash
# On Linux
curl -s https://fluxcd.io/install.sh | sudo bash

# On macOS
brew install fluxcd/tap/flux

# On Windows (Chocolatey)
choco install flux

# Verify
flux version
```

### Prerequisites Check

```bash
# Check that your Kubernetes cluster meets Flux requirements
flux check --pre

# Expected output:
# ► checking prerequisites
# ✔ Kubernetes 1.26.0 >=1.24.0-0
# ✔ prerequisites checks passed
```

### Bootstrap Flux on Minikube (Local Dev)

**Bootstrap** is the process of installing Flux AND having Flux manage itself from a Git repository.

```bash
# Start Minikube
minikube start --cpus=4 --memory=8192

# Verify cluster
kubectl get nodes

# Bootstrap Flux to a GitHub repository
# This installs Flux components AND commits their manifests to your Git repo
flux bootstrap github \
  --owner=your-github-username \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/minikube \
  --personal \
  --token-auth

# You will be prompted for your GitHub Personal Access Token

# Bootstrap creates these in your repo:
# clusters/minikube/flux-system/
#   ├── gotk-components.yaml    ← Flux controllers (self-managed)
#   ├── gotk-sync.yaml          ← GitRepository + Kustomization for flux-system
#   └── kustomization.yaml

# Verify Flux is running
kubectl get pods -n flux-system
flux check
```

### Bootstrap to a GitLab Repository

```bash
flux bootstrap gitlab \
  --owner=your-gitlab-group \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/minikube \
  --token-auth
```

---

## Online/Cloud Setup

### Bootstrap Flux on Azure AKS

```bash
# Create AKS cluster (or use Terraform — see terraform-complete-guide.md)
az aks create \
  --resource-group my-rg \
  --name my-aks \
  --node-count 2 \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group my-rg --name my-aks

# Prerequisites check
flux check --pre

# Bootstrap to GitHub
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/aks-prod \
  --token-auth

# After bootstrap, commit your app configurations to the Git repo
# Flux will automatically reconcile them
```

### Using Azure DevOps with Flux

```bash
# Bootstrap with Azure DevOps
flux bootstrap git \
  --url=https://dev.azure.com/your-org/your-project/_git/fleet-infra \
  --branch=main \
  --path=clusters/aks-prod \
  --token-auth \
  --username=your-user \
  --password=your-pat-token
```

---

## Configuration Deep Dive

### GitRepository Source

A `GitRepository` defines a Git repository that Flux should watch:

```yaml
# sources/app-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: myapp-config
  namespace: flux-system
spec:
  # URL of the Git repository (config/GitOps repo)
  url: https://github.com/your-org/config-repo

  # How often to poll for new commits
  interval: 1m

  # Branch, tag, or commit SHA to track
  ref:
    branch: main
    # Or pin to a specific tag:
    # tag: v1.2.3
    # Or a semver range:
    # semver: ">=1.0.0 <2.0.0"

  # Reference to a Secret containing Git credentials
  secretRef:
    name: git-credentials

  # Only reconcile if files in these paths change (optional — improves performance)
  include:
    - fromPath: "apps/*"
      toPath: "apps/"
```

```bash
# Create the Git credentials secret
kubectl create secret generic git-credentials \
  --namespace flux-system \
  --from-literal=username=your-username \
  --from-literal=password=your-personal-access-token

# Apply the GitRepository
kubectl apply -f sources/app-source.yaml

# Check status
flux get sources git
kubectl get gitrepository -n flux-system
```

### Kustomization Reconciliation

A `Kustomization` (Flux's CRD, not the same as `kustomize.config.k8s.io`) applies manifests from a source to the cluster:

```yaml
# kustomizations/myapp-dev.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-dev
  namespace: flux-system
spec:
  # How often to reconcile (apply changes from Git)
  interval: 5m

  # If the source hasn't changed, retry after this duration on errors
  retryInterval: 1m

  # The source to pull manifests from
  sourceRef:
    kind: GitRepository
    name: myapp-config

  # Path within the repo to the Kustomize overlay
  path: ./environments/dev

  # Automatically create the target namespace
  prune: true         # Delete resources removed from Git
  wait: true          # Wait for all resources to be ready before marking Synced
  timeout: 5m         # Timeout for the reconciliation

  # Target namespace (overrides kustomization.yaml namespace if set)
  targetNamespace: development

  # Substitute variables in manifests (Flux variable substitution)
  postBuild:
    substitute:
      APP_ENV: "dev"
      REPLICA_COUNT: "1"
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
      - kind: Secret
        name: cluster-secrets

  # Health checks — Kustomization waits for these to be healthy
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: development
```

```bash
# Apply and check status
kubectl apply -f kustomizations/myapp-dev.yaml

flux get kustomizations
# NAME       REVISION    SUSPENDED  READY  MESSAGE
# myapp-dev  main/abc123 False      True   Applied revision: main/abc123

# Force a reconcile (don't wait for the interval)
flux reconcile kustomization myapp-dev --with-source
```

### HelmRepository and HelmRelease

Flux can manage Helm releases through GitOps:

```yaml
# sources/bitnami-helm-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  url: https://charts.bitnami.com/bitnami
  interval: 12h  # Check for new chart versions every 12 hours

  # For OCI-based Helm registries (e.g., JFrog)
  # type: oci
  # url: oci://your-org.jfrog.io/helm-local
```

```yaml
# releases/redis-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: redis
  namespace: flux-system
spec:
  # Target namespace for the Helm release
  targetNamespace: production

  # Install/upgrade interval
  interval: 10m

  # Reference to the HelmRepository source
  chart:
    spec:
      chart: redis                          # Chart name in the repository
      version: ">=17.0.0 <18.0.0"          # Semver constraint
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
      interval: 12h  # Check for chart updates

  # Helm values (equivalent to values.yaml)
  values:
    auth:
      enabled: true
    replica:
      replicaCount: 1
    master:
      persistence:
        size: 8Gi

  # Override values from Kubernetes Secrets/ConfigMaps
  valuesFrom:
    - kind: Secret
      name: redis-values-secret
      valuesKey: values.yaml

  # Rollback automatically if upgrade fails
  upgrade:
    remediation:
      retries: 3
      strategy: rollback
  install:
    remediation:
      retries: 3
```

```bash
# Apply HelmRepository and HelmRelease
kubectl apply -f sources/bitnami-helm-repo.yaml
kubectl apply -f releases/redis-release.yaml

# Check status
flux get helmreleases
flux get helmcharts

# Force upgrade
flux reconcile helmrelease redis
```

### ImageRepository and ImagePolicy for Image Automation

Flux can automatically update image tags in Git when new images are pushed to a registry:

```yaml
# image-automation/image-repo.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  # Container registry and image to watch
  image: your-org.jfrog.io/docker-local/myapp

  # How often to scan the registry for new tags
  interval: 5m

  # Reference to credentials for the registry
  secretRef:
    name: jfrog-registry-credentials
```

```yaml
# image-automation/image-policy.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp

  # Policy for selecting the "latest" image
  policy:
    # Semver: select the latest tag matching a semver range
    semver:
      range: ">=1.0.0"
    # Or use alphabetical ordering (useful for timestamp-based tags like 20240101-abc1234)
    # alphabetical:
    #   order: asc
    # Or use numerical ordering
    # numerical:
    #   order: asc
```

```yaml
# image-automation/image-update-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m

  # The Git source to update
  sourceRef:
    kind: GitRepository
    name: myapp-config

  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxbot@your-org.com
        name: FluxBot
      messageTemplate: |
        chore: update {{range .Updated.Images}}{{.}}{{end}} image

        Images updated:
        {{range .Updated.Images}}- {{.}}
        {{end}}
    push:
      branch: main

  update:
    # Strategy for finding and updating image references in YAML files
    strategy: Setters
```

**Mark the field in your YAML to be auto-updated:**

```yaml
# environments/dev/kustomization.yaml
images:
  - name: your-org.jfrog.io/docker-local/myapp
    # {"$imagepolicy": "flux-system:myapp"}  ← Flux marker: auto-updates this value
    newTag: "1.0.0" # {"$imagepolicy": "flux-system:myapp:tag"}
```

```bash
# Check image automation status
flux get images all

# Manually trigger an image scan
flux reconcile image repository myapp

# View the latest resolved tag
kubectl get imagepolicy myapp -n flux-system -o jsonpath='{.status.latestImage}'
```

### Flux Notification Controller

Send alerts to Slack, Teams, email, or custom webhooks:

```yaml
# notifications/slack-provider.yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: "#deployments"
  # Reference to a Secret containing the Slack webhook URL
  secretRef:
    name: slack-webhook-url
```

```bash
# Create the Slack webhook secret
kubectl create secret generic slack-webhook-url \
  --namespace flux-system \
  --from-literal=address=https://hooks.slack.com/services/T.../B.../...
```

```yaml
# notifications/alert.yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: deployment-alert
  namespace: flux-system
spec:
  # Which Notification Provider to use
  providerRef:
    name: slack

  # Alert on these Flux objects
  eventSources:
    - kind: Kustomization
      name: "*"  # All Kustomizations
    - kind: HelmRelease
      name: "*"  # All HelmReleases

  # Alert on error events (not informational)
  eventSeverity: error

  # Optional: only alert for specific events
  # inclusionList:
  #   - ".*succeeded.*"
  # exclusionList:
  #   - ".*no changes.*"
```

---

## Integration with Existing Tools

### Kubernetes Integration

Flux reconciles Kubernetes state. Every Kustomization or HelmRelease results in `kubectl apply`-equivalent operations. Key integration points:

```bash
# Flux creates/updates/deletes Kubernetes resources automatically
# No manual kubectl apply needed after initial bootstrap

# View what Flux manages
flux get all --all-namespaces

# Suspend reconciliation (maintenance window)
flux suspend kustomization myapp-dev
# Make manual cluster changes...
flux resume kustomization myapp-dev

# Check what would be applied (dry run)
flux diff kustomization myapp-dev
```

### Jenkins Integration

Jenkins builds the image and updates the image tag in Git. Flux detects the change and auto-deploys.

```groovy
// Jenkinsfile — CI pipeline that triggers Flux deployment via Git commit
pipeline {
    agent any

    environment {
        JFROG_REGISTRY  = 'your-org.jfrog.io'
        APP_NAME        = 'myapp'
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT[0..7]}"
        GITOPS_REPO     = 'https://github.com/your-org/config-repo.git'
        JFROG_CREDS     = credentials('jfrog-credentials')
        GIT_CREDS       = credentials('github-token')
    }

    stages {
        stage('Build & Push') {
            steps {
                sh """
                    docker build -t ${JFROG_REGISTRY}/docker-local/${APP_NAME}:${IMAGE_TAG} .
                    echo \${JFROG_CREDS_PSW} | \
                      docker login ${JFROG_REGISTRY} -u \${JFROG_CREDS_USR} --password-stdin
                    docker push ${JFROG_REGISTRY}/docker-local/${APP_NAME}:${IMAGE_TAG}
                    docker logout ${JFROG_REGISTRY}
                """
            }
        }

        stage('Update GitOps Repo') {
            steps {
                sh """
                    git clone https://\${GIT_CREDS_USR}:\${GIT_CREDS_PSW}@github.com/your-org/config-repo.git
                    cd config-repo

                    git config user.email "jenkins@ci.local"
                    git config user.name "Jenkins CI"

                    # Update image tag in dev environment
                    # Using kustomize to update the image tag properly
                    cd environments/dev
                    kustomize edit set image \
                      "${JFROG_REGISTRY}/docker-local/${APP_NAME}=${IMAGE_TAG}"

                    git add kustomization.yaml
                    git commit -m "ci: update ${APP_NAME} to ${IMAGE_TAG}

Source: Jenkins build ${env.BUILD_URL}
Image: ${JFROG_REGISTRY}/docker-local/${APP_NAME}:${IMAGE_TAG}"

                    git push origin main
                """
            }
            post {
                always {
                    sh 'rm -rf config-repo'
                }
            }
        }

        stage('Wait for Flux Sync') {
            steps {
                // Option 1: Poll for reconciliation
                sh """
                    for i in \$(seq 1 30); do
                        STATUS=\$(kubectl get kustomization myapp-dev \
                          -n flux-system \
                          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
                        if [ "\$STATUS" = "True" ]; then
                            echo "Flux reconciliation complete"
                            exit 0
                        fi
                        echo "Waiting for Flux... (\$i/30)"
                        sleep 10
                    done
                    echo "Flux reconciliation timed out"
                    exit 1
                """
            }
        }
    }
}
```

**Trigger Flux reconciliation via webhook (faster than polling):**

```bash
# Set up a Flux Receiver to trigger reconciliation on GitHub push events
cat << 'EOF' | kubectl apply -f -
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: github-receiver
  namespace: flux-system
spec:
  type: github
  events:
    - "ping"
    - "push"
  resources:
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: myapp-config
  secretRef:
    name: github-webhook-token
EOF

# Get the webhook URL
kubectl get receiver github-receiver -n flux-system \
  -o jsonpath='{.status.webhookPath}'

# Configure GitHub webhook to call: https://your-cluster/hook/<token>
```

### JFrog Integration

Flux's Image Automation controller can watch JFrog Artifactory for new image tags:

```yaml
# Configure ImageRepository to pull from JFrog
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp-jfrog
  namespace: flux-system
spec:
  image: your-org.jfrog.io/docker-local/myapp
  interval: 2m

  # JFrog registry authentication
  secretRef:
    name: jfrog-flux-credentials
```

```bash
# Create JFrog credentials for Flux Image Reflector
kubectl create secret docker-registry jfrog-flux-credentials \
  --namespace flux-system \
  --docker-server=your-org.jfrog.io \
  --docker-username=flux-service-account \
  --docker-password=your-jfrog-api-key

# Check that Flux can connect to JFrog and see images
flux get images repository myapp-jfrog

# View the latest scanned tags
kubectl get imagerepository myapp-jfrog \
  -n flux-system \
  -o jsonpath='{.status.lastScanResult}' | jq .
```

---

## Real-World Scenarios

### Scenario 1: Bootstrap Flux and Deploy First App

```bash
# Step 1: Bootstrap Flux to your GitHub repo
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/my-cluster \
  --personal \
  --token-auth

# Step 2: Clone the fleet-infra repo that Flux bootstrapped
git clone https://github.com/your-org/fleet-infra.git
cd fleet-infra

# Step 3: Create a GitRepository source pointing to your app config
mkdir -p clusters/my-cluster/sources

cat > clusters/my-cluster/sources/myapp-config.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: myapp-config
  namespace: flux-system
spec:
  url: https://github.com/your-org/config-repo
  interval: 1m
  ref:
    branch: main
  secretRef:
    name: git-credentials
EOF

# Step 4: Create a Kustomization to deploy the app
mkdir -p clusters/my-cluster/apps

cat > clusters/my-cluster/apps/myapp-dev.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-dev
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: myapp-config
  path: ./environments/dev
  prune: true
  targetNamespace: development
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: development
EOF

# Step 5: Commit and push — Flux will apply automatically
git add clusters/my-cluster/
git commit -m "feat: add myapp-dev kustomization"
git push

# Step 6: Watch Flux reconcile
flux get all --watch

# Step 7: Verify the app is running
kubectl get pods -n development
```

### Scenario 2: Automated Image Update When New Image Pushed to JFrog

This scenario sets up end-to-end automation: Jenkins pushes a new image to JFrog → Flux detects it → Flux updates Git → Flux deploys.

```bash
# Step 1: Install image-reflector and image-automation controllers
# (Not installed by default — add to bootstrap)
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/my-cluster \
  --components-extra=image-reflector-controller,image-automation-controller \
  --personal \
  --token-auth

# Step 2: Create JFrog credentials
kubectl create secret docker-registry jfrog-creds \
  --namespace flux-system \
  --docker-server=your-org.jfrog.io \
  --docker-username=flux-scanner \
  --docker-password=your-jfrog-token

# Step 3: Create ImageRepository to watch JFrog
kubectl apply -f - << 'EOF'
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  image: your-org.jfrog.io/docker-local/myapp
  interval: 1m
  secretRef:
    name: jfrog-creds
EOF

# Step 4: Create ImagePolicy to select the latest semver tag
kubectl apply -f - << 'EOF'
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp
  policy:
    semver:
      range: ">=1.0.0"
EOF

# Step 5: Mark the image field in kustomization.yaml for auto-update
# In your config-repo, environments/dev/kustomization.yaml:
# images:
#   - name: your-org.jfrog.io/docker-local/myapp
#     newTag: "1.0.0" # {"$imagepolicy": "flux-system:myapp:tag"}

# Step 6: Create ImageUpdateAutomation
kubectl apply -f - << 'EOF'
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: myapp-config
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxbot@your-org.com
        name: Flux Image Updater
      messageTemplate: |
        chore(image): update {{range .Updated.Images}}{{.}}{{end}}
    push:
      branch: main
  update:
    strategy: Setters
EOF

# Step 7: Verify the full flow
# Push a new image to JFrog: your-org.jfrog.io/docker-local/myapp:1.1.0
# Wait 1-2 minutes, then:
flux get images all
# Check Git for automatic commit by FluxBot
# Check cluster for new deployment
kubectl get pods -n development
kubectl describe deployment myapp -n development | grep Image
```

### Scenario 3: Multi-Tenancy with Flux Tenants

Flux supports multi-tenancy where different teams manage their own namespaces without cross-tenant access.

```bash
# Repository structure for multi-tenancy
fleet-infra/
├── clusters/
│   └── production/
│       ├── flux-system/          ← Flux controllers (platform team manages)
│       ├── tenants/
│       │   ├── team-alpha.yaml   ← Tenant configuration for team-alpha
│       │   └── team-beta.yaml    ← Tenant configuration for team-beta
│       └── platform/             ← Platform-level resources

# Step 1: Create a tenant namespace, ServiceAccount, and RBAC
cat > clusters/production/tenants/team-alpha.yaml << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
  labels:
    toolkit.fluxcd.io/tenant: team-alpha
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: team-alpha
  namespace: team-alpha
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-reconciler
  namespace: team-alpha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin  # Scope this down for production!
subjects:
- kind: ServiceAccount
  name: team-alpha
  namespace: team-alpha
---
# Tenant's GitRepository — managed by Flux, points to team-alpha's config repo
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: team-alpha
  namespace: team-alpha
spec:
  interval: 1m
  url: https://github.com/your-org/team-alpha-config
  ref:
    branch: main
  secretRef:
    name: team-alpha-git-creds
---
# Tenant's Kustomization — reconciles team-alpha's workloads
# Runs with team-alpha ServiceAccount (limited to team-alpha namespace)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: team-alpha
  namespace: team-alpha
spec:
  serviceAccountName: team-alpha  # Impersonates team-alpha SA — limits blast radius
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: team-alpha
  path: ./production
  prune: true
  targetNamespace: team-alpha
EOF

# Step 2: Commit the tenant configuration
git add clusters/production/tenants/
git commit -m "feat: add team-alpha tenant"
git push

# Flux reconciles and creates the tenant's Kustomization
# Team Alpha can now manage resources in their namespace via their own Git repo
# They CANNOT affect other namespaces (ServiceAccount is scoped to team-alpha)
flux get kustomizations --all-namespaces
```

---

## Verification & Testing

### Check Flux Health

```bash
# Overall health check
flux check

# Get all Flux resources
flux get all
flux get all --all-namespaces

# Get specific resource types
flux get sources git          # GitRepositories
flux get sources helm         # HelmRepositories
flux get sources oci          # OCIRepositories
flux get kustomizations       # Kustomizations
flux get helmreleases         # HelmReleases
flux get images all           # ImageRepositories + ImagePolicies + ImageUpdateAutomations
```

### Reconcile and Test

```bash
# Force immediate reconciliation (don't wait for interval)
flux reconcile source git myapp-config
flux reconcile kustomization myapp-dev --with-source

# See what would be applied (diff without applying)
flux diff kustomization myapp-dev

# Trace the reconciliation of a specific resource
flux trace deployment myapp --namespace development

# Export Flux resources for review
flux export source git --all > sources.yaml
flux export kustomization --all > kustomizations.yaml
```

### Validate Manifests

```bash
# Validate Kustomize overlays locally
kustomize build environments/dev | kubectl apply --dry-run=client -f -

# Validate with server-side dry run
kustomize build environments/dev | kubectl apply --dry-run=server -f -

# Run Flux validation checks
flux check --components-extra image-reflector-controller,image-automation-controller
```

---

## Troubleshooting Guide

### Issue 1: Kustomization Not Ready

```bash
# Check detailed status
kubectl describe kustomization myapp-dev -n flux-system

# Common causes:
# - YAML syntax error in the manifests
# - Missing referenced resources
# - Insufficient RBAC permissions
```

### Issue 2: GitRepository Authentication Failure

```
Authentication failed
```

**Fix:**
```bash
# Verify the secret exists
kubectl get secret git-credentials -n flux-system

# Test connectivity
flux check

# Re-create credentials
kubectl create secret generic git-credentials \
  --namespace flux-system \
  --from-literal=username=user \
  --from-literal=password=new-token \
  --dry-run=client -o yaml | kubectl apply -f -

# Force reconcile
flux reconcile source git myapp-config
```

### Issue 3: Helm Release Upgrade Failing

```bash
# Check HelmRelease status
kubectl describe helmrelease redis -n flux-system

# Check Helm release history
helm history redis -n production

# Force rollback
flux suspend helmrelease redis
helm rollback redis -n production
flux resume helmrelease redis
```

### Issue 4: Image Automation Not Updating Git

**Fix:**
```bash
# Verify image marker is correctly placed in YAML
# It must be a comment: # {"$imagepolicy": "flux-system:myapp:tag"}
grep -r 'imagepolicy' environments/

# Check ImagePolicy status
kubectl get imagepolicy myapp -n flux-system -o yaml

# Check ImageUpdateAutomation status
kubectl describe imageupdateautomation myapp -n flux-system

# Check ImageRepository can scan JFrog
kubectl describe imagerepository myapp -n flux-system
```

### Issue 5: Prune Deletes Resources Unexpectedly

**Cause:** Resources in the cluster aren't labeled with Flux's ownership labels.

**Fix:**
```bash
# Add the Flux labels to existing resources before enabling prune
kubectl label deployment myapp \
  kustomize.toolkit.fluxcd.io/name=myapp-dev \
  kustomize.toolkit.fluxcd.io/namespace=flux-system

# Or temporarily disable prune while migrating
flux suspend kustomization myapp-dev
# Migrate resources...
flux resume kustomization myapp-dev
```

### Issue 6: Notifications Not Sending

```bash
# Check Alert and Provider status
kubectl describe alert deployment-alert -n flux-system
kubectl describe provider slack -n flux-system

# Verify the webhook secret
kubectl get secret slack-webhook-url -n flux-system

# Test notification manually
kubectl -n flux-system delete pod -l app=notification-controller
# Wait for restart and trigger a sync to test
```

### Issue 7: Bootstrap Fails — Already Exists

**Fix:**
```bash
# Use --force flag to overwrite existing components
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/my-cluster \
  --personal \
  --token-auth \
  --force
```

### Issue 8: Flux Components Outdated After Cluster Upgrade

```bash
# Upgrade Flux components to match the CLI version
flux install --export | kubectl apply -f -

# Or re-bootstrap
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --branch=main \
  --path=clusters/my-cluster \
  --personal \
  --token-auth
```

---

## Cheat Sheet

### Core Flux Commands

| Command | Description |
|---------|-------------|
| `flux check` | Check Flux prerequisites and components |
| `flux check --pre` | Only check prerequisites (before install) |
| `flux bootstrap github ...` | Bootstrap Flux to GitHub |
| `flux install` | Install Flux in the current cluster |
| `flux uninstall` | Remove Flux from the cluster |
| `flux version` | Show Flux CLI and controller versions |
| `flux get all` | List all Flux resources and their status |
| `flux get all --all-namespaces` | All Flux resources across all namespaces |

### Source Commands

| Command | Description |
|---------|-------------|
| `flux get sources git` | List GitRepository sources |
| `flux get sources helm` | List HelmRepository sources |
| `flux get sources oci` | List OCIRepository sources |
| `flux reconcile source git name` | Force reconcile a GitRepository |
| `flux export source git --all` | Export all GitRepositories as YAML |
| `flux create source git name --url ... --branch main` | Create a GitRepository |

### Kustomization Commands

| Command | Description |
|---------|-------------|
| `flux get kustomizations` | List all Kustomizations |
| `flux reconcile kustomization name` | Force reconcile a Kustomization |
| `flux reconcile kustomization name --with-source` | Reconcile source then Kustomization |
| `flux diff kustomization name` | Show diff between Git and cluster |
| `flux suspend kustomization name` | Pause reconciliation |
| `flux resume kustomization name` | Resume reconciliation |
| `flux trace deployment name -n ns` | Trace how a resource is managed by Flux |

### Helm Commands

| Command | Description |
|---------|-------------|
| `flux get helmreleases` | List all HelmReleases |
| `flux reconcile helmrelease name` | Force reconcile a HelmRelease |
| `flux suspend helmrelease name` | Pause a HelmRelease |
| `flux resume helmrelease name` | Resume a HelmRelease |

### Image Automation Commands

| Command | Description |
|---------|-------------|
| `flux get images repository` | List ImageRepositories |
| `flux get images policy` | List ImagePolicies |
| `flux get images update` | List ImageUpdateAutomations |
| `flux reconcile image repository name` | Force scan a registry |
| `flux reconcile image update name` | Force run image automation |

### Event / Notification Commands

| Command | Description |
|---------|-------------|
| `flux events` | List recent Flux events |
| `flux events --watch` | Watch Flux events in real time |
| `flux logs` | View Flux controller logs |
| `flux logs --level=error` | View only error-level logs |
| `flux logs --follow` | Follow Flux controller logs |

### Debugging

| Command | Description |
|---------|-------------|
| `flux stats` | Show statistics for all Flux resources |
| `flux export kustomization --all` | Export all Kustomizations |
| `flux export helmrelease --all` | Export all HelmReleases |
| `kubectl describe kustomization name -n flux-system` | Detailed Kustomization status |
| `kubectl describe helmrelease name -n flux-system` | Detailed HelmRelease status |
| `kubectl get events -n flux-system --sort-by='.lastTimestamp'` | Recent events in flux-system |

---

*This guide covers FluxCD as used in the context of the DevOps Final Project. For the latest documentation, see [https://fluxcd.io/docs](https://fluxcd.io/docs).*
