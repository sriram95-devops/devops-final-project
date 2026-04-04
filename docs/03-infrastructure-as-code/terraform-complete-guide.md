# Terraform Complete Guide

## Table of Contents
1. [Overview & Why Terraform](#overview--why-terraform)
2. [Local Setup](#local-setup)
3. [Online/Cloud Setup](#onlinecloud-setup)
4. [Configuration Deep Dive](#configuration-deep-dive)
5. [Integration with Existing Tools](#integration-with-existing-tools)
6. [Real-World Scenarios](#real-world-scenarios)
7. [Verification & Testing](#verification--testing)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Cheat Sheet](#cheat-sheet)

---

## Overview & Why Terraform

### What is Infrastructure as Code (IaC)?

Infrastructure as Code (IaC) is the practice of managing and provisioning computing infrastructure through machine-readable configuration files rather than through manual processes or interactive configuration tools. Instead of clicking through a cloud console or running imperative shell commands, you describe what your infrastructure should look like, and your IaC tool makes it so.

**Key benefits of IaC:**
- **Repeatability**: The same configuration always produces the same infrastructure.
- **Version Control**: Infrastructure changes are tracked in Git just like application code.
- **Collaboration**: Teams can review, approve, and audit infrastructure changes via pull requests.
- **Speed**: Provisioning hundreds of resources takes minutes rather than days.
- **Documentation**: The configuration files themselves document the infrastructure.
- **Disaster Recovery**: Re-create an entire environment from scratch in minutes.

### Declarative vs. Imperative IaC

| Aspect | Declarative | Imperative |
|--------|-------------|------------|
| Style | Describe the desired end state | Describe the steps to reach the end state |
| Example tool | Terraform, CloudFormation | Ansible (partially), shell scripts |
| Idempotency | Built-in | Must be coded manually |
| State management | Tool tracks state | No built-in tracking |
| Readability | High (what, not how) | Lower (procedural logic) |

**Terraform is declarative.** You write:
```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "my-aks-cluster"
  location            = "East US"
  resource_group_name = "my-rg"
  dns_prefix          = "myaks"
  # ...
}
```
Terraform figures out how to create, update, or delete that resource to match your declared state.

### Terraform vs. Ansible vs. Pulumi

| Feature | Terraform | Ansible | Pulumi |
|---------|-----------|---------|--------|
| Primary use | Infrastructure provisioning | Configuration management | Infrastructure provisioning |
| Language | HCL (HashiCorp Configuration Language) | YAML/Jinja2 | Python, TypeScript, Go, C# |
| State management | Yes (state file) | No | Yes (state backend) |
| Cloud coverage | Excellent (1000+ providers) | Good | Good |
| Learning curve | Medium | Low-Medium | Medium-High |
| Imperative/Declarative | Declarative | Imperative/Declarative hybrid | Imperative (in familiar lang) |
| Mutable/Immutable | Immutable-first | Mutable | Immutable-first |
| Community | Very large | Very large | Growing |

**When to use Terraform:**
- Provisioning cloud resources (VMs, Kubernetes clusters, databases, networks)
- Multi-cloud or hybrid cloud environments
- When you need a strong state management system
- When your team prefers a purpose-built DSL

**When to use Ansible instead:**
- Configuring software on existing VMs (install packages, edit config files)
- Running ad-hoc operational tasks
- When you need agentless SSH-based execution

**When to use Pulumi instead:**
- Your team is more comfortable with general-purpose programming languages
- You need complex loops, conditionals, or abstractions not easy in HCL
- You want to unit test your infrastructure code

### How Terraform Works

Terraform operates in a three-stage cycle:

1. **Write**: Author `.tf` configuration files describing desired infrastructure.
2. **Plan**: Run `terraform plan` — Terraform compares your configuration against the current state and shows what will be created, updated, or destroyed.
3. **Apply**: Run `terraform apply` — Terraform executes the changes.

Terraform maintains a **state file** (`terraform.tfstate`) that records the real-world resources it manages. This state is the single source of truth for Terraform and must be treated carefully (stored remotely, never edited manually).

---

## Local Setup

### Install Terraform on Ubuntu/Debian

```bash
# Add HashiCorp GPG key and repository
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform -y

# Verify installation
terraform version
```

### Install Terraform on macOS

```bash
# Using Homebrew (recommended)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
```

### Install Terraform on Windows

```powershell
# Using Chocolatey
choco install terraform

# Or using winget
winget install Hashicorp.Terraform
```

### Install tfenv (Terraform Version Manager)

Managing multiple Terraform versions across projects is easier with `tfenv`:

```bash
# Install tfenv
git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install a specific version
tfenv install 1.6.0
tfenv use 1.6.0

# List installed versions
tfenv list
```

### Azure CLI Authentication

Terraform uses the Azure provider (`azurerm`) to manage Azure resources. You need to authenticate.

#### Option 1: Azure CLI (recommended for local development)

```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login
az login

# Set default subscription
az account set --subscription "your-subscription-id"

# Verify
az account show
```

#### Option 2: Service Principal (recommended for CI/CD)

```bash
# Create a service principal with Contributor role
az ad sp create-for-rbac \
  --name "terraform-sp" \
  --role="Contributor" \
  --scopes="/subscriptions/YOUR_SUBSCRIPTION_ID" \
  --sdk-auth

# Output will look like:
# {
#   "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
#   "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
# }
```

Store these values as environment variables:

```bash
export ARM_CLIENT_ID="<clientId>"
export ARM_CLIENT_SECRET="<clientSecret>"
export ARM_SUBSCRIPTION_ID="<subscriptionId>"
export ARM_TENANT_ID="<tenantId>"
```

Or configure them in your `provider.tf` (without secrets in code — use env vars or a vault):

```hcl
provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
```

### VS Code Terraform Extension

Install the **HashiCorp Terraform** extension for VS Code:

```bash
# Via CLI
code --install-extension hashicorp.terraform

# Or search "HashiCorp Terraform" in VS Code Extensions panel
```

**Extension features:**
- Syntax highlighting for `.tf` and `.tfvars` files
- IntelliSense / auto-completion for resource types and arguments
- Hover documentation for providers and resources
- Format on save (`terraform fmt`)
- Integrated `terraform validate`

**Recommended VS Code settings** (`.vscode/settings.json`):

```json
{
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.tabSize": 2
  },
  "[terraform-vars]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true
  }
}
```

---

## Online/Cloud Setup

### Azure Cloud Shell

Azure Cloud Shell is a browser-based shell that comes with Terraform pre-installed — no local setup needed.

1. Go to [https://shell.azure.com](https://shell.azure.com)
2. Choose **Bash** mode
3. Verify Terraform is available: `terraform version`
4. You are already authenticated to Azure — no `az login` needed
5. Cloud Shell provides 5 GB of persistent storage in an Azure File Share

```bash
# In Azure Cloud Shell — Terraform is ready to use
terraform version

# Clone your Terraform configs
git clone https://github.com/your-org/your-infra-repo.git
cd your-infra-repo

# Initialize and apply
terraform init
terraform plan
terraform apply
```

**Limitations of Cloud Shell:**
- Timeouts after 20 minutes of inactivity
- Not ideal for long-running `terraform apply` operations
- Limited compute resources

### Gitpod / GitHub Codespaces

You can define a development environment with Terraform pre-installed using a devcontainer:

```json
// .devcontainer/devcontainer.json
{
  "name": "Terraform Dev",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/terraform:1": {
      "version": "latest"
    },
    "ghcr.io/devcontainers/features/azure-cli:1": {}
  }
}
```

---

## Configuration Deep Dive

### Project Structure

A well-organised Terraform project follows a consistent file structure:

```
infra/
├── main.tf           # Primary resources
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output values
├── provider.tf       # Provider configuration
├── versions.tf       # Terraform and provider version constraints
├── terraform.tfvars  # Variable values (not committed if secrets)
├── locals.tf         # Local value computations
└── modules/
    ├── aks/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── networking/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### provider.tf — Azure Provider Configuration

```hcl
# provider.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state backend (see Remote State section)
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateaccount"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    # Prevent accidental deletion of key vaults by requiring soft-delete purge
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Prevent accidental deletion of resource groups containing resources
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
```

### variables.tf — Input Variable Declarations

```hcl
# variables.tf

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "my-aks-rg"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "East US"

  validation {
    condition     = contains(["East US", "West US", "West Europe", "East Asia"], var.location)
    error_message = "Location must be one of: East US, West US, West Europe, East Asia."
  }
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "environment" {
  description = "Environment name: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "acr_name" {
  description = "Name of the Azure Container Registry (must be globally unique)"
  type        = string
}

variable "enable_auto_scaling" {
  description = "Enable cluster autoscaler on the default node pool"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum nodes when autoscaling is enabled"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes when autoscaling is enabled"
  type        = number
  default     = 5
}
```

### outputs.tf — Output Values

```hcl
# outputs.tf

output "resource_group_name" {
  description = "Name of the created Resource Group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "kube_config" {
  description = "Kubernetes configuration for kubectl"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true  # Marks this output as sensitive — won't be shown in plan/apply output
}

output "aks_fqdn" {
  description = "FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "acr_login_server" {
  description = "Login server URL for ACR"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "node_resource_group" {
  description = "Auto-generated resource group containing AKS nodes"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}
```

### main.tf — Provision AKS Cluster (Line-by-Line Explained)

```hcl
# main.tf

# ─── Resource Group ──────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  # The logical name Terraform uses to reference this resource internally
  name     = var.resource_group_name

  # Azure region where the resource group is created
  location = var.location

  # Tags are key-value metadata attached to the resource in Azure
  tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    Environment = var.environment
  })
}

# ─── Virtual Network ─────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # CIDR block for the entire VNet — must be large enough for all subnets
  address_space = ["10.0.0.0/8"]

  tags = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  # Subnet CIDR — nodes will receive IPs from this range
  address_prefixes = ["10.240.0.0/16"]
}

# ─── AKS Cluster ─────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "aks" {
  # Display name of the AKS cluster in Azure
  name = var.cluster_name

  # Must match the resource group's location
  location = azurerm_resource_group.main.location

  # Resource group to place the AKS resource in
  resource_group_name = azurerm_resource_group.main.name

  # DNS prefix used to form the FQDN of the K8s API server
  # Must be unique within the Azure region
  dns_prefix = var.cluster_name

  # Kubernetes version to deploy — must be a supported version in the region
  kubernetes_version = var.kubernetes_version

  # default_node_pool defines the system node pool (required, cannot be deleted)
  default_node_pool {
    # Internal name for this node pool (lowercase alphanumeric, max 12 chars)
    name = "default"

    # Number of nodes (ignored if enable_auto_scaling = true and min/max set)
    node_count = var.enable_auto_scaling ? null : var.node_count

    # Azure VM SKU for node VMs
    vm_size = var.node_vm_size

    # Place nodes in the custom subnet (enables Azure CNI networking)
    vnet_subnet_id = azurerm_subnet.aks_nodes.id

    # Enable cluster autoscaler to scale nodes based on workload demand
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_node_count : null
    max_count           = var.enable_auto_scaling ? var.max_node_count : null

    # OS disk size in GB for each node
    os_disk_size_gb = 50

    # OS disk type: Managed (persistent) or Ephemeral (faster, uses VM cache disk)
    os_disk_type = "Managed"

    # Type of node pool: VirtualMachineScaleSets (recommended) or AvailabilitySet
    type = "VirtualMachineScaleSets"

    # Spread nodes across availability zones for high availability
    zones = ["1", "2", "3"]

    # Labels applied to all nodes in this pool (selectable via nodeSelector in K8s)
    node_labels = {
      "pool" = "default"
    }

    # Upgrade settings for rolling node upgrades
    upgrade_settings {
      # Maximum number of nodes that can be unavailable during an upgrade
      max_surge = "10%"
    }
  }

  # Managed identity for the AKS cluster (recommended over service principals)
  identity {
    # SystemAssigned: Azure manages the identity lifecycle automatically
    type = "SystemAssigned"
  }

  # Network profile defines how pods and services communicate
  network_profile {
    # azure: Azure CNI (pods get VNet IPs, better for enterprise networking)
    # kubenet: simpler, NAT-based (less IP usage, limited features)
    network_plugin = "azure"

    # azure: Azure Network Policy (uses eBPF, recommended)
    # calico: open-source Network Policy implementation
    network_policy = "azure"

    # Service CIDR: IP range for Kubernetes ClusterIP services (must not overlap VNet)
    service_cidr = "10.0.0.0/16"

    # DNS service IP: must be within service_cidr (conventionally .10)
    dns_service_ip = "10.0.0.10"
  }

  # Enable the Kubernetes dashboard add-on (legacy, consider alternatives)
  # addon_profile block replaced by individual addon arguments in azurerm >= 3.x

  # Azure Monitor integration for container insights
  monitor_metrics {}

  # Enable Microsoft Defender for Containers (security monitoring)
  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Azure Key Vault Secrets Provider — mounts secrets directly into pods
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # RBAC configuration
  azure_active_directory_role_based_access_control {
    # Managed: Azure AD integration managed by Microsoft
    managed = true

    # Allow Azure AD users/groups with Azure RBAC roles on the cluster to authenticate
    azure_rbac_enabled = true
  }

  # Automatic channel for minor Kubernetes version upgrades
  automatic_channel_upgrade = "patch"

  # Maintenance window for upgrades (prevents disruption during business hours)
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [21, 22, 23]
    }
  }

  tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    Environment = var.environment
  })
}

