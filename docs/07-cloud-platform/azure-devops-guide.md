# Azure DevOps Guide — AKS, ACR, Key Vault, Azure Monitor

## 1. Overview & Why You Need It

Azure provides a complete cloud platform for DevOps engineers. Key services:

| Service | Role |
|---------|------|
| **AKS** | Managed Kubernetes cluster |
| **ACR** | Container image registry |
| **Azure Key Vault** | Secrets management |
| **Azure Monitor** | Metrics, logs, alerts |
| **Azure Pipelines** | CI/CD (alternative to Jenkins) |
| **Azure AD** | Identity and access management |

**Why Azure for this stack?**
- AKS = managed K8s (no control plane to manage)
- ACR integrates natively with AKS
- Key Vault CSI driver mounts secrets directly into pods
- Azure Monitor + Container Insights gives instant K8s observability

---

## 2. Prerequisites & Local Setup

### Install Azure CLI

```bash
# Ubuntu
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# macOS
brew install azure-cli

# Verify
az version
# Expected: {"azure-cli": "2.x.x", ...}
```

### Authenticate

```bash
# Interactive login
az login
# Opens browser, select your account

# List subscriptions
az account list --output table

# Set default subscription
az account set --subscription "My Subscription Name"

# Verify
az account show
```

### Create Service Principal (for automation)

```bash
# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "sp-devops-jenkins" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth

# Expected output (save this JSON for Jenkins/Terraform):
# {
#   "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
#   "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }
```

---

## 3. AKS — Azure Kubernetes Service

### Create AKS Cluster

```bash
# Create Resource Group
az group create \
  --name rg-devops \
  --location eastus

# Create AKS cluster
az aks create \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-addons monitoring \
  --enable-managed-identity \
  --generate-ssh-keys \
  --kubernetes-version 1.28.0

# Get kubectl credentials
az aks get-credentials \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --overwrite-existing

# Verify
kubectl get nodes
# Expected:
# NAME                                STATUS   ROLES   AGE   VERSION
# aks-nodepool1-12345678-vmss000000   Ready    agent   2m    v1.28.0
# aks-nodepool1-12345678-vmss000001   Ready    agent   2m    v1.28.0
# aks-nodepool1-12345678-vmss000002   Ready    agent   2m    v1.28.0
```

### Scale Node Pool

```bash
# Scale to 5 nodes
az aks scale \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --node-count 5

# Add a new node pool (for GPU workloads)
az aks nodepool add \
  --resource-group rg-devops \
  --cluster-name aks-devops-cluster \
  --name gpupool \
  --node-count 2 \
  --node-vm-size Standard_NC6
```

### Enable Cluster Autoscaler

```bash
az aks update \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10
```

### AKS with RBAC + Azure AD Integration

```bash
# Enable Azure AD integration
az aks update \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --enable-aad \
  --aad-admin-group-object-ids <GROUP_ID>

# Create namespace with RBAC
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace prod
```

---

## 4. ACR — Azure Container Registry

### Create ACR

```bash
# Create registry (Premium for geo-replication, Standard for most uses)
az acr create \
  --resource-group rg-devops \
  --name acrdevops001 \
  --sku Standard \
  --location eastus

# Verify
az acr show --name acrdevops001 --query loginServer
# Expected: "acrdevops001.azurecr.io"
```

### Push/Pull Images

```bash
# Login to ACR
az acr login --name acrdevops001

# Tag local image
docker tag myapp:latest acrdevops001.azurecr.io/myapp:1.0.0

# Push
docker push acrdevops001.azurecr.io/myapp:1.0.0

# List images
az acr repository list --name acrdevops001 --output table

# Pull
docker pull acrdevops001.azurecr.io/myapp:1.0.0
```

### Attach ACR to AKS

```bash
# Attach (grants AKS managed identity pull access to ACR)
az aks update \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --attach-acr acrdevops001

# Verify (AKS can now pull from ACR without imagePullSecret)
kubectl run test-acr \
  --image=acrdevops001.azurecr.io/myapp:1.0.0 \
  --restart=Never
kubectl get pod test-acr
```

### ACR Task (Build in Cloud)

