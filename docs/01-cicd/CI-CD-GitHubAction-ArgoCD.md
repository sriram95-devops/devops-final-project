# 🚀 CI/CD Setup: GitHub Actions + ArgoCD (Dev / Test / Stage)

## 📁 Repository Structure

```
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI pipeline
├── k8s/
│   ├── dev/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── test/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── stage/
│       ├── deployment.yaml
│       └── service.yaml
├── Dockerfile
└── CICD-ARGOCD-SETUP.md
```

---

## 🐳 Part 1 — GitHub Actions CI Pipeline

### 📌 Overview
GitHub Actions will:
1. Build the Docker image
2. Push it to Docker Hub
3. Update the image tag in the Kubernetes manifests in the repo

---

### 🔐 Step 1 — Add Secrets to GitHub Repository

#### ➤ Via GitHub UI
1. Go to your repo → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** and add:

| Secret Name            | Value                          |
|------------------------|-------------------------------|
| `DOCKERHUB_USERNAME`   | Your Docker Hub username       |
| `DOCKERHUB_TOKEN`      | Docker Hub Access Token (PAT)  |
| `GH_PAT`               | GitHub Personal Access Token   |

> **To create a Docker Hub token:** Docker Hub → Account Settings → Security → New Access Token
> 
> **To create a GitHub PAT:** GitHub → Settings → Developer settings → Personal access tokens → Fine-grained or Classic (needs `repo` scope)

#### ➤ Via GitHub CLI
```bash
# Authenticate GitHub CLI
gh auth login

# Add Docker Hub secrets
gh secret set DOCKERHUB_USERNAME --body "your-dockerhub-username" --repo <owner>/<repo>
gh secret set DOCKERHUB_TOKEN    --body "your-dockerhub-token"    --repo <owner>/<repo>

# Add GitHub PAT (used to push image tag updates back to the repo)
gh secret set GH_PAT             --body "your-github-pat"         --repo <owner>/<repo>

# Verify secrets
gh secret list --repo <owner>/<repo>
```

---

### ⚙️ Step 2 — GitHub Actions Workflow

```yaml name=.github/workflows/ci.yml
name: CI — Build, Push & Update Image Tag

on:
  push:
    branches:
      - main

env:
  DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
  IMAGE_NAME: ${{ secrets.DOCKERHUB_USERNAME }}/your-app-name

jobs:
  build-push-update:
    runs-on: ubuntu-latest

    steps:
      # 1. Checkout source code
      - name: Checkout Code
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GH_PAT }}   # needed to push image tag update back

      # 2. Set image tag from short SHA
      - name: Set Image Tag
        id: vars
        run: echo "IMAGE_TAG=${GITHUB_SHA::8}" >> $GITHUB_OUTPUT

      # 3. Log in to Docker Hub
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      # 4. Build and push Docker image
      - name: Build and Push Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:${{ steps.vars.outputs.IMAGE_TAG }}
            ${{ env.IMAGE_NAME }}:latest

      # 5. Update image tag in k8s manifests (dev, test, stage)
      - name: Update Image Tag in Manifests
        run: |
          IMAGE_TAG=${{ steps.vars.outputs.IMAGE_TAG }}
          for ENV in dev test stage; do
            sed -i "s|image: .*|image: ${{ env.IMAGE_NAME }}:${IMAGE_TAG}|g" k8s/${ENV}/deployment.yaml
          done

      # 6. Commit and push updated manifests
      - name: Commit Updated Manifests
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/
          git commit -m "ci: update image tag to ${{ steps.vars.outputs.IMAGE_TAG }}" || echo "No changes to commit"
          git push
```

---

### 📄 Step 3 — Sample Kubernetes Deployment Manifest

```yaml name=k8s/dev/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: your-app
  template:
    metadata:
      labels:
        app: your-app
    spec:
      containers:
        - name: your-app
          image: your-dockerhub-username/your-app-name:latest   # ← updated by CI
          ports:
            - containerPort: 3000
```

> Same pattern applies for `k8s/test/deployment.yaml` and `k8s/stage/deployment.yaml` — just change the `namespace`.

---

## 🔄 Part 2 — ArgoCD Setup (Dev / Test / Stage)

### 📌 Overview
ArgoCD will:
1. Watch the GitHub repo (`k8s/dev`, `k8s/test`, `k8s/stage` folders)
2. Detect image tag changes committed by GitHub Actions
3. Automatically sync and deploy to the matching environment

---

### 🔐 Step 4 — Connect ArgoCD to GitHub (Private Repo)

#### ➤ Via ArgoCD UI
1. Open ArgoCD → **Settings** → **Repositories** → **Connect Repo**
2. Choose **HTTPS** method
3. Fill in:
   - **Repository URL:** `https://github.com/<owner>/<repo>.git`
   - **Username:** your GitHub username
   - **Password:** your GitHub PAT (same `GH_PAT` created above)
4. Click **Connect** — a green ✅ confirms success

#### ➤ Via ArgoCD CLI
```bash
# Login to ArgoCD
argocd login <ARGOCD_SERVER> --username admin --password <ARGOCD_ADMIN_PASSWORD>

# Add private GitHub repo using HTTPS + PAT
argocd repo add https://github.com/<owner>/<repo>.git \
  --username <your-github-username> \
  --password <your-github-pat>

# Verify repo is connected
argocd repo list
```