# ─── Log Analytics Workspace (for AKS monitoring) ────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
```

### Terraform Modules (Reusable Components)

Modules let you package and reuse configuration. A module is simply a directory with `.tf` files.

**Module directory structure:**
```
modules/
└── aks/
    ├── main.tf       # Resource definitions
    ├── variables.tf  # Module inputs
    └── outputs.tf    # Module outputs
```

**modules/aks/variables.tf:**
```hcl
variable "cluster_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**modules/aks/main.tf:**
```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}
```

**modules/aks/outputs.tf:**
```hcl
output "cluster_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}

output "identity_principal_id" {
  value = azurerm_kubernetes_cluster.this.identity[0].principal_id
}
```

**Consuming the module (root main.tf):**
```hcl
module "aks" {
  source = "./modules/aks"

  cluster_name        = "my-cluster"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  node_count          = 3
  tags                = local.common_tags
}

# Access module outputs
output "cluster_id" {
  value = module.aks.cluster_id
}
```

### Remote State in Azure Blob Storage

Storing state remotely is critical for team collaboration and CI/CD.

**Step 1: Create the storage resources (one-time setup)**

```bash
#!/bin/bash
RESOURCE_GROUP="terraform-state-rg"
STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"
CONTAINER="tfstate"
LOCATION="eastus"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2

az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT"

# Enable versioning to protect state file history
az storage blob service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --enable-versioning true

echo "Storage account: $STORAGE_ACCOUNT"
```