```bash
# Build and push without local Docker
az acr build \
  --registry acrdevops001 \
  --image myapp:1.0.0 \
  --file Dockerfile .

# ACR auto-build on git push
az acr task create \
  --registry acrdevops001 \
  --name build-on-commit \
  --image "myapp:{{.Run.ID}}" \
  --context https://github.com/org/repo.git \
  --file Dockerfile \
  --git-access-token <GITHUB_PAT>
```

---

## 5. Azure Key Vault

### Create Key Vault

```bash
# Create Key Vault
az keyvault create \
  --name kv-devops-secrets \
  --resource-group rg-devops \
  --location eastus \
  --enable-rbac-authorization true

# Add secrets
az keyvault secret set \
  --vault-name kv-devops-secrets \
  --name "db-password" \
  --value "SuperSecretP@ssw0rd"

az keyvault secret set \
  --vault-name kv-devops-secrets \
  --name "jfrog-password" \
  --value "JFrogArtifactoryToken123"

# Read secret
az keyvault secret show \
  --vault-name kv-devops-secrets \
  --name "db-password" \
  --query value -o tsv
```

### Mount Key Vault Secrets in K8s (CSI Driver)

```bash
# Install Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true

# Install Azure Key Vault provider
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install azure-csi-provider csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  --namespace kube-system
```

**SecretProviderClass YAML:**

```yaml
# secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault-secrets           # Name of this provider config
  namespace: default
spec:
  provider: azure                         # Use Azure Key Vault provider
  parameters:
    usePodIdentity: "false"               # Use managed identity, not pod identity
    useVMManagedIdentity: "true"          # Use AKS node managed identity
    userAssignedIdentityID: ""            # Leave empty for system-assigned identity
    keyvaultName: "kv-devops-secrets"     # Your Key Vault name
    cloudName: ""                         # AzurePublicCloud by default
    objects: |
      array:
        - |
          objectName: db-password         # Secret name in Key Vault
          objectType: secret              # Type: secret, key, or cert
          objectVersion: ""              # Empty = latest version
        - |
          objectName: jfrog-password
          objectType: secret
          objectVersion: ""
    tenantId: "YOUR-TENANT-ID"           # Your Azure AD tenant ID
  secretObjects:                          # Sync to K8s Secret
  - secretName: app-secrets              # K8s Secret name to create
    type: Opaque
    data:
    - objectName: db-password
      key: DB_PASSWORD
    - objectName: jfrog-password
      key: JFROG_PASSWORD
```

**Pod using Key Vault secrets:**

```yaml
# pod-with-secrets.yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: app
    image: acrdevops001.azurecr.io/myapp:1.0.0
    env:
    - name: DB_PASSWORD                   # Env var in container
      valueFrom:
        secretKeyRef:
          name: app-secrets               # K8s Secret synced from Key Vault
          key: DB_PASSWORD
    volumeMounts:
    - name: secrets-vol
      mountPath: "/mnt/secrets"           # Mount path in container
      readOnly: true
  volumes:
  - name: secrets-vol
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "azure-keyvault-secrets"
```

```bash
kubectl apply -f secret-provider-class.yaml
kubectl apply -f pod-with-secrets.yaml

# Verify secret is mounted
kubectl exec myapp -- cat /mnt/secrets/db-password
```

---

## 6. Azure Monitor + Container Insights

### Enable Container Insights on AKS

```bash
# Enable during creation (already included in section 3)
# OR enable on existing cluster:
az aks enable-addons \
  --resource-group rg-devops \
  --name aks-devops-cluster \
  --addons monitoring \
  --workspace-resource-id /subscriptions/<SUB_ID>/resourceGroups/rg-devops/providers/Microsoft.OperationalInsights/workspaces/law-devops

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group rg-devops \
  --workspace-name law-devops \
  --location eastus
```

### Query Container Logs (KQL)

```kusto
-- Pod logs from all namespaces
ContainerLog
| where TimeGenerated > ago(1h)
| where Namespace == "default"
| project TimeGenerated, PodName, ContainerName, LogEntry
| order by TimeGenerated desc

-- Failed pods in last 24h
KubePodInventory
| where TimeGenerated > ago(24h)
| where PodStatus == "Failed"
| project TimeGenerated, PodName, Namespace, ContainerStatus
| distinct PodName, Namespace

-- CPU usage by namespace
Perf
| where ObjectName == "K8SContainer"
| where CounterName == "cpuUsageNanoCores"
| summarize avg(CounterValue) by bin(TimeGenerated, 5m), Namespace
| render timechart
```

