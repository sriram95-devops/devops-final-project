# Local Development Environment Setup Guide

This guide walks you through setting up a complete local DevOps workstation on **Ubuntu 22.04** or **macOS**. By the end, you will have every tool required to work with the projects in this repository.

---

## Table of Contents

1. [Hardware Requirements](#1-hardware-requirements)
2. [Operating System Preparation](#2-operating-system-preparation)
3. [Git](#3-git)
4. [Docker](#4-docker)
5. [kubectl](#5-kubectl)
6. [Minikube](#6-minikube)
7. [Kind (Kubernetes in Docker)](#7-kind-kubernetes-in-docker)
8. [Helm](#8-helm)
9. [Terraform](#9-terraform)
10. [Azure CLI](#10-azure-cli)
11. [Visual Studio Code](#11-visual-studio-code)
12. [Python 3](#12-python-3)
13. [jq and curl](#13-jq-and-curl)
14. [ArgoCD CLI](#14-argocd-cli)
15. [Flux CLI](#15-flux-cli)
16. [Shell Configuration (zsh / bash aliases)](#16-shell-configuration-zsh--bash-aliases)
17. [Start Minikube with Recommended Resources](#17-start-minikube-with-recommended-resources)
18. [JFrog Cloud Free Account Setup](#18-jfrog-cloud-free-account-setup)
19. [Azure CLI Authentication](#19-azure-cli-authentication)
20. [Verify All Tools](#20-verify-all-tools)
21. [Troubleshooting](#21-troubleshooting)

---

## 1. Hardware Requirements

Running a full local DevOps stack (Minikube, Docker, build pipelines) is resource-intensive. The table below lists the minimums and the recommended specs.

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU cores | 4 physical cores | 8+ cores (or 4 cores with hyper-threading) |
| RAM | 8 GB | 16 GB or more |
| Free disk space | 40 GB | 80 GB SSD |
| OS | Ubuntu 22.04 LTS / macOS 13+ | Ubuntu 22.04 LTS / macOS 14 Sonoma |
| Virtualization | VT-x / AMD-V enabled in BIOS | Same |

> **Why so much RAM?**  
> Minikube alone reserves 8 GB. Docker Desktop on macOS uses another 4–6 GB. Add IDE, browser, and build tooling and 16 GB becomes the comfortable floor.

### Check Your Current Resources (Linux)

```bash
# CPU info
lscpu | grep -E "^CPU\(s\)|Thread|Core|Socket"

# RAM
free -h

# Disk
df -h /
```

Expected output (example):

```
CPU(s):                  8
Thread(s) per core:      2
Core(s) per socket:      4
Socket(s):               1
              total        used        free
Mem:           15Gi        4.2Gi       9.8Gi
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        80G   22G   54G  29% /
```

### Check Your Current Resources (macOS)

```bash
sysctl -n hw.physicalcpu hw.memsize | awk 'NR==1{print "CPUs:", $1} NR==2{printf "RAM: %.0f GB\n", $1/1073741824}'
df -h /
```

---

## 2. Operating System Preparation

### Ubuntu 22.04 — System Update

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  build-essential \
  unzip \
  wget
```

Expected output (last lines):

```
Processing triggers for man-db (2.10.2-1) ...
Processing triggers for libc-bin (2.35-0ubuntu3) ...
```

### macOS — Install Homebrew

Homebrew is the package manager used for almost every tool in this guide.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the printed instructions to add Homebrew to your PATH (especially on Apple Silicon Macs):

```bash
# Apple Silicon (M1/M2/M3)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel Mac — usually already on PATH, but verify:
brew --version
```

Expected output:

```
Homebrew 4.3.x
```

Update Homebrew:

```bash
brew update && brew upgrade
```

---

## 3. Git

### Ubuntu 22.04

```bash
sudo apt-get install -y git
```

### macOS

```bash
brew install git
```

### Configure Git Identity

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global core.editor "code --wait"   # use VS Code as default editor
git config --global init.defaultBranch main
git config --global pull.rebase false
```

Verify:

```bash
git --version
git config --list --global
```

Expected output:

```
git version 2.43.0
user.name=Your Name
user.email=you@example.com
core.editor=code --wait
init.defaultbranch=main
pull.rebase=false
```

### Generate SSH Key (recommended)

```bash
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub   # copy this to GitHub / GitLab
```

---

## 4. Docker

### Ubuntu 22.04

```bash
# Remove old versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to the docker group (avoid sudo for every docker command)
sudo usermod -aG docker "$USER"
newgrp docker
```

> **Note:** Log out and back in (or run `newgrp docker`) for group changes to take effect.

### macOS

Install Docker Desktop from <https://www.docker.com/products/docker-desktop/> or via Homebrew:

```bash
brew install --cask docker
open /Applications/Docker.app
```

Wait for Docker Desktop to start (whale icon in menu bar becomes steady).

### Verify Docker

```bash
docker --version
docker compose version
docker run --rm hello-world
```

Expected output:

```
Docker version 26.1.3, build b72abbb
Docker Compose version v2.27.0
...
Hello from Docker!
```

---

## 5. kubectl

### Ubuntu 22.04

```bash
# Download latest stable release
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl kubectl.sha256
```

### macOS

```bash
brew install kubectl
```

### Verify kubectl

```bash
kubectl version --client --output=yaml
```

Expected output:

```yaml
clientVersion:
  major: "1"
  minor: "30"
  gitVersion: v1.30.x
```

### Enable kubectl Autocompletion

```bash
# bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# zsh
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
```

---

## 6. Minikube

### Ubuntu 22.04

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

### macOS

```bash
brew install minikube
```

### Verify Minikube

```bash
minikube version
```

Expected output:

```
minikube version: v1.33.x
commit: ...
```

> Minikube startup (with resources) is covered in [Section 17](#17-start-minikube-with-recommended-resources).

---

## 7. Kind (Kubernetes in Docker)

Kind (Kubernetes IN Docker) is a lightweight alternative to Minikube, especially useful in CI/CD pipelines. It runs Kubernetes nodes as Docker containers.

### Ubuntu 22.04

```bash
KIND_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### macOS

```bash
brew install kind
```

### Verify Kind

```bash
kind version
```

Expected output:

```
kind v0.23.x go1.21.x linux/amd64
```

### Create a Kind Cluster

```bash
kind create cluster --name devops-lab --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
EOF
```

Expected output:

```
Creating cluster "devops-lab" ...
 ✓ Ensuring node image (kindest/node:v1.30.x) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-devops-lab"
```

```bash
kubectl cluster-info --context kind-devops-lab
kubectl get nodes
```

### Delete Kind Cluster

```bash
kind delete cluster --name devops-lab
```

---

## 8. Helm

Helm is the Kubernetes package manager. It is required by many components in this project (ArgoCD, Prometheus, cert-manager, etc.).

### Ubuntu 22.04

```bash
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | \
  sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] \
  https://baltocdn.com/helm/stable/debian/ all main" | \
  sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm
```

### macOS

```bash
brew install helm
```

### Verify Helm

```bash
helm version
```

Expected output:

```
version.BuildInfo{Version:"v3.15.x", ...}
```

### Add Common Helm Repositories

```bash
helm repo add stable        https://charts.helm.sh/stable
helm repo add bitnami       https://charts.bitnami.com/bitnami
helm repo add argo          https://argoproj.github.io/argo-helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack      https://charts.jetstack.io
helm repo add prometheus    https://prometheus-community.github.io/helm-charts
helm repo update
```

Expected output:

```
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "argo" chart repository
...Successfully got an update from the "bitnami" chart repository
Update Complete. ⎈Happy Helming!⎈
```

---

## 9. Terraform

### Ubuntu 22.04

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
```

### macOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Verify Terraform

```bash
terraform version
```

Expected output:

```
Terraform v1.9.x
on linux_amd64
```

### Enable Tab Completion

```bash
terraform -install-autocomplete
```

---

## 10. Azure CLI

### Ubuntu 22.04

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### macOS

```bash
brew install azure-cli
```

### Verify Azure CLI

```bash
az version
```

Expected output:

```json
{
  "azure-cli": "2.61.x",
  "azure-cli-core": "2.61.x",
  "azure-cli-telemetry": "1.1.0"
}
```

> Authentication is covered in [Section 19](#19-azure-cli-authentication).

---

## 11. Visual Studio Code

### Ubuntu 22.04

```bash
sudo snap install --classic code
```

Or via apt:

```bash
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
  https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg
sudo apt-get update
sudo apt-get install -y code
```

### macOS

```bash
brew install --cask visual-studio-code
```

### Recommended VS Code Extensions

Install these once VS Code is open:

```bash
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
code --install-extension ms-azuretools.vscode-docker
code --install-extension hashicorp.terraform
code --install-extension redhat.vscode-yaml
code --install-extension ms-python.python
code --install-extension GitHub.vscode-pull-request-github
code --install-extension eamodio.gitlens
code --install-extension ms-vscode-remote.remote-containers
```

### Verify VS Code

```bash
code --version
```

Expected output:

```
1.90.x
...
```

---

## 12. Python 3

### Ubuntu 22.04

Ubuntu 22.04 ships with Python 3.10. Install additional tooling:

```bash
sudo apt-get install -y python3 python3-pip python3-venv python3-dev
```

Optionally install `pyenv` to manage multiple Python versions:

```bash
curl https://pyenv.run | bash
```

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
```

Then install a specific Python version:

```bash
pyenv install 3.12.4
pyenv global 3.12.4
```

### macOS

```bash
brew install python@3.12
# Ensure this python is first on PATH
echo 'export PATH="$(brew --prefix python@3.12)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Verify Python

```bash
python3 --version
pip3 --version
```

Expected output:

```
Python 3.12.x
pip 24.x from .../pip (python 3.12)
```

### Install Common Python Packages

```bash
pip3 install --upgrade pip
pip3 install \
  boto3 \
  azure-identity \
  azure-mgmt-resource \
  kubernetes \
  pyyaml \
  requests \
  black \
  flake8
```

---

## 13. jq and curl

`jq` is a lightweight JSON processor. `curl` is an HTTP client. Both are essential for scripting.

### Ubuntu 22.04

```bash
sudo apt-get install -y jq curl
```

### macOS

```bash
brew install jq curl
```

### Verify

```bash
jq --version
curl --version | head -1
```

Expected output:

```
jq-1.7.1
curl 8.7.1 (x86_64-pc-linux-gnu) ...
```

### Quick jq Examples

```bash
# Pretty-print JSON
echo '{"name":"devops","version":1}' | jq .

# Extract a field
kubectl get nodes -o json | jq '.items[].metadata.name'

# Filter array
kubectl get pods -o json | jq '.items[] | select(.status.phase=="Running") | .metadata.name'
```

---

## 14. ArgoCD CLI

### Ubuntu 22.04

```bash
ARGOCD_VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o /usr/local/bin/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64"
sudo chmod +x /usr/local/bin/argocd
```

### macOS

```bash
brew install argocd
```

### Verify ArgoCD CLI

```bash
argocd version --client
```

Expected output:

```
argocd: v2.11.x
  BuildDate: ...
  GoVersion: go1.21.x
```

### ArgoCD CLI Auto-completion

```bash
# bash
echo 'source <(argocd completion bash)' >> ~/.bashrc

# zsh
echo 'source <(argocd completion zsh)' >> ~/.zshrc
```

---

## 15. Flux CLI

Flux is the CNCF GitOps operator. The CLI is used to bootstrap and interact with Flux on Kubernetes.

### Ubuntu 22.04

```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

### macOS

```bash
brew install fluxcd/tap/flux
```

### Verify Flux CLI

```bash
flux --version
```

Expected output:

```
flux version 2.3.x
```

### Flux Auto-completion

```bash
# bash
echo 'source <(flux completion bash)' >> ~/.bashrc

# zsh
echo 'source <(flux completion zsh)' >> ~/.zshrc
```

---

## 16. Shell Configuration (zsh / bash aliases)

Well-crafted aliases dramatically speed up day-to-day DevOps work. Add the following blocks to your `~/.zshrc` (zsh) or `~/.bashrc` (bash).

### Install zsh + Oh My Zsh (Ubuntu, optional but recommended)

```bash
sudo apt-get install -y zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
chsh -s $(which zsh)
```

### Recommended Aliases and Functions

Create a dedicated aliases file to keep things tidy:

```bash
cat >> ~/.zshrc << 'ALIASES'

# ─── kubectl ──────────────────────────────────────────────────────────────────
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kge='kubectl get events --sort-by=".lastTimestamp"'
alias kdp='kubectl describe pod'
alias kdd='kubectl describe deployment'
alias kds='kubectl describe svc'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'
alias kctxs='kubectl config get-contexts'

# Shorthand for switching namespaces (requires kubens: brew install kubectx)
alias kn='kubens'

# ─── Helm ─────────────────────────────────────────────────────────────────────
alias h='helm'
alias hi='helm install'
alias hu='helm upgrade --install'
alias hls='helm list'
alias hlsa='helm list --all-namespaces'
alias hrb='helm rollback'
alias hh='helm history'
alias hst='helm status'

# ─── Docker ───────────────────────────────────────────────────────────────────
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias dex='docker exec -it'
alias dl='docker logs'
alias dlf='docker logs -f'
alias dpr='docker pull'
alias dpu='docker push'
alias db='docker build'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'

# ─── Git ──────────────────────────────────────────────────────────────────────
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gco='git checkout'
alias gcb='git checkout -b'
alias glog='git log --oneline --graph --decorate --all'
alias gd='git diff'
alias gds='git diff --staged'

# ─── ArgoCD ───────────────────────────────────────────────────────────────────
alias acd='argocd'
alias acdas='argocd app sync'
alias acdag='argocd app get'
alias acdal='argocd app list'

# ─── Terraform ────────────────────────────────────────────────────────────────
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfw='terraform workspace'

# ─── Minikube ─────────────────────────────────────────────────────────────────
alias mk='minikube'
alias mks='minikube status'
alias mkstart='minikube start'
alias mkstop='minikube stop'
alias mkdash='minikube dashboard'

# ─── Azure CLI ────────────────────────────────────────────────────────────────
alias azl='az login'
alias azac='az account'
alias azaks='az aks'

# ─── Utility functions ────────────────────────────────────────────────────────

# Switch Kubernetes context interactively (requires fzf)
kctxi() {
  kubectl config use-context "$(kubectl config get-contexts -o name | fzf)"
}

# Tail pod logs matching a pattern
klgrep() {
  kubectl logs -f "$(kubectl get pods | grep "$1" | awk '{print $1}' | head -1)"
}

# Port-forward a pod on a given port
kpf() {
  # Usage: kpf <pod-name-pattern> <local-port>:<remote-port>
  kubectl port-forward "$(kubectl get pods | grep "$1" | awk '{print $1}' | head -1)" "$2"
}

# Get all resource types in a namespace
kall() {
  kubectl api-resources --verbs=list --namespaced -o name | \
    xargs -I{} kubectl get {} --ignore-not-found -n "${1:-default}"
}

ALIASES

source ~/.zshrc
```

For **bash**, replace `~/.zshrc` with `~/.bashrc` throughout.

### Install kubectx / kubens (optional but highly recommended)

```bash
# Ubuntu
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens  /usr/local/bin/kubens

# macOS
brew install kubectx
```

---

## 17. Start Minikube with Recommended Resources

This section starts Minikube with the 4 CPU / 8 GB RAM configuration needed for running ArgoCD, Jenkins, and Prometheus concurrently.

### Choose a Driver

| Driver | Ubuntu | macOS | Notes |
|--------|--------|-------|-------|
| `docker` | ✅ Recommended | ✅ Works | No separate VM, uses Docker |
| `virtualbox` | ✅ | ✅ | Requires VirtualBox install |
| `kvm2` | ✅ Linux only | ❌ | Native KVM, best performance |
| `hyperkit` | ❌ | ✅ Intel only | Deprecated |
| `qemu` | ✅ | ✅ M1/M2/M3 | Best for Apple Silicon |

### Start Minikube

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --kubernetes-version=stable \
  --addons=ingress,dashboard,metrics-server,registry \
  --profile=devops-lab
```

> Replace `--driver=docker` with `--driver=qemu2` on Apple Silicon Macs.

Expected output:

```
😄  [devops-lab] minikube v1.33.x on Ubuntu 22.04
✨  Using the docker driver based on user configuration
📌  Using Docker driver with root privileges
👍  Starting "devops-lab" primary control-plane node in "devops-lab" cluster
🚜  Pulling base image v0.0.44 ...
🔥  Creating docker container (CPUs=4, Memory=8192MB) ...
🐳  Preparing Kubernetes v1.30.x on Docker 26.0.x ...
    ▪ Generating certificates and keys ...
    ▪ Booting up control plane ...
    ▪ Configuring RBAC rules ...
🔗  Configuring bridge CNI (Container Networking Interface) ...
🔎  Verifying Kubernetes components...
    ▪ Using image gcr.io/k8s-minikube/storage-provisioner:v5
    ▪ Using image registry.k8s.io/ingress-nginx/controller:v1.10.1
    ▪ Using image docker.io/kubernetesui/dashboard:v2.7.0
    ▪ Using image registry.k8s.io/metrics-server/metrics-server:v0.7.1
🌟  Enabled addons: storage-provisioner, default-storageclass, ingress, dashboard, metrics-server
🏄  Done! kubectl is now configured to use "devops-lab" profile and "default" namespace by default
```

### Verify the Cluster

```bash
kubectl get nodes
kubectl get pods --all-namespaces
minikube status --profile=devops-lab
```

Expected output:

```
NAME        STATUS   ROLES           AGE   VERSION
devops-lab  Ready    control-plane   2m    v1.30.x

NAMESPACE              NAME                                        READY   STATUS    RESTARTS
kube-system            coredns-xxx                                 1/1     Running   0
kube-system            etcd-devops-lab                             1/1     Running   0
ingress-nginx          ingress-nginx-controller-xxx                1/1     Running   0
kubernetes-dashboard   kubernetes-dashboard-xxx                    1/1     Running   0
```

### Access the Dashboard

```bash
minikube dashboard --profile=devops-lab &
# Opens browser automatically, or use the printed URL
```

### Manage Minikube Profiles

```bash
# List all profiles
minikube profile list

# Stop the cluster (preserves state)
minikube stop --profile=devops-lab

# Delete the cluster entirely
minikube delete --profile=devops-lab

# Switch kubectl to the devops-lab profile
kubectl config use-context devops-lab
```

---

## 18. JFrog Cloud Free Account Setup

JFrog Artifactory is used in this project as the Docker image registry. The free tier (JFrog Cloud) gives you unlimited storage for 14 days then transitions to a limited free plan.

### Step 1: Create an Account

1. Navigate to <https://jfrog.com/start-free/>
2. Choose **JFrog Cloud (SaaS)** → **Free Forever**
3. Fill in your details, select the **AWS** cloud provider and a region near you
4. Choose a unique **Server Name** (e.g., `yourname-devops`) — this becomes part of your registry URL: `yourname-devops.jfrog.io`
5. Verify your email and log in to the JFrog Platform UI

### Step 2: Create a Docker Repository

1. In the JFrog UI, go to **Administration → Repositories → Repositories**
2. Click **Add Repositories → Local Repository**
3. Choose **Docker** as the package type
4. Set **Repository Key** to `docker-local`
5. Click **Save & Finish**

### Step 3: Create an Access Token

1. Go to **Administration → Identity and Access → Access Tokens**
2. Click **Generate Token**
3. Set **Token Scope** to **Admin**
4. Set an expiry (or leave 0 for no expiry)
5. Copy the generated token — you will not see it again

### Step 4: Configure Docker to Use JFrog Registry

```bash
# Replace <SERVER_NAME> with your JFrog server name
export JFROG_SERVER="yourname-devops.jfrog.io"
export JFROG_USER="your-email@example.com"
export JFROG_TOKEN="your-access-token-here"

docker login "${JFROG_SERVER}" \
  --username "${JFROG_USER}" \
  --password "${JFROG_TOKEN}"
```

Expected output:

```
WARNING! Using --password via the CLI is insecure. Use --password-stdin.
Login Succeeded
```

More secure login:

```bash
echo "${JFROG_TOKEN}" | docker login "${JFROG_SERVER}" \
  --username "${JFROG_USER}" \
  --password-stdin
```

### Step 5: Push a Test Image

```bash
docker pull nginx:alpine
docker tag nginx:alpine "${JFROG_SERVER}/docker-local/nginx:alpine-test"
docker push "${JFROG_SERVER}/docker-local/nginx:alpine-test"
```

Expected output:

```
The push refers to repository [yourname-devops.jfrog.io/docker-local/nginx]
alpine-test: digest: sha256:... size: 1234
```

Verify the image exists in the JFrog UI: **Artifactory → Artifacts → docker-local → nginx**.

### Step 6: Store Credentials as Environment Variables

Add to your `~/.zshrc` or `~/.bashrc` (never commit secrets to git):

```bash
cat >> ~/.zshrc << 'EOF'
# JFrog Artifactory
export JFROG_SERVER="yourname-devops.jfrog.io"
export JFROG_USER="your-email@example.com"
# Load token from a secrets file, not inline
[ -f ~/.secrets/jfrog_token ] && export JFROG_TOKEN=$(cat ~/.secrets/jfrog_token)
EOF

mkdir -p ~/.secrets
chmod 700 ~/.secrets
echo "your-access-token-here" > ~/.secrets/jfrog_token
chmod 600 ~/.secrets/jfrog_token
```

### Step 7: Create Kubernetes Image Pull Secret

When Kubernetes needs to pull images from JFrog, create a pull secret:

```bash
kubectl create secret docker-registry jfrog-registry-secret \
  --docker-server="${JFROG_SERVER}" \
  --docker-username="${JFROG_USER}" \
  --docker-password="${JFROG_TOKEN}" \
  --namespace=default
```

Reference this secret in your pod specs:

```yaml
spec:
  imagePullSecrets:
    - name: jfrog-registry-secret
  containers:
    - name: app
      image: yourname-devops.jfrog.io/docker-local/myapp:1.0.0
```

---

## 19. Azure CLI Authentication

### Login Interactively

```bash
az login
```

This opens a browser window for authentication. After logging in:

```
[
  {
    "cloudName": "AzureCloud",
    "homeTenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "isDefault": true,
    "name": "My Azure Subscription",
    "state": "Enabled",
    "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "user": {
      "name": "you@example.com",
      "type": "user"
    }
  }
]
```

### Login with a Service Principal (CI/CD)

```bash
az login \
  --service-principal \
  --username "${AZURE_CLIENT_ID}" \
  --password "${AZURE_CLIENT_SECRET}" \
  --tenant  "${AZURE_TENANT_ID}"
```

### Set the Default Subscription

```bash
# List subscriptions
az account list --output table

# Set default
az account set --subscription "My Azure Subscription"

# Verify
az account show --output table
```

### Create a Resource Group for the Lab

```bash
az group create \
  --name rg-devops-lab \
  --location eastus

az group list --output table
```

### Configure AKS kubeconfig

```bash
# After creating an AKS cluster
az aks get-credentials \
  --resource-group rg-devops-lab \
  --name aks-devops-lab \
  --overwrite-existing

kubectl config get-contexts
```

---

## 20. Verify All Tools

Run this comprehensive check to confirm every tool is installed and meets the minimum version requirement.

```bash
#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    pass "$name: $(eval "$cmd" 2>&1 | head -1)"
  else
    fail "$name: NOT FOUND or error"
  fi
}

echo "═══════════════════════════════════════════════"
echo "   DevOps Toolchain Verification"
echo "═══════════════════════════════════════════════"
echo ""

check "Git"         "git --version"
check "Docker"      "docker --version"
check "kubectl"     "kubectl version --client --short 2>/dev/null || kubectl version --client"
check "Minikube"    "minikube version"
check "Kind"        "kind version"
check "Helm"        "helm version --short"
check "Terraform"   "terraform version | head -1"
check "Azure CLI"   "az version --query '\"azure-cli\"' -o tsv"
check "VS Code"     "code --version | head -1"
check "Python"      "python3 --version"
check "pip"         "pip3 --version"
check "jq"          "jq --version"
check "curl"        "curl --version | head -1"
check "ArgoCD CLI"  "argocd version --client --short 2>/dev/null | head -1"
check "Flux CLI"    "flux --version"

echo ""
echo "═══════════════════════════════════════════════"
```

Save the above as `verify-tools.sh` and run it:

```bash
chmod +x verify-tools.sh
./verify-tools.sh
```

Expected output when everything is installed:

```
═══════════════════════════════════════════════
   DevOps Toolchain Verification
═══════════════════════════════════════════════

✓ Git: git version 2.43.0
✓ Docker: Docker version 26.1.3, build b72abbb
✓ kubectl: Client Version: v1.30.x
✓ Minikube: minikube version: v1.33.x
✓ Kind: kind v0.23.x go1.21.x linux/amd64
✓ Helm: v3.15.x
✓ Terraform: Terraform v1.9.x
✓ Azure CLI: 2.61.x
✓ VS Code: 1.90.x
✓ Python: Python 3.12.x
✓ pip: pip 24.x
✓ jq: jq-1.7.1
✓ curl: curl 8.7.1
✓ ArgoCD CLI: argocd: v2.11.x
✓ Flux CLI: flux version 2.3.x

═══════════════════════════════════════════════
```

---

## 21. Troubleshooting

### Docker

#### Issue: `permission denied while trying to connect to the Docker daemon socket`

**Cause:** Your user is not in the `docker` group.

```bash
# Check groups
groups $USER

# Add user to docker group
sudo usermod -aG docker $USER

# Apply immediately (no logout needed)
newgrp docker

# Verify
docker ps
```

#### Issue: `Error response from daemon: driver failed programming external connectivity`

**Cause:** Port conflict or iptables issue.

```bash
sudo systemctl restart docker
# If that fails:
sudo iptables -F && sudo iptables -X
sudo systemctl restart docker
```

#### Issue: Docker out of disk space

```bash
# Remove dangling images, stopped containers, unused networks
docker system prune -f

# Remove all unused images (more aggressive)
docker system prune -a -f

# Check disk usage
docker system df
```

---

### Minikube

#### Issue: `minikube start` fails with `Exiting due to PROVIDER_DOCKER_NOT_RUNNING`

```bash
# Start Docker
sudo systemctl start docker

# Verify Docker is running
docker ps

# Retry
minikube start --driver=docker --profile=devops-lab
```

#### Issue: `Exiting due to GUEST_MISSING_CONNTRACK`

```bash
sudo apt-get install -y conntrack
```

#### Issue: Minikube not enough memory

```bash
minikube stop --profile=devops-lab
minikube delete --profile=devops-lab
minikube start --driver=docker --cpus=4 --memory=8192 --profile=devops-lab
```

#### Issue: `kubectl` uses wrong context after Minikube restart

```bash
# View all contexts
kubectl config get-contexts

# Switch to Minikube context
kubectl config use-context devops-lab

# Or use the minikube helper
minikube update-context --profile=devops-lab
```

---

### kubectl

#### Issue: `Unable to connect to the server: dial tcp ... connection refused`

```bash
# Check if minikube is running
minikube status --profile=devops-lab

# If stopped, start it
minikube start --profile=devops-lab

# Check kubeconfig
kubectl config view
cat ~/.kube/config | grep server
```

#### Issue: `error: the server doesn't have a resource type "pods"`

**Cause:** Namespace mismatch or API server connection issue.

```bash
kubectl cluster-info
kubectl get namespaces
kubectl get pods -n kube-system
```

---

### Helm

#### Issue: `Error: Kubernetes cluster unreachable`

```bash
kubectl cluster-info
helm env | grep KUBECONFIG
export KUBECONFIG=~/.kube/config
helm list
```

#### Issue: `Error: INSTALLATION FAILED: cannot re-use a name that is still in use`

```bash
helm list --all-namespaces
helm uninstall <release-name> -n <namespace>
# or upgrade instead
helm upgrade --install <release-name> <chart>
```

---

### Azure CLI

#### Issue: `az login` opens browser but hangs

```bash
# Use device code flow instead
az login --use-device-code
```

Follow the printed instructions to open the URL and enter the code manually.

#### Issue: `No subscriptions found`

```bash
az account list --all
az account set --subscription "<subscription-id>"
```

---

### ArgoCD CLI

#### Issue: `FATA[0000] dial tcp ... connect: connection refused`

ArgoCD server is not accessible from your machine.

```bash
# Check argocd-server pod is running
kubectl get pods -n argocd

# Port-forward the server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Set the server
argocd login localhost:8080 --insecure
```

---

### JFrog / Docker Login

#### Issue: `unauthorized: The client does not have permission to push to this repository`

```bash
# Verify login credentials
docker logout yourname-devops.jfrog.io
echo "${JFROG_TOKEN}" | docker login yourname-devops.jfrog.io \
  --username "${JFROG_USER}" --password-stdin

# Verify repository key matches
# In JFrog UI: Administration → Repositories → check repository key
# Your push path must be: <server>/<repo-key>/<image>:<tag>
```

#### Issue: `x509: certificate signed by unknown authority`

```bash
# Add JFrog certificate to trusted store (Ubuntu)
curl -fsSL "https://yourname-devops.jfrog.io/artifactory/api/v1/system/certificates" \
  | sudo tee /usr/local/share/ca-certificates/jfrog.crt
sudo update-ca-certificates
sudo systemctl restart docker
```

---

### Terraform

#### Issue: `Error: Required plugins are not installed`

```bash
terraform init
terraform init -upgrade
```

#### Issue: `Error acquiring the state lock`

```bash
# Check who holds the lock
terraform force-unlock <LOCK_ID>
```

---

### General Connectivity Issues

#### Check DNS resolution

```bash
nslookup google.com
dig google.com
```

#### Check proxy settings

```bash
env | grep -i proxy
# If behind a corporate proxy, set:
export HTTP_PROXY=http://proxy.corp.com:8080
export HTTPS_PROXY=http://proxy.corp.com:8080
export NO_PROXY=localhost,127.0.0.1,.local
```

#### Check firewall (Ubuntu)

```bash
sudo ufw status
sudo ufw allow 8080/tcp   # example: allow ArgoCD port
```

---

## Quick Reference Card

```
Tool        | Version Check         | Install Docs
────────────┼───────────────────────┼──────────────────────────────────────────────
git         | git --version         | https://git-scm.com/downloads
docker      | docker --version      | https://docs.docker.com/engine/install/
kubectl     | kubectl version       | https://kubernetes.io/docs/tasks/tools/
minikube    | minikube version      | https://minikube.sigs.k8s.io/docs/start/
kind        | kind version          | https://kind.sigs.k8s.io/docs/user/quick-start/
helm        | helm version          | https://helm.sh/docs/intro/install/
terraform   | terraform version     | https://developer.hashicorp.com/terraform/install
az          | az version            | https://learn.microsoft.com/cli/azure/install-azure-cli
code        | code --version        | https://code.visualstudio.com/download
python3     | python3 --version     | https://www.python.org/downloads/
jq          | jq --version          | https://jqlang.github.io/jq/download/
curl        | curl --version        | (usually pre-installed)
argocd      | argocd version        | https://argo-cd.readthedocs.io/en/stable/cli_installation/
flux        | flux --version        | https://fluxcd.io/flux/installation/
```

---

*Last updated: 2024 | Maintained by the DevOps Engineering Team*
