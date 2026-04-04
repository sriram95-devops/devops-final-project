# ArgoCD Complete Guide

A comprehensive guide to deploying, configuring, and operating ArgoCD — the GitOps continuous delivery controller for Kubernetes — across local Minikube, Azure AKS, and Killercoda playground environments.

---

## Table of Contents

1. [Overview & Why You Need It](#1-overview--why-you-need-it)
2. [Local Setup on Minikube](#2-local-setup-on-minikube)
3. [Online / Cloud Setup](#3-online--cloud-setup)
4. [Configuration Deep Dive](#4-configuration-deep-dive)
5. [Integration with Existing Tools](#5-integration-with-existing-tools)
6. [Real-World Scenarios & Hands-On Exercises](#6-real-world-scenarios--hands-on-exercises)
7. [Verification & Testing](#7-verification--testing)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [Cheat Sheet](#9-cheat-sheet)

---

## 1. Overview & Why You Need It

### What is ArgoCD?

ArgoCD is a **declarative, GitOps continuous delivery tool for Kubernetes**. It continuously monitors Git repositories and ensures that the live state of your Kubernetes cluster matches the desired state declared in Git.

```
Git Repository (desired state)
        │
        │  ArgoCD polls / webhook
        ▼
  ┌─────────────┐    diff detected    ┌───────────────┐
  │   ArgoCD    │ ──────────────────► │  Kubernetes   │
  │  Controller │    apply changes    │   Cluster     │
  └─────────────┘                     └───────────────┘
        │
        │  Reports status back to Git (via UI/API)
        ▼
   Sync Status: Synced ✓  Health: Healthy ✓
```

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Application** | An ArgoCD CRD that links a Git repo path to a Kubernetes destination |
| **AppProject** | RBAC boundary grouping Applications; controls which repos, clusters, and namespaces are allowed |
| **Sync** | The act of reconciling Git state → Kubernetes state |
| **Self-Heal** | ArgoCD automatically reverts manual changes to match Git |
| **Drift Detection** | Continuous comparison of live state vs. desired state |
| **Health Assessment** | ArgoCD understands Deployment, StatefulSet, Job, etc. health |

### GitOps Operator Comparison

| Feature | ArgoCD | Flux | Spinnaker |
|---------|--------|------|-----------|
| GitOps native | ✅ | ✅ | ❌ (push-based) |
| UI | Rich web UI | Limited (Weave GitOps) | Rich UI |
| Multi-cluster | ✅ | ✅ | ✅ |
| Helm support | ✅ Native | ✅ Native | Via plugin |
| Kustomize support | ✅ Native | ✅ Native | Via plugin |
| RBAC | ✅ Built-in | ✅ Via Flux RBAC | ✅ |
| SSO | ✅ OIDC/LDAP | ❌ (delegated to K8s) | ✅ |
| Rollback | ✅ One-click | Manual | ✅ |
| Progressive delivery | Via Argo Rollouts | Via Flagger | Built-in |
| Learning curve | Medium | Medium | High |

### Why ArgoCD Over Pure CI/CD?

Traditional CI/CD pipelines (e.g., Jenkins push model) have a key weakness: the pipeline has **write access to the cluster**. If the pipeline breaks mid-deploy or the cluster is manually modified, you have drift with no automatic reconciliation.

ArgoCD solves this by:
1. **Pulling** desired state from Git, not pushing
2. **Continuously reconciling** — not just on commit
3. **Self-healing** — reverts manual `kubectl` changes
4. **Auditable** — every change has a Git commit as its source

---

## 2. Local Setup on Minikube

### Prerequisites

- Minikube running with at least 4 CPU / 8 GB RAM (see local-setup-guide.md)
- kubectl configured
- Helm 3 installed
- ArgoCD CLI installed

### Method A: Install ArgoCD with kubectl

```bash
# Create namespace
kubectl create namespace argocd

# Apply the official installation manifest
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Expected output:

```
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io created
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io created
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io created
serviceaccount/argocd-application-controller created
...
deployment.apps/argocd-server created
```

Wait for all pods to be ready:

```bash
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
kubectl get pods -n argocd
```

Expected output:

```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m
argocd-applicationset-controller-xxx                1/1     Running   0          2m
argocd-dex-server-xxx                               1/1     Running   0          2m
argocd-notifications-controller-xxx                 1/1     Running   0          2m
argocd-redis-xxx                                    1/1     Running   0          2m
argocd-repo-server-xxx                              1/1     Running   0          2m
argocd-server-xxx                                   1/1     Running   0          2m
```

### Method B: Install ArgoCD with Helm

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.3.x \
  --set configs.params."server\.insecure"=true \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --wait
```

### Expose the ArgoCD UI

#### Option 1: Port-forward (simplest)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
# Access at: https://localhost:8080
```

#### Option 2: NodePort via Minikube

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'

minikube service argocd-server -n argocd --url
```

#### Option 3: Ingress on Minikube

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.local
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

```bash
kubectl apply -f argocd-ingress.yaml
echo "$(minikube ip) argocd.local" | sudo tee -a /etc/hosts
# Access at: https://argocd.local
```

### Get the Initial Admin Password

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
echo   # print newline after the password
```

Expected output:

```
R4nd0mP4ss!xYz
```

### Login via CLI

```bash
argocd login localhost:8080 \
  --username admin \
  --password "$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure
```

Expected output:

```
'admin:login' logged in successfully
Context 'localhost:8080' updated
```

### Change the Admin Password

```bash
argocd account update-password \
  --current-password "$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" \
  --new-password "MySecureAdminPassword123!"
```

After changing, delete the initial secret:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

---

## 3. Online / Cloud Setup

### 3.1 Azure AKS Setup

#### Create AKS Cluster

```bash
# Variables
RESOURCE_GROUP="rg-devops-lab"
CLUSTER_NAME="aks-devops-lab"
LOCATION="eastus"
NODE_COUNT=3
NODE_VM_SIZE="Standard_DS2_v2"

# Create resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Create AKS cluster
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --node-count "$NODE_COUNT" \
  --node-vm-size "$NODE_VM_SIZE" \
  --enable-managed-identity \
  --enable-addons monitoring \
  --kubernetes-version 1.30 \
  --generate-ssh-keys

# Get credentials
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

# Verify
kubectl get nodes
```

#### Install ArgoCD on AKS

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for deployment
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
```

#### Expose ArgoCD via Azure Load Balancer

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for external IP
kubectl get svc argocd-server -n argocd --watch
```

After the EXTERNAL-IP is assigned:

```bash
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ArgoCD UI: https://${ARGOCD_IP}"

# Login
argocd login "${ARGOCD_IP}" \
  --username admin \
  --password "$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure
```

#### Use Azure Application Gateway Ingress (production)

For production AKS deployments, use AGIC (Application Gateway Ingress Controller) with TLS:

```bash
# Enable AGIC addon
az aks enable-addons \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --addons ingress-appgw \
  --appgw-name "appgw-argocd" \
  --appgw-subnet-cidr "10.225.0.0/16"
```

```yaml
# argocd-ingress-aks.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - argocd.yourdomain.com
      secretName: argocd-tls
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
                  number: 80
```

### 3.2 Killercoda Playground

Killercoda provides free browser-based Kubernetes environments at <https://killercoda.com/>.

1. Open <https://killercoda.com/playgrounds/scenario/kubernetes>
2. Wait for the environment to start (it gives you a running K8s cluster)
3. In the terminal:

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Use NodePort to access
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
kubectl get svc argocd-server -n argocd

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Install ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Get NodePort
NODE_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
argocd login "${NODE_IP}:${NODE_PORT}" --username admin --insecure
```

---

## 4. Configuration Deep Dive

### 4.1 ArgoCD Application CRD

The `Application` CRD is the core object that instructs ArgoCD what to deploy and where.

```yaml
# app-sample.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
  labels:
    team: platform
    env: dev
  finalizers:
    # Ensures ArgoCD deletes K8s resources when the Application is deleted
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main          # branch, tag, or commit SHA
    path: kubernetes/apps/sample  # path within the repo

  destination:
    server: https://kubernetes.default.svc  # in-cluster
    namespace: dev

  syncPolicy:
    automated:
      prune: true       # delete K8s resources removed from Git
      selfHeal: true    # revert manual changes
      allowEmpty: false # prevent accidental deletion of all resources
    syncOptions:
      - CreateNamespace=true        # create namespace if it doesn't exist
      - PrunePropagationPolicy=foreground
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # Override values in Helm charts
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: helm/sample-app
    helm:
      releaseName: sample-app
      valueFiles:
        - values.yaml
        - values-dev.yaml
      parameters:
        - name: image.repository
          value: yourname-devops.jfrog.io/docker-local/sample-app
        - name: image.tag
          value: "1.2.3"
      version: v3

  # Ignore differences in certain fields (e.g., auto-scaling)
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: autoscaling
      kind: HorizontalPodAutoscaler
      jqPathExpressions:
        - .spec.metrics
```

### 4.2 AppProject CRD

AppProjects enforce RBAC boundaries. Always create dedicated projects for each team or environment.

```yaml
# project-platform.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: argocd
spec:
  description: "Platform team applications"

  # Allow deployments only from these Git repos
  sourceRepos:
    - https://github.com/your-org/devops-final-project.git
    - https://github.com/your-org/helm-charts.git

  # Allow deployments only to these destinations
  destinations:
    - server: https://kubernetes.default.svc
      namespace: dev
    - server: https://kubernetes.default.svc
      namespace: staging
    - server: https://aks-prod.eastus.azmk8s.io
      namespace: prod

  # Allow these cluster-scoped resources
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding

  # Deny these namespace-scoped resources
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
    - group: ""
      kind: LimitRange

  # Project-level RBAC roles
  roles:
    - name: developer
      description: "Developer read-only access"
      policies:
        - p, proj:platform:developer, applications, get, platform/*, allow
        - p, proj:platform:developer, applications, sync, platform/*, allow
      groups:
        - platform-developers

    - name: admin
      description: "Platform admin full access"
      policies:
        - p, proj:platform:admin, applications, *, platform/*, allow
      groups:
        - platform-admins

  # Orphaned resources monitoring
  orphanedResources:
    warn: true

  # Sync windows: restrict when syncs can happen
  syncWindows:
    - kind: allow
      schedule: "10 1 * * *"    # 1:10 AM daily
      duration: 1h
      applications:
        - "*"
      manualSync: true
    - kind: deny
      schedule: "0 22 * * 5"   # Friday 10 PM
      duration: 36h             # weekend freeze
      applications:
        - "*"
      manualSync: false
```

### 4.3 Repository Configuration

#### Add a Private Git Repository (HTTPS)

```bash
argocd repo add https://github.com/your-org/private-repo.git \
  --username your-github-username \
  --password "ghp_yourPersonalAccessToken"
```

#### Add a Private Git Repository (SSH)

```bash
argocd repo add git@github.com:your-org/private-repo.git \
  --ssh-private-key-path ~/.ssh/id_ed25519
```

#### Via Secret (declarative)

```yaml
# repo-secret.yaml — store in a sealed-secrets or Vault, not plain git
apiVersion: v1
kind: Secret
metadata:
  name: private-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/your-org/private-repo.git
  username: your-github-username
  password: ghp_yourPersonalAccessToken
```

```bash
kubectl apply -f repo-secret.yaml
```

#### Credential Templates (for multiple repos from same org)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-org-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  type: git
  url: https://github.com/your-org   # matches all repos under this org
  username: your-github-username
  password: ghp_yourPersonalAccessToken
```

### 4.4 RBAC Configuration

ArgoCD's RBAC is configured in the `argocd-rbac-cm` ConfigMap.

```yaml
# argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Built-in roles: role:readonly, role:admin

    # Custom role: developer
    p, role:developer, applications, get,    */*, allow
    p, role:developer, applications, sync,   */*, allow
    p, role:developer, applications, action, */*, allow
    p, role:developer, logs,          get,   */*, allow

    # Custom role: release-manager
    p, role:release-manager, applications, *, */*, allow
    p, role:release-manager, projects,     *, */*, allow
    p, role:release-manager, repositories, *, */*, allow

    # Assign roles to groups (from OIDC/LDAP)
    g, platform-developers, role:developer
    g, platform-leads,      role:release-manager
    g, sre-team,            role:admin

    # Assign role to specific user
    g, jenkins-bot,         role:release-manager
  scopes: '[groups]'
```

```bash
kubectl apply -f argocd-rbac-cm.yaml
```

### 4.5 SSO with OIDC (Azure AD)

```yaml
# argocd-cm.yaml (partial — SSO section)
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.yourdomain.com

  oidc.config: |
    name: Azure AD
    issuer: https://login.microsoftonline.com/<TENANT_ID>/v2.0
    clientID: <AZURE_APP_CLIENT_ID>
    clientSecret: $oidc.azure.clientSecret
    requestedIDTokenClaims:
      groups:
        essential: true
    requestedScopes:
      - openid
      - profile
      - email
```

Store the client secret:

```bash
kubectl create secret generic argocd-secret \
  --namespace argocd \
  --from-literal=oidc.azure.clientSecret="your-azure-app-secret" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 5. Integration with Existing Tools

### 5.1 Jenkins Integration

Jenkins builds Docker images and pushes them to JFrog. After a successful push, Jenkins updates the Helm `values.yaml` with the new image tag and triggers an ArgoCD sync.

#### Jenkins → ArgoCD Sync via CLI

In your Jenkins agent, the ArgoCD CLI must be installed:

```groovy
stage('ArgoCD Sync') {
    steps {
        withCredentials([string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_TOKEN')]) {
            sh '''
                argocd login ${ARGOCD_SERVER} \
                  --auth-token ${ARGOCD_TOKEN} \
                  --insecure \
                  --grpc-web

                argocd app sync sample-app \
                  --revision ${GIT_COMMIT} \
                  --timeout 300

                argocd app wait sample-app \
                  --health \
                  --timeout 300
            '''
        }
    }
}
```

#### Create an ArgoCD Service Account for Jenkins

```bash
# Create local user in argocd-cm ConfigMap
kubectl patch configmap argocd-cm -n argocd \
  --type merge \
  --patch '{"data":{"accounts.jenkins":"apiKey"}}'

# Generate API token for jenkins user
argocd account generate-token --account jenkins
# Save this token as a Jenkins credential named 'argocd-auth-token'
```

```bash
# Grant permissions to the jenkins user (add to argocd-rbac-cm)
kubectl patch configmap argocd-rbac-cm -n argocd \
  --type merge \
  --patch '{"data":{"policy.csv":"p, jenkins, applications, sync, */*, allow\np, jenkins, applications, get, */*, allow\n"}}'
```

### 5.2 Kubernetes Integration

ArgoCD is itself a Kubernetes controller. It uses the Kubernetes API to apply, diff, and monitor resources.

#### Health Checks

ArgoCD has built-in health assessment for standard K8s resources:

| Resource | Health logic |
|----------|-------------|
| Deployment | All replicas ready and updated |
| StatefulSet | All replicas ready |
| DaemonSet | All nodes have desired pods |
| Job | Completed successfully |
| PersistentVolumeClaim | Bound |
| Service | Has endpoints (if ClusterIP) |
| Ingress | Has load balancer IP/hostname |

Custom health checks can be added for CRDs:

```yaml
# In argocd-cm ConfigMap
data:
  resource.customizations.health.certmanager.io_Certificate: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for certificate"
    return hs
```

#### Register External Clusters

```bash
# Add an AKS cluster to ArgoCD
kubectl config use-context aks-prod
argocd cluster add aks-prod \
  --name prod-aks \
  --system-namespace argocd

argocd cluster list
```

### 5.3 JFrog Artifactory Integration

#### Create Image Pull Secret for JFrog

```bash
kubectl create secret docker-registry jfrog-registry \
  --docker-server=yourname-devops.jfrog.io \
  --docker-username="${JFROG_USER}" \
  --docker-password="${JFROG_TOKEN}" \
  --namespace=dev
```

#### Helm Values Referencing JFrog Images

```yaml
# helm/sample-app/values.yaml
image:
  repository: yourname-devops.jfrog.io/docker-local/sample-app
  tag: "1.0.0"
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: jfrog-registry
```

#### ArgoCD Application Using JFrog Images

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-dev
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: helm/sample-app
    helm:
      valueFiles:
        - values.yaml
        - values-dev.yaml
      parameters:
        - name: image.repository
          value: yourname-devops.jfrog.io/docker-local/sample-app
        - name: image.tag
          value: "1.2.3"
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### ArgoCD Image Updater (automatic image tag updates)

ArgoCD Image Updater polls JFrog and automatically updates the image tag in Git.

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

Annotate your Application:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: |
      sample-app=yourname-devops.jfrog.io/docker-local/sample-app
    argocd-image-updater.argoproj.io/sample-app.update-strategy: semver
    argocd-image-updater.argoproj.io/sample-app.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/sample-app.helm.image-tag: image.tag
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
```

Configure JFrog registry credentials for Image Updater:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: JFrog Artifactory
        api_url: https://yourname-devops.jfrog.io/artifactory
        prefix: yourname-devops.jfrog.io
        credentials: secret:argocd/jfrog-registry#.dockerconfigjson
        defaultns: docker-local
        insecure: false
```

### 5.4 SonarQube Quality Gate Integration

ArgoCD itself does not run code scans. The pattern is:

1. Jenkins runs SonarQube scan in a pipeline stage
2. Jenkins waits for the quality gate result
3. **Only if** the quality gate passes, Jenkins updates the Git repo with the new image tag
4. ArgoCD detects the Git change and syncs

This means the quality gate acts as a **pre-sync gate** — ArgoCD never sees a deploy that failed quality.

```groovy
// Jenkinsfile excerpt
stage('SonarQube Analysis') {
    steps {
        withSonarQubeEnv('sonarqube-server') {
            sh 'mvn sonar:sonar -Dsonar.projectKey=sample-app'
        }
    }
}

stage('Quality Gate') {
    steps {
        timeout(time: 5, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true
        }
    }
}

// Only reached if quality gate passes:
stage('Update Helm Values') {
    steps {
        sh '''
            sed -i "s/tag:.*/tag: \\"${IMAGE_TAG}\\"/" helm/sample-app/values-dev.yaml
            git commit -am "ci: bump image tag to ${IMAGE_TAG} [skip ci]"
            git push origin main
        '''
    }
}
```

---

## 6. Real-World Scenarios & Hands-On Exercises

### Exercise 1: Deploy a Sample Application via ArgoCD

**Goal:** Deploy an Nginx-based sample app through ArgoCD from a Git repository.

#### Step 1: Create the Kubernetes manifests

```bash
mkdir -p kubernetes/apps/sample-app
```

```yaml
# kubernetes/apps/sample-app/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app
```

```yaml
# kubernetes/apps/sample-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: sample-app
  labels:
    app: sample-app
    version: "1.0.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        version: "1.0.0"
    spec:
      containers:
        - name: sample-app
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 20
```

```yaml
# kubernetes/apps/sample-app/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: sample-app
spec:
  selector:
    app: sample-app
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

```bash
# Commit and push
git add kubernetes/apps/sample-app/
git commit -m "feat: add sample-app manifests"
git push origin main
```

#### Step 2: Create ArgoCD Application

```bash
argocd app create sample-app \
  --project default \
  --repo https://github.com/your-org/devops-final-project.git \
  --path kubernetes/apps/sample-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace sample-app \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true

# Check status
argocd app get sample-app
```

Expected output:

```
Name:               argocd/sample-app
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          sample-app
URL:                https://localhost:8080/applications/sample-app
Source:
  Repo:             https://github.com/your-org/devops-final-project.git
  Target:           main
  Path:             kubernetes/apps/sample-app
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune, Self Heal)
Sync Status:        Synced to main (a1b2c3d)
Health Status:      Healthy

GROUP  KIND        NAMESPACE   NAME        STATUS  HEALTH   HOOK  MESSAGE
       Namespace               sample-app  Synced  Healthy
apps   Deployment  sample-app  sample-app  Synced  Healthy        deployment.apps/sample-app configured
       Service     sample-app  sample-app  Synced  Healthy        service/sample-app configured
```

#### Step 3: Verify Self-Healing

```bash
# Manually scale down (simulate an unwanted change)
kubectl scale deployment sample-app -n sample-app --replicas=0

# Watch ArgoCD detect and fix the drift (within ~3 seconds by default)
watch argocd app get sample-app
```

Within seconds, ArgoCD restores replicas to 2.

---

### Exercise 2: Multi-Environment Deployment (dev/staging/prod)

**Goal:** Deploy the same application to three environments with environment-specific configuration.

#### Repository Structure

```
helm/sample-app/
├── Chart.yaml
├── values.yaml           # defaults
├── values-dev.yaml       # dev overrides
├── values-staging.yaml   # staging overrides
└── values-prod.yaml      # production overrides
```

```yaml
# helm/sample-app/values.yaml
replicaCount: 1
image:
  repository: yourname-devops.jfrog.io/docker-local/sample-app
  tag: "latest"
  pullPolicy: IfNotPresent
imagePullSecrets:
  - name: jfrog-registry
service:
  type: ClusterIP
  port: 80
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
autoscaling:
  enabled: false
```

```yaml
# helm/sample-app/values-dev.yaml
replicaCount: 1
image:
  tag: "latest"
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

```yaml
# helm/sample-app/values-staging.yaml
replicaCount: 2
image:
  tag: "1.2.3"
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

```yaml
# helm/sample-app/values-prod.yaml
replicaCount: 3
image:
  tag: "1.2.0"   # prod lags staging intentionally
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi
```

#### Create Applications for Each Environment

```yaml
# argocd-apps-multi-env.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-dev
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: helm/sample-app
    helm:
      valueFiles: [values.yaml, values-dev.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-staging
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: helm/sample-app
    helm:
      valueFiles: [values.yaml, values-staging.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-prod
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: helm/sample-app
    helm:
      valueFiles: [values.yaml, values-prod.yaml]
  destination:
    server: https://aks-prod.eastus.azmk8s.io   # separate production cluster
    namespace: prod
  syncPolicy:
    syncOptions: [CreateNamespace=true]
    # No automated sync for prod — manual approval required
```

```bash
kubectl apply -f argocd-apps-multi-env.yaml
argocd app list
```

Expected output:

```
NAME                 CLUSTER                          NAMESPACE  PROJECT   STATUS  HEALTH   SYNCPOLICY
sample-app-dev       https://kubernetes.default.svc   dev        platform  Synced  Healthy  Auto-Prune
sample-app-staging   https://kubernetes.default.svc   staging    platform  Synced  Healthy  Auto-Prune
sample-app-prod      https://aks-prod.eastus.azmk8s.io prod       platform  Synced  Healthy  <none>
```

To promote to production (manual):

```bash
argocd app sync sample-app-prod --revision 1.2.3
argocd app wait sample-app-prod --health --timeout 300
```

---

### Exercise 3: App-of-Apps Pattern

The App-of-Apps pattern lets you manage many Applications from a single parent Application. The parent points to a directory full of ArgoCD Application manifests.

#### Structure

```
argocd/
├── app-of-apps.yaml          # parent Application
└── apps/
    ├── sample-app-dev.yaml
    ├── sample-app-staging.yaml
    ├── sample-app-prod.yaml
    ├── monitoring.yaml
    └── ingress-nginx.yaml
```

```yaml
# argocd/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```bash
kubectl apply -f argocd/app-of-apps.yaml
# ArgoCD will now auto-create all Applications in argocd/apps/
argocd app list
```

Adding a new application is as simple as adding a new YAML file to `argocd/apps/` and pushing to Git.

---

## 7. Verification & Testing

### Health and Sync Status

```bash
# Get detailed application status
argocd app get sample-app

# Get all applications
argocd app list

# Get resource tree
argocd app resources sample-app

# Get diff (desired vs. live)
argocd app diff sample-app

# Get history
argocd app history sample-app
```

### kubectl Health Verification

```bash
# Verify pods are running
kubectl get pods -n sample-app

# Check deployment rollout
kubectl rollout status deployment/sample-app -n sample-app

# Check events for issues
kubectl get events -n sample-app --sort-by='.lastTimestamp'

# Describe any failing pods
kubectl describe pod -l app=sample-app -n sample-app

# Check application logs
kubectl logs -l app=sample-app -n sample-app --tail=50

# Verify service endpoints
kubectl get endpoints sample-app -n sample-app
```

### ArgoCD API Health Check

```bash
# Check ArgoCD API server health
curl -k https://localhost:8080/healthz

# Get application via API
ARGOCD_TOKEN=$(argocd account generate-token --account jenkins)
curl -k \
  -H "Authorization: Bearer ${ARGOCD_TOKEN}" \
  https://localhost:8080/api/v1/applications/sample-app | jq .status.health
```

Expected output:

```json
{
  "status": "Healthy"
}
```

### Automated Health Check Script

```bash
#!/usr/bin/env bash
# check-argocd-health.sh
APP_NAME="${1:-sample-app}"
TIMEOUT="${2:-300}"
INTERVAL=10
ELAPSED=0

echo "Waiting for ${APP_NAME} to be Healthy and Synced..."

while [ $ELAPSED -lt $TIMEOUT ]; do
    STATUS=$(argocd app get "$APP_NAME" -o json | jq -r '.status.health.status')
    SYNC=$(argocd app get "$APP_NAME" -o json | jq -r '.status.sync.status')

    echo "  Health: ${STATUS} | Sync: ${SYNC} | Elapsed: ${ELAPSED}s"

    if [ "$STATUS" = "Healthy" ] && [ "$SYNC" = "Synced" ]; then
        echo "✓ ${APP_NAME} is Healthy and Synced!"
        exit 0
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "✗ Timeout waiting for ${APP_NAME} to become healthy"
exit 1
```

---

## 8. Troubleshooting Guide

### Issue 1: `ComparisonError: failed to load target state`

**Symptom:** ArgoCD shows `OutOfSync` with an error about failing to load target state.

**Cause:** ArgoCD cannot connect to the Git repository or the path doesn't exist.

```bash
# Check repository connectivity
argocd repo list
argocd repo get https://github.com/your-org/your-repo.git

# Re-add repository with correct credentials
argocd repo add https://github.com/your-org/your-repo.git \
  --username your-username \
  --password your-token
```

---

### Issue 2: Application Stuck in `Progressing`

**Symptom:** App health shows `Progressing` indefinitely after sync.

**Cause:** Usually a pod that cannot start (image pull error, OOM, crashloop).

```bash
argocd app get sample-app
kubectl get pods -n sample-app
kubectl describe pod <pod-name> -n sample-app
kubectl logs <pod-name> -n sample-app --previous
```

Common sub-causes:
- `ErrImagePull` / `ImagePullBackOff` → image tag wrong, or pull secret missing
- `CrashLoopBackOff` → application runtime error, check logs
- `Pending` → insufficient cluster resources, check node capacity

---

### Issue 3: `PermissionDenied` When Syncing

**Symptom:** `FATA rpc error: code = PermissionDenied`

**Cause:** The logged-in user or service account lacks permission to sync the application.

```bash
# Check current user
argocd account get-user-info

# Check RBAC policy
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Login as admin to grant permissions
argocd login localhost:8080 --username admin
```

---

### Issue 4: Self-Healing Not Working

**Symptom:** Manual `kubectl` changes are not being reverted.

**Cause:** Self-heal might be disabled, or the sync window denies syncs.

```bash
argocd app get sample-app | grep -E "Sync Policy|SyncWindow"
# Ensure "Self Heal" is shown in Sync Policy

# Check sync windows
argocd app get sample-app -o json | jq '.status.sync'

# Enable self-heal
argocd app set sample-app --self-heal
```

---

### Issue 5: ArgoCD Pods Not Starting After Installation

```bash
kubectl get pods -n argocd
kubectl describe pod argocd-server-xxx -n argocd
kubectl logs argocd-server-xxx -n argocd

# Common fix: resource limits too tight for Minikube
kubectl edit deployment argocd-server -n argocd
# Reduce or remove resource limits temporarily
```

---

### Issue 6: `helm template` Errors in ArgoCD

**Symptom:** Application shows `InvalidSpecError` with Helm template rendering errors.

```bash
# Reproduce locally
helm template sample-app helm/sample-app \
  --values helm/sample-app/values.yaml \
  --values helm/sample-app/values-dev.yaml

# Check for syntax errors in values files
helm lint helm/sample-app
```

---

### Issue 7: Namespace Not Being Created

**Symptom:** App fails with `namespace "dev" not found`.

**Cause:** `CreateNamespace=true` sync option not set.

```bash
argocd app set sample-app --sync-option CreateNamespace=true
argocd app sync sample-app
```

---

### Issue 8: Pruning Deleting Resources Unexpectedly

**Symptom:** Resources that should exist are being deleted after sync.

**Cause:** The resource is no longer in the Git path, or `prune` is enabled and the resource is not tracked.

```bash
# Preview what would be pruned
argocd app diff sample-app --server-side-generate

# Disable auto-prune temporarily
argocd app set sample-app --auto-prune=false

# Add prune=false annotation to protect specific resources
kubectl annotate deployment special-deployment \
  argocd.argoproj.io/managed-by=argocd \
  -n sample-app
```

---

### Issue 9: ArgoCD UI Not Accessible

```bash
# Check argocd-server service
kubectl get svc argocd-server -n argocd

# Re-do port-forward
pkill -f "kubectl port-forward.*argocd"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Check argocd-server pod
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd
```

---

### Issue 10: Image Pull Failures for JFrog Images

**Symptom:** Pods stuck in `ImagePullBackOff` for JFrog-hosted images.

```bash
# Verify secret exists in the target namespace
kubectl get secret jfrog-registry -n dev

# Verify credentials are correct
kubectl get secret jfrog-registry -n dev -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | jq .

# Recreate secret
kubectl delete secret jfrog-registry -n dev
kubectl create secret docker-registry jfrog-registry \
  --docker-server=yourname-devops.jfrog.io \
  --docker-username="${JFROG_USER}" \
  --docker-password="${JFROG_TOKEN}" \
  --namespace=dev

# Verify image exists in JFrog
curl -u "${JFROG_USER}:${JFROG_TOKEN}" \
  "https://yourname-devops.jfrog.io/artifactory/api/docker/docker-local/v2/sample-app/tags/list"
```

---

## 9. Cheat Sheet

### CLI Quick Reference

```bash
# ─── Login ────────────────────────────────────────────────────────────────────
argocd login <SERVER>                           # interactive login
argocd login <SERVER> --auth-token <TOKEN>      # token-based login (CI/CD)
argocd logout <SERVER>                          # logout

# ─── Applications ─────────────────────────────────────────────────────────────
argocd app list                                 # list all apps
argocd app get <APP>                            # detailed status
argocd app get <APP> -o json                    # JSON output
argocd app diff <APP>                           # show diff
argocd app history <APP>                        # deployment history
argocd app sync <APP>                           # trigger sync
argocd app sync <APP> --revision <TAG>          # sync to specific revision
argocd app sync <APP> --resource apps:Deployment:myapp  # sync specific resource
argocd app wait <APP> --health --timeout 300    # wait until healthy
argocd app rollback <APP> <ID>                  # rollback to history ID
argocd app delete <APP>                         # delete application
argocd app delete <APP> --cascade               # delete app + K8s resources

# ─── Create Application ───────────────────────────────────────────────────────
argocd app create <APP> \
  --repo <REPO_URL> \
  --path <PATH> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <NS> \
  --project <PROJECT> \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true

# ─── Projects ─────────────────────────────────────────────────────────────────
argocd proj list                                # list projects
argocd proj get <PROJ>                          # project details
argocd proj create <PROJ>                       # create project

# ─── Repositories ─────────────────────────────────────────────────────────────
argocd repo list                                # list configured repos
argocd repo add <URL> --username x --password y # add HTTPS repo
argocd repo add <URL> --ssh-private-key-path ~  # add SSH repo
argocd repo rm <URL>                            # remove repo

# ─── Clusters ─────────────────────────────────────────────────────────────────
argocd cluster list                             # list registered clusters
argocd cluster add <CONTEXT>                    # register cluster
argocd cluster rm <SERVER>                      # remove cluster

# ─── Accounts ─────────────────────────────────────────────────────────────────
argocd account list                             # list users
argocd account update-password                  # change password
argocd account generate-token --account <USER>  # generate API token
argocd account get-user-info                    # current user info

# ─── Admin utilities ─────────────────────────────────────────────────────────
argocd admin settings validate                  # validate argocd-cm settings
argocd admin app generate-spec <APP>            # generate Application YAML

# ─── Context ─────────────────────────────────────────────────────────────────
argocd context                                  # show current context
argocd context <SERVER>                         # switch context
```

### Key Kubernetes Resources

```bash
# ArgoCD CRDs
kubectl get applications    -n argocd
kubectl get appprojects     -n argocd
kubectl get applicationsets -n argocd

# ArgoCD ConfigMaps
kubectl get cm argocd-cm       -n argocd -o yaml  # main config
kubectl get cm argocd-rbac-cm  -n argocd -o yaml  # RBAC config
kubectl get cm argocd-ssh-known-hosts-cm -n argocd -o yaml

# ArgoCD Secrets
kubectl get secret argocd-initial-admin-secret -n argocd
kubectl get secret argocd-secret               -n argocd
```

### Useful ArgoCD API Endpoints

```bash
BASE="https://localhost:8080/api/v1"
TOKEN="Bearer ${ARGOCD_TOKEN}"

# List applications
curl -k -H "Authorization: ${TOKEN}" "${BASE}/applications"

# Get application
curl -k -H "Authorization: ${TOKEN}" "${BASE}/applications/sample-app"

# Sync application
curl -k -X POST \
  -H "Authorization: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"revision":"main","prune":false,"dryRun":false}' \
  "${BASE}/applications/sample-app/sync"

# Get application health
curl -k -H "Authorization: ${TOKEN}" \
  "${BASE}/applications/sample-app" | jq .status.health
```

---

*Last updated: 2024 | Maintained by the DevOps Engineering Team*