### Create Metric Alert

```bash
# Alert when AKS node CPU > 80%
az monitor metrics alert create \
  --name "aks-high-cpu" \
  --resource-group rg-devops \
  --scopes /subscriptions/<SUB_ID>/resourceGroups/rg-devops/providers/Microsoft.ContainerService/managedClusters/aks-devops-cluster \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action /subscriptions/<SUB_ID>/resourceGroups/rg-devops/providers/microsoft.insights/actionGroups/ag-devops-team \
  --description "AKS node CPU high"

# Create Action Group (email + webhook)
az monitor action-group create \
  --resource-group rg-devops \
  --name ag-devops-team \
  --short-name devops \
  --email-receivers name=team address=devops@company.com
```

---

## 7. Integration with Existing Tools

### Jenkins Deploying to AKS

**Jenkinsfile:**

```groovy
// Jenkinsfile - Deploy to AKS
pipeline {
    agent any

    environment {
        ACR_NAME        = 'acrdevops001'
        ACR_LOGIN_SERVER = 'acrdevops001.azurecr.io'
        IMAGE_NAME      = 'myapp'
        IMAGE_TAG       = "${BUILD_NUMBER}"
        AKS_RESOURCE_GROUP = 'rg-devops'
        AKS_CLUSTER_NAME   = 'aks-devops-cluster'
        NAMESPACE          = 'default'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh 'mvn sonar:sonar -Dsonar.projectKey=myapp'
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

        stage('Docker Build') {
            steps {
                sh """
                    docker build -t ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG} .
                    docker tag ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG} \
                               ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:latest
                """
            }
        }

        stage('Push to ACR') {
            steps {
                withCredentials([azureServicePrincipal('azure-sp-credentials')]) {
                    sh """
                        az login --service-principal \
                          -u $AZURE_CLIENT_ID \
                          -p $AZURE_CLIENT_SECRET \
                          --tenant $AZURE_TENANT_ID

                        az acr login --name ${ACR_NAME}
                        docker push ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('Deploy to AKS') {
            steps {
                withCredentials([azureServicePrincipal('azure-sp-credentials')]) {
                    sh """
                        az login --service-principal \
                          -u $AZURE_CLIENT_ID \
                          -p $AZURE_CLIENT_SECRET \
                          --tenant $AZURE_TENANT_ID

                        az aks get-credentials \
                          --resource-group ${AKS_RESOURCE_GROUP} \
                          --name ${AKS_CLUSTER_NAME} \
                          --overwrite-existing

                        kubectl set image deployment/myapp \
                          myapp=${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG} \
                          --namespace ${NAMESPACE}

                        kubectl rollout status deployment/myapp \
                          --namespace ${NAMESPACE} \
                          --timeout=5m
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    kubectl get pods -n ${NAMESPACE} -l app=myapp
                    kubectl get svc -n ${NAMESPACE} -l app=myapp
                """
            }
        }
    }

    post {
        success {
            echo "Deployment to AKS successful: ${IMAGE_TAG}"
        }
        failure {
            sh """
                kubectl rollout undo deployment/myapp \
                  --namespace ${NAMESPACE} || true
            """
            echo "Deployment failed — rolled back!"
        }
    }
}
```

### JFrog with AKS

```bash
# Create imagePullSecret for JFrog in K8s
kubectl create secret docker-registry jfrog-pull-secret \
  --docker-server=mycompany.jfrog.io \
  --docker-username=jenkins-svc \
  --docker-password=<JFROG_API_TOKEN> \
  --docker-email=devops@company.com \
  --namespace default

# Reference in deployment
# spec.template.spec.imagePullSecrets:
# - name: jfrog-pull-secret
```

---

## 8. Real-World Scenarios

### Scenario 1: Full Environment Provisioning