**Step 2: Configure backend in provider.tf**

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstate1a2b3c4d"  # From the script output
    container_name       = "tfstate"
    key                  = "prod/aks.tfstate"  # Path within the container
  }
}
```

**Step 3: Initialize with the backend**

```bash
terraform init

# If migrating existing local state to remote:
terraform init -migrate-state
```

### Terraform Workspaces

Workspaces allow managing multiple environments with the same configuration.

```bash
# List workspaces
terraform workspace list

# Create and switch to dev workspace
terraform workspace new dev

# Create staging and prod
terraform workspace new staging
terraform workspace new prod

# Switch workspaces
terraform workspace select prod

# Show current workspace
terraform workspace show
```

**Using workspace in configuration:**

```hcl
# locals.tf
locals {
  workspace = terraform.workspace

  # Different configurations per workspace
  node_counts = {
    dev     = 1
    staging = 2
    prod    = 3
  }

  vm_sizes = {
    dev     = "Standard_B2s"
    staging = "Standard_D2s_v3"
    prod    = "Standard_D4s_v3"
  }

  node_count = local.node_counts[local.workspace]
  vm_size    = local.vm_sizes[local.workspace]
}
```

### terraform.tfvars and Variable Precedence

**terraform.tfvars** (automatically loaded):
```hcl
resource_group_name = "my-aks-rg"
location            = "East US"
cluster_name        = "my-cluster"
environment         = "prod"
node_count          = 3
node_vm_size        = "Standard_D4s_v3"
enable_auto_scaling = true
min_node_count      = 2
max_node_count      = 10
acr_name            = "myacr12345"