---

### 🔐 Step 5 — Add Docker Hub Image Pull Secret to Kubernetes

ArgoCD deploys pods — if your Docker Hub image is private, the cluster needs pull credentials.

#### ➤ Via kubectl (CLI) — apply to each namespace
```bash
for NS in dev test stage; do
  # Create namespace if not existing
  kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

  # Create Docker Hub pull secret
  kubectl create secret docker-registry dockerhub-pull-secret \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username=<DOCKERHUB_USERNAME> \
    --docker-password=<DOCKERHUB_TOKEN> \
    --docker-email=<YOUR_EMAIL> \
    --namespace=$NS
done
```

#### ➤ Reference the secret in your deployment
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: dockerhub-pull-secret
      containers:
        - name: your-app
          image: your-dockerhub-username/your-app-name:latest
```

#### ➤ Via Kubernetes Dashboard (UI)
1. Go to **Workloads** → Select namespace (`dev` / `test` / `stage`)
2. **Config and Storage** → **Secrets** → **Create Secret**
3. Type: `kubernetes.io/dockerconfigjson`
4. Paste the encoded `.dockerconfigjson` value

---

### 📦 Step 6 — Create ArgoCD Applications (Dev / Test / Stage)

#### ➤ Via ArgoCD UI
1. ArgoCD → **New App**
2. Fill in for each environment:

| Field               | Dev                          | Test                          | Stage                          |
|---------------------|------------------------------|-------------------------------|-------------------------------|
| App Name            | `your-app-dev`               | `your-app-test`               | `your-app-stage`              |
| Project             | `default`                    | `default`                     | `default`                     |
| Sync Policy         | `Automatic`                  | `Automatic`                   | `Automatic`                   |
| Repo URL            | `https://github.com/<o>/<r>` | `https://github.com/<o>/<r>`  | `https://github.com/<o>/<r>`  |
| Revision            | `HEAD`                       | `HEAD`                        | `HEAD`                        |
| Path                | `k8s/dev`                    | `k8s/test`                    | `k8s/stage`                   |
| Cluster URL         | `https://kubernetes.default.svc` | same                      | same                          |
| Namespace           | `dev`                        | `test`                        | `stage`                       |

3. Enable **Auto-sync** + **Prune** + **Self-heal** → Click **Create**

#### ➤ Via ArgoCD CLI
```bash
# DEV
argocd app create your-app-dev \
  --repo https://github.com/<owner>/<repo>.git \
  --path k8s/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# TEST
argocd app create your-app-test \
  --repo https://github.com/<owner>/<repo>.git \
  --path k8s/test \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace test \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# STAGE
argocd app create your-app-stage \
  --repo https://github.com/<owner>/<repo>.git \
  --path k8s/stage \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace stage \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Verify all apps
argocd app list
```

#### ➤ Via YAML (declarative — recommended for GitOps)
```yaml name=k8s/argocd-apps/dev-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: your-app-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<owner>/<repo>.git
    targetRevision: HEAD
    path: k8s/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
> Repeat with `k8s/test` and `k8s/stage` paths for the other environments.

```bash
# Apply all ArgoCD app definitions
kubectl apply -f k8s/argocd-apps/
```

---

## 🔁 End-to-End Flow Summary

```
Developer pushes code to main branch
        │
        ▼
GitHub Actions triggers
        │
        ├─► Builds Docker image
        ├─► Pushes image to Docker Hub  ← uses DOCKERHUB_TOKEN secret
        ├─► Tags image with short Git SHA
        └─► Updates image tag in k8s/dev|test|stage/deployment.yaml
                    │
                    ▼
            Commits & pushes manifest change to GitHub repo
                    │
                    ▼
            ArgoCD detects change in repo  ← connected via GitHub PAT
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    Syncs DEV   Syncs TEST  Syncs STAGE
    namespace   namespace   namespace
```

---

## 🔑 Credentials Summary

| Credential              | Where Stored             | Used By            |
|-------------------------|--------------------------|--------------------|
| `DOCKERHUB_USERNAME`    | GitHub Repo Secret       | GitHub Actions     |
| `DOCKERHUB_TOKEN`       | GitHub Repo Secret       | GitHub Actions     |
| `GH_PAT`                | GitHub Repo Secret       | GitHub Actions (push manifest update) |
| GitHub PAT              | ArgoCD Repo Settings     | ArgoCD (pull manifests) |
| `dockerhub-pull-secret` | Kubernetes Secret (each ns) | Kubelet (pull image) |

---

## ✅ Verification Checklist

- [ ] Docker Hub token created and saved as `DOCKERHUB_TOKEN` in GitHub Secrets
- [ ] GitHub PAT saved as `GH_PAT` in GitHub Secrets
- [ ] GitHub Actions workflow runs successfully on push to `main`
- [ ] Image appears in Docker Hub after pipeline run
- [ ] `k8s/dev/deployment.yaml` image tag is updated after pipeline run
- [ ] ArgoCD repo connected (green status in Settings → Repositories)
- [ ] `dockerhub-pull-secret` created in `dev`, `test`, `stage` namespaces
- [ ] ArgoCD apps (`your-app-dev`, `your-app-test`, `your-app-stage`) are Synced ✅
- [ ] Pods running in all 3 namespaces after a push