```bash
#!/bin/bash
# provision-azure-env.sh — Creates complete DevOps environment

set -e

RESOURCE_GROUP="rg-devops-prod"
LOCATION="eastus"
AKS_NAME="aks-prod-cluster"
ACR_NAME="acrprod001"
KV_NAME="kv-prod-secrets"

echo "=== Creating Resource Group ==="
az group create --name $RESOURCE_GROUP --location $LOCATION

echo "=== Creating ACR ==="
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard

echo "=== Creating Key Vault ==="
az keyvault create --name $KV_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

echo "=== Creating AKS ==="
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --enable-addons monitoring \
  --attach-acr $ACR_NAME \
  --generate-ssh-keys

echo "=== Getting Credentials ==="
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

echo "=== Verifying ==="
kubectl get nodes
echo "Environment ready!"
```

### Scenario 2: Monitor AKS with Container Insights

```bash
# Check Container Insights is running
kubectl get pods -n kube-system | grep omsagent
# Expected: omsagent-XXXXX Running

# View live metrics in Azure Portal:
# Portal → AKS → Monitoring → Insights → Cluster tab

# Query pod restarts in last hour
az monitor log-analytics query \
  --workspace law-devops \
  --analytics-query "KubePodInventory | where TimeGenerated > ago(1h) | summarize restartCount = sum(RestartCount) by PodName | order by restartCount desc | take 10"
```

### Scenario 3: AKS + ArgoCD Deployment

```bash
# Install ArgoCD on AKS
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD via Azure Load Balancer
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for external IP
kubectl get svc argocd-server -n argocd --watch

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Login
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
argocd login $ARGOCD_IP --username admin --insecure
```

---

## 9. Troubleshooting Guide

| Issue | Symptom | Fix |
|-------|---------|-----|
| AKS node NotReady | `kubectl get nodes` shows NotReady | `az aks nodepool upgrade` or check NSG rules |
| Image pull from ACR fails | `ErrImagePull` | Run `az aks update --attach-acr`; verify managed identity |
| AKS can't pull from JFrog | `ImagePullBackOff` | Check `imagePullSecrets` in deployment spec |
| Key Vault access denied | `403 Forbidden` | Assign `Key Vault Secrets User` role to pod identity |
| kubectl unauthorized | `Unauthorized` | Re-run `az aks get-credentials --overwrite-existing` |
| CSI driver not mounting | Pod stuck in Init | Check `kubectl describe pod` for CSI errors |
| AKS autoscaler not working | Nodes not scaling | Check `kubectl describe cm cluster-autoscaler-status -n kube-system` |
| az login fails in pipeline | Auth error | Verify service principal not expired; check `az ad sp show` |
| ACR throttling | Pull rate limit error | Upgrade to Premium SKU or implement image caching |
| Log Analytics no data | Empty queries | Verify omsagent pods running; check workspace ID in AKS addon config |

---

## 10. Cheat Sheet

```bash
# === AKS ===
az aks create -g <rg> -n <name> --node-count 3    # Create cluster
az aks get-credentials -g <rg> -n <name>           # Get kubectl config
az aks scale -g <rg> -n <name> --node-count 5      # Scale nodes
az aks upgrade -g <rg> -n <name> --kubernetes-version 1.29.0  # Upgrade
az aks show -g <rg> -n <name> --query kubernetesVersion       # Get version
az aks stop -g <rg> -n <name>                      # Stop cluster (save cost)
az aks start -g <rg> -n <name>                     # Start cluster

# === ACR ===
az acr create -g <rg> -n <name> --sku Standard     # Create
az acr login -n <name>                              # Docker login
az acr repository list -n <name>                   # List images
az acr build -r <name> -t image:tag .              # Build in cloud
az acr task run -r <name> -n <task>                # Run ACR task

# === Key Vault ===
az keyvault create -g <rg> -n <name>               # Create
az keyvault secret set --vault-name <name> --name <key> --value <val>  # Add secret
az keyvault secret show --vault-name <name> --name <key>               # Get secret
az keyvault secret list --vault-name <name>        # List secrets

# === Monitor ===
az monitor metrics alert create -n <name> -g <rg> --scopes <id> --condition "<cond>"
az monitor log-analytics query -w <ws> --analytics-query "<kql>"

# === General ===
az group create -n <name> -l eastus                # Create resource group
az group delete -n <name> --yes --no-wait          # Delete resource group
az resource list -g <name> -o table                # List resources
az account list -o table                           # List subscriptions
```