tags = {
  Team    = "platform"
  Project = "devops-final"
}
```

**Environment-specific files** (loaded with `-var-file`):
```bash
# dev.tfvars
terraform apply -var-file="environments/dev.tfvars"

# prod.tfvars
terraform apply -var-file="environments/prod.tfvars"
```

**Variable Precedence (highest to lowest):**
1. `-var` CLI flag: `terraform apply -var="node_count=5"`
2. `-var-file` CLI flag
3. `*.auto.tfvars` files (alphabetical order)
4. `terraform.tfvars`
5. Environment variables: `TF_VAR_node_count=5`
6. Default values in `variables.tf`

---

## Integration with Existing Tools

### Jenkins Integration

**Complete Jenkinsfile for Terraform CI/CD:**

```groovy
// Jenkinsfile
pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.6.0'
            args '-v /var/run/docker.sock:/var/run/docker.sock --entrypoint=""'
        }
    }

    environment {
        ARM_CLIENT_ID       = credentials('azure-client-id')
        ARM_CLIENT_SECRET   = credentials('azure-client-secret')
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_TENANT_ID       = credentials('azure-tenant-id')
        TF_VAR_environment  = "${env.BRANCH_NAME == 'main' ? 'prod' : 'dev'}"
        TF_IN_AUTOMATION    = 'true'  // Disables interactive prompts
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Format Check') {
            steps {
                dir('infra') {
                    sh 'terraform fmt -check -recursive'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir('infra') {
                    sh '''
                        terraform init \
                          -backend-config="key=${TF_VAR_environment}/aks.tfstate" \
                          -reconfigure
                    '''
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir('infra') {
                    sh 'terraform validate'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('infra') {
                    sh '''
                        terraform plan \
                          -var-file="environments/${TF_VAR_environment}.tfvars" \
                          -out=tfplan \
                          -detailed-exitcode
                    '''
                }
            }
            post {
                always {
                    // Archive the plan for review
                    archiveArtifacts artifacts: 'infra/tfplan', fingerprint: true
                }
            }
        }

        stage('Approval') {
            when {
                branch 'main'
            }
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: 'Review the Terraform plan. Proceed with apply?',
                          ok: 'Apply'
                }
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                dir('infra') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Update kubeconfig') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    az aks get-credentials \
                      --resource-group $(terraform -chdir=infra output -raw resource_group_name) \
                      --name $(terraform -chdir=infra output -raw aks_cluster_name) \
                      --overwrite-existing
                    kubectl get nodes
                '''
            }
        }
    }

    post {
        failure {
            slackSend channel: '#infra-alerts',
                      color: 'danger',
                      message: "Terraform pipeline FAILED on ${env.BRANCH_NAME}: ${env.BUILD_URL}"
        }
        success {
            slackSend channel: '#infra-alerts',
                      color: 'good',
                      message: "Terraform apply succeeded on ${env.BRANCH_NAME}"
        }
        always {
            cleanWs()
        }
    }
}
```

### Kubernetes Integration

After Terraform provisions AKS, configure `kubectl`:

```bash
# Get credentials from Terraform output
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

# Configure kubectl
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

# Verify connectivity
kubectl get nodes
kubectl get namespaces
```

**Use the kubeconfig in the same Terraform run** (for subsequent K8s resources):

```hcl
# After provisioning AKS, configure the Kubernetes provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# Create a namespace using the Kubernetes provider
resource "kubernetes_namespace" "apps" {
  metadata {
    name = "applications"
    labels = {
      managed-by = "terraform"
    }
  }
}
```

### ArgoCD Bootstrap on Terraform-Provisioned AKS

```hcl
# Install ArgoCD using the Helm provider after AKS is provisioned

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.0"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [kubernetes_namespace.argocd]
}

output "argocd_service_ip" {
  value = helm_release.argocd.status
}
```

---

## Real-World Scenarios

### Scenario 1: Provision AKS Cluster with Terraform

**Complete working configuration:**

```hcl
# environments/dev.tfvars
resource_group_name = "devops-dev-rg"
location            = "East US"
cluster_name        = "devops-dev-aks"
kubernetes_version  = "1.28"
environment         = "dev"
node_count          = 1
node_vm_size        = "Standard_B2s"
enable_auto_scaling = false
acr_name            = "devopsdevacr12345"

tags = {
  Environment = "dev"
  Team        = "platform"
  CostCenter  = "engineering"
}
```

```bash
# Provision the AKS cluster
cd infra/
terraform init
terraform plan -var-file="environments/dev.tfvars" -out=dev.tfplan
terraform apply dev.tfplan

# Configure kubectl
az aks get-credentials \
  --resource-group devops-dev-rg \
  --name devops-dev-aks

# Verify
kubectl get nodes
kubectl cluster-info
```

### Scenario 2: Add ACR and Configure AKS to Pull from It

```hcl
# main.tf additions

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Basic: dev/test | Standard: production | Premium: geo-replication
  sku = var.environment == "prod" ? "Premium" : "Standard"

  # Enable admin user (needed for some integrations; prefer managed identity for K8s)
  admin_enabled = false

  tags = var.tags
}

# Grant AKS the AcrPull role on ACR using managed identity
resource "azurerm_role_assignment" "aks_acr_pull" {
  # The principal ID of the AKS kubelet managed identity
  principal_id = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id

  # AcrPull allows pulling images, but not pushing
  role_definition_name = "AcrPull"

  # Scope the role to the specific ACR resource
  scope = azurerm_container_registry.acr.id
}
```

```bash
# After apply — test ACR integration
ACR_NAME=$(terraform output -raw acr_login_server)

# Build and push a test image
docker build -t ${ACR_NAME}/myapp:v1 .
az acr login --name $(terraform output -raw acr_login_server | cut -d. -f1)
docker push ${ACR_NAME}/myapp:v1

# Deploy to AKS — no imagePullSecret needed (managed identity handles auth)
kubectl run test \
  --image=${ACR_NAME}/myapp:v1 \
  --restart=Never
kubectl get pod test
```

### Scenario 3: Full Environment (VNet + AKS + ACR + Key Vault)

```hcl
# full-environment/main.tf

resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-platform-rg"
  location = var.location
  tags     = local.common_tags
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "${var.environment}-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.240.0.0/16"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.241.0.0/24"]

  private_endpoint_network_policies_enabled = true
}

# ─── AKS ─────────────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.environment}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.environment}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = local.vm_sizes[var.environment]
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = local.min_nodes[var.environment]
    max_count           = local.max_nodes[var.environment]
    os_disk_size_gb     = 128
    zones               = ["1", "2", "3"]
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.common_tags
}

# ─── ACR ─────────────────────────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  name                = "${var.environment}platformacr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.environment == "prod" ? "Premium" : "Standard"
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "aks_acr" {
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main.id
}

# ─── Key Vault ────────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = "${var.environment}-platform-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable soft delete and purge protection for production
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7
  purge_protection_enabled   = var.environment == "prod"

  # Allow the AKS cluster's managed identity to read secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id

    secret_permissions = ["Get", "List"]
  }

  tags = local.common_tags
}

# ─── Locals ───────────────────────────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "devops-final-project"
  })

  vm_sizes = {
    dev     = "Standard_B2s"
    staging = "Standard_D2s_v3"
    prod    = "Standard_D4s_v3"
  }

  min_nodes = { dev = 1, staging = 1, prod = 3 }
  max_nodes = { dev = 3, staging = 5, prod = 20 }
}
```

```bash
# Deploy the full environment in one command
terraform apply -var-file="environments/prod.tfvars"

# Expected resources created:
# - 1 Resource Group
# - 1 Virtual Network + 2 Subnets
# - 1 AKS Cluster
# - 1 Container Registry
# - 1 Role Assignment (AKS → ACR)
# - 1 Key Vault
# - 1 Log Analytics Workspace
```

---

## Verification & Testing

### terraform validate

```bash
# Check syntax and configuration validity
terraform validate

# Expected output:
# Success! The configuration is valid.
```

### terraform fmt

```bash
# Format all .tf files to canonical style
terraform fmt -recursive

# Check only (non-zero exit if formatting needed — use in CI)
terraform fmt -check -recursive
```

### Plan Review Checklist

Before running `terraform apply`, review the plan for:

```bash
terraform plan -out=tfplan -detailed-exitcode
# Exit codes: 0 = no changes, 1 = error, 2 = changes present

# Show a saved plan
terraform show tfplan

# Output plan as JSON for programmatic analysis
terraform show -json tfplan | jq '.resource_changes[] | select(.change.actions[] | contains("delete"))'
```

**What to look for in the plan:**
- `+ create` — New resources being created (expected)
- `~ update in-place` — Existing resources being modified (review carefully)
- `-/+ replace` — Resource will be destroyed and recreated (potentially disruptive!)
- `- destroy` — Resource being deleted (dangerous!)

### Post-Apply Verification

```bash
# Verify AKS cluster
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A

# Verify ACR
az acr list --output table
az acr check-health --name <acr-name>

# Verify Key Vault
az keyvault list --output table

# Check Terraform state
terraform state list
terraform state show azurerm_kubernetes_cluster.aks
```

### Terratest (Automated Infrastructure Testing)

```go
// test/aks_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestAKSCluster(t *testing.T) {
    opts := &terraform.Options{
        TerraformDir: "../infra",
        Vars: map[string]interface{}{
            "environment": "test",
            "node_count":  1,
        },
    }

    defer terraform.Destroy(t, opts)
    terraform.InitAndApply(t, opts)

    clusterName := terraform.Output(t, opts, "aks_cluster_name")
    assert.Equal(t, "test-aks", clusterName)
}
```

---

## Troubleshooting Guide

### Issue 1: State Lock Error

```
Error: Error acquiring the state lock
Error message: state blob is already locked
```

**Cause:** A previous `terraform apply` was interrupted and left the state locked.

**Fix:**
```bash
# Force-unlock the state (use the lock ID from the error message)
terraform force-unlock LOCK_ID

# For Azure backend, you can also break the lease manually:
az storage blob lease break \
  --blob-name "prod/aks.tfstate" \
  --container-name tfstate \
  --account-name tfstateaccount
```

### Issue 2: Authentication Error

```
Error: Error building account: Error getting authenticated object ID
```

**Fix:**
```bash
# Re-authenticate
az login
az account set --subscription "your-sub-id"

# Or verify service principal env vars are set
echo $ARM_CLIENT_ID $ARM_TENANT_ID $ARM_SUBSCRIPTION_ID
```

### Issue 3: Resource Already Exists

```
Error: A resource with the ID "/subscriptions/.../resourceGroups/my-rg" already exists
```

**Fix:** Import the existing resource into Terraform state:
```bash
terraform import azurerm_resource_group.main /subscriptions/SUB_ID/resourceGroups/my-rg
```

### Issue 4: Quota Exceeded

```
Error: QuotaExceeded: Operation could not be completed as it results in exceeding approved quota
```

**Fix:**
```bash
# Check current quota usage
az vm list-usage --location "East US" --output table

# Request a quota increase via Azure portal or:
az quota update --resource-name StandardDSv3Family --scope /subscriptions/SUB_ID/providers/Microsoft.Compute/locations/eastus --limit-object value=100
```

### Issue 5: Provider Version Conflicts

```
Error: Failed to query available provider packages
```

**Fix:**
```bash
# Clear provider cache and re-initialize
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
```

### Issue 6: Terraform State Drift

State drift occurs when resources are modified outside of Terraform.

**Fix:**
```bash
# Refresh state to sync with real infrastructure
terraform refresh

# Or plan with refresh to see drift
terraform plan -refresh=true

# For specific resource
terraform apply -target=azurerm_kubernetes_cluster.aks -refresh-only
```

### Issue 7: Circular Dependencies

```
Error: Cycle: module.aks.azurerm_role_assignment, module.acr
```

**Fix:** Use `depends_on` explicitly to break circular references, or restructure your modules.

### Issue 8: Sensitive Value in Plan Output

**Fix:** Mark variables as sensitive:
```hcl
variable "db_password" {
  type      = string
  sensitive = true
}
```

### Issue 9: AKS Node Pool Immutable Fields

```
Error: node_count cannot be updated when enable_auto_scaling is true
```

**Fix:** Some AKS fields require node pool replacement. Use:
```bash
terraform apply -target=azurerm_kubernetes_cluster.aks
# Review that it shows -/+ replace, then accept
```

### Issue 10: Backend Configuration Changed

```
Error: Backend configuration changed
```

**Fix:**
```bash
terraform init -reconfigure
# or to migrate existing state:
terraform init -migrate-state
```

---

## Cheat Sheet

### Core Terraform Commands

| Command | Description |
|---------|-------------|
| `terraform init` | Initialize working directory, download providers and modules |
| `terraform init -upgrade` | Upgrade providers to latest allowed versions |
| `terraform init -migrate-state` | Migrate state to a new backend |
| `terraform validate` | Check configuration syntax and validity |
| `terraform fmt` | Format configuration files to canonical style |
| `terraform fmt -check` | Check formatting without modifying files (CI use) |
| `terraform plan` | Show execution plan (what will change) |
| `terraform plan -out=tfplan` | Save plan to file for later apply |
| `terraform plan -target=resource.name` | Plan only a specific resource |
| `terraform apply` | Apply changes (prompts for confirmation) |
| `terraform apply -auto-approve` | Apply without confirmation prompt |
| `terraform apply tfplan` | Apply a saved plan file |
| `terraform destroy` | Destroy all managed resources |
| `terraform destroy -target=resource.name` | Destroy a specific resource |
| `terraform show` | Show current state or a saved plan |
| `terraform output` | Show output values |
| `terraform output -raw name` | Show raw output value (no quotes) |
| `terraform output -json` | Show all outputs as JSON |
| `terraform state list` | List all resources in state |
| `terraform state show resource.name` | Show details of a state resource |
| `terraform state rm resource.name` | Remove resource from state (doesn't delete real resource) |
| `terraform state mv src dst` | Move/rename resource in state |
| `terraform import resource.name ID` | Import existing resource into state |
| `terraform refresh` | Sync state with real infrastructure |
| `terraform force-unlock LOCK_ID` | Release a stuck state lock |
| `terraform workspace list` | List all workspaces |
| `terraform workspace new name` | Create a new workspace |
| `terraform workspace select name` | Switch to a workspace |
| `terraform graph` | Generate dependency graph (pipe to dot) |
| `terraform console` | Interactive expression evaluation |
| `terraform providers` | Show required providers |
| `terraform version` | Show Terraform version |

### Useful Flags

| Flag | Used With | Description |
|------|-----------|-------------|
| `-var="key=value"` | plan, apply | Override a variable |
| `-var-file=file.tfvars` | plan, apply | Load variables from file |
| `-target=resource` | plan, apply, destroy | Operate on specific resource only |
| `-refresh=false` | plan, apply | Skip state refresh (faster, use with caution) |
| `-parallelism=N` | apply | Number of concurrent operations (default 10) |
| `-detailed-exitcode` | plan | Exit 0=no changes, 1=error, 2=changes |
| `-json` | plan, show | JSON output |
| `-no-color` | all | Disable color output (useful for CI logs) |
| `-compact-warnings` | plan, apply | Shorter warning output |
| `-lock=false` | plan, apply | Skip state locking (dangerous!) |
| `-lock-timeout=10m` | plan, apply | Wait for lock to be released |
| `-reconfigure` | init | Reconfigure backend |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TF_VAR_name` | Override input variable `name` |
| `TF_CLI_ARGS` | Default CLI arguments for all commands |
| `TF_CLI_ARGS_plan` | Default arguments for `terraform plan` |
| `TF_LOG` | Log level: TRACE, DEBUG, INFO, WARN, ERROR |
| `TF_LOG_PATH` | Write logs to a file |
| `TF_IN_AUTOMATION` | Set to any value to reduce interactive prompts |
| `ARM_CLIENT_ID` | Azure service principal client ID |
| `ARM_CLIENT_SECRET` | Azure service principal secret |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |
| `ARM_TENANT_ID` | Azure tenant ID |
| `TF_WORKSPACE` | Select a workspace |

---

*This guide covers Terraform as used with the Azure provider in the context of the DevOps Final Project. For the latest documentation, see [https://developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform).*
