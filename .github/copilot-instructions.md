# GitHub Copilot Instructions — DevOps Mastery Repository

## Repository Purpose

This repository is a **zero-to-expert DevOps learning project**. The goal is to take someone who knows nothing about DevOps and walk them step by step through every tool, concept, and production-grade setup needed to become an expert DevOps engineer.

The audience ranges from:
- **Beginners** who know basic Linux and maybe some Docker
- **Intermediate** engineers who can deploy apps but want deeper understanding
- **Advanced** practitioners who want production-grade reference implementations

Every guide must be written with this range in mind: start simple, explain concepts in plain English, build up to expert-level configurations.

---

## Repository Structure

```
docs/
├── 00-prerequisites/          # Local machine setup, tools installation
├── 01-cicd/                   # Jenkins, GitHub Actions, ArgoCD pipelines
├── 02-monitoring-observability/  # Prometheus, Grafana, ELK, Jaeger
├── 03-infrastructure-as-code/    # Terraform
├── 04-containerization/          # Docker, Podman
├── 05-gitops/                    # ArgoCD, FluxCD
├── 06-aiops/                     # AIOps for DevOps
├── 07-cloud-platform/            # Azure DevOps
├── 08-service-mesh-networking/   # Istio, NGINX Ingress
├── 09-collaboration-chatops/     # ChatOps (Slack, Teams)
└── 10-end-to-end-scenarios/      # Full pipeline scenarios
```

**Two guide types exist per major tool:**
- `*-complete-guide.md` — Full advanced reference (all config options, deep dives)
- `*-beginner-to-practitioner.md` — Learning guide (plain English → hands-on → scenarios)

---

## Writing Style & Content Rules

### 1. Always explain concepts in plain English first

Before showing any command or YAML, explain WHAT the tool does using a simple analogy or real-world comparison. Example:

> Prometheus is like a health checkup machine. Every 15 seconds it visits your app and asks "how are you?", records the numbers, and stores them.

Never assume the reader knows the concept. Always define terms the first time they appear.

### 2. Guide structure for beginner guides

Every beginner guide must follow this structure:
1. **What is [Tool]?** — Plain English explanation + analogy + key terms dictionary
2. **How it works** — Architecture diagram (ASCII) showing all components and data flow
3. **Simple sample project** — A real deployable app/config to test with
4. **Install on Kubernetes (AKS with Helm)** — Step-by-step with full values files
5. **Install on Azure VMs** — Step-by-step with all config files
6. **Core concepts deep dive** — The thing you MUST understand (PromQL, HCL, etc.)
7. **Scenarios section** — At least 10 real failure AND success scenarios
8. **Common mistakes & fixes** — Mistakes beginners actually make
9. **Quick reference cheat sheet** — Commands and patterns for daily use

### 3. Every scenario must include all four parts

When writing a scenario (failure or success):
- **Goal:** One sentence — what will the reader learn?
- **Trigger:** The exact command(s) to cause the situation
- **Observe:** The exact query/command to see it in the tool
- **Alert/Fix:** The alert rule or resolution command

### 4. Commands must be complete and runnable

- Never use placeholder-only commands. Always show the real flag, the real YAML key.
- When a value must be replaced by the user, mark it clearly: `# <-- REPLACE THIS`
- Include expected output as comments so readers know if it worked.
- Chain commands with comments explaining what each does.

### 5. Code blocks must specify language

Always use fenced code blocks with language identifiers:
- ` ```bash ` for shell commands
- ` ```yaml ` for Kubernetes/Helm/Prometheus YAML
- ` ```json ` for JSON
- ` ```promql ` for Prometheus queries
- ` ```javascript ` / ` ```python ` for application code
- ` ```hcl ` for Terraform

### 6. Kubernetes examples use AKS (Azure Kubernetes Service)

The primary cloud platform is **Azure**. Use:
- **AKS** for Kubernetes clusters
- **Azure VMs** (Ubuntu 22.04) for VM-based setups
- **Azure Container Registry (ACR)** for container images
- **Azure CLI (`az`)** for cloud resource creation
- Default location: `eastus`

When Helm charts are used, always include:
- The `helm repo add` command
- A complete `values.yaml` file with every key commented
- The `helm install` command with `--namespace` and `--wait`
- Verification commands after install

### 7. Alert rules must be complete

Every alert rule must include:
```yaml
alert: AlertName
expr: <promql expression>
for: <duration>
labels:
  severity: warning|critical
annotations:
  summary: "Human readable summary with {{ $labels.instance }}"
  description: "Detailed description with {{ $value }}"
```

### 8. Show both success AND failure

For every tool and scenario, show:
- ✅ What the **healthy/working** state looks like (metrics, logs, output)
- ❌ What the **broken/failing** state looks like
- How to tell the difference using the tool itself

---

## Tool-Specific Guidelines

### Prometheus
- Always use `kube-prometheus-stack` Helm chart (not standalone Prometheus)
- Use `ServiceMonitor` or `PodMonitor` for K8s scrape config, not `additionalScrapeConfigs` alone
- PromQL queries must always include `rate()` for counters — never graph raw counter values
- Node Exporter is mandatory for VM monitoring
- Alert rules go in `/etc/prometheus/rules/*.yml` on VMs, or via Helm `additionalPrometheusRulesMap` on K8s

### Grafana
- Always provision datasources via YAML (`provisioning/datasources/`) not just UI clicks
- Import community dashboards by ID (provide the ID and name)
- Dashboard variables (dropdowns) must be shown for namespace, pod, instance filtering
- Alert contact points must include a test step

### Kubernetes / Helm
- Always specify `--namespace` on every `kubectl` and `helm` command
- Show `kubectl rollout status` after every deployment
- Resource `requests` and `limits` must be set on every container
- Use `kubectl get pods -w` or `kubectl rollout status` to show watching live state

### Terraform
- Always include `terraform init`, `plan`, `apply` in sequence
- Show `terraform output` to verify resources were created
- Use Azure provider (`azurerm`)
- State should be in Azure Storage backend

### Docker / Podman
- Always use non-root users in Dockerfiles (`USER`)
- Multi-stage builds for production images
- Always tag images with version + latest

### Jenkins
- Pipelines in `Jenkinsfile` (declarative syntax)
- Stages: Checkout → Build → Test → Scan → Push → Deploy
- Always show how to trigger and verify a build

### ArgoCD / GitOps
- App of Apps pattern for multi-service deployments
- Always show sync status verification: `argocd app sync` + `argocd app wait`
- Health checks in ApplicationSet

### ELK Stack
- Filebeat on K8s nodes and VMs as DaemonSet / systemd service
- Always show Kibana index pattern creation steps
- Include a sample Logstash pipeline filter

### Istio
- Always use `istioctl install --set profile=demo` for learning environments
- Show sidecar injection verification: `kubectl get pod -l istio-injection=enabled`
- VirtualService + DestinationRule must be shown together

---

## Scenario Writing Rules

When asked to add monitoring, observability, or operational scenarios:

1. Cover both **Kubernetes** and **Azure VM** variants
2. Include at least **3 failure scenarios** and **2 success scenarios** per tool
3. Failures must be **reproducible** — provide the exact `stress-ng`, `kubectl`, or `curl` command
4. Successes must demonstrate the tool working **end-to-end** (install → configure → verify → alert)
5. Number scenarios clearly: `Scenario 1`, `Scenario 2`, etc.
6. Add a **summary table** at the end of all scenarios

---

## Sample App Guidelines

When a guide needs a sample application:
- Use **Node.js + Express** as the default language (simple, widely understood)
- The app must expose a `/metrics` endpoint (Prometheus format)
- The app must have a `/health` endpoint (for K8s probes)
- Include at least: a normal route (`/`), a slow route (`/slow`), an error route (`/error`)
- Provide `Dockerfile`, `package.json`, K8s `deployment.yaml`, and K8s `ServiceMonitor`
- The `Dockerfile` must use a non-root user

---

## File Naming Convention

| File type | Naming pattern | Example |
|---|---|---|
| Advanced reference guide | `<tool>-complete-guide.md` | `prometheus-complete-guide.md` |
| Beginner learning guide | `<tool>-beginner-to-practitioner.md` | `grafana-beginner-to-practitioner.md` |
| Integration guide | `<tool-a>-<tool-b>-integration.md` | `jenkins-argocd-integration.md` |
| End-to-end scenario | `scenario-<nn>-<description>.md` | `scenario-01-full-pipeline.md` |

---

## When Asked to Write or Update a Guide

1. **Check the existing file first** — read it before editing to understand what is already covered
2. **Do not duplicate content** — if the complete guide covers advanced config, the beginner guide focuses on getting started
3. **Link between guides** — always end with a "What to do next" section linking to related guides in the repo
4. **Commit message format:**
   - New file: `Add <tool> beginner-to-practitioner guide with <key features>`
   - Update: `Update <tool> guide: add <what was added>`
   - Fix: `Fix <tool> guide: correct <what was wrong>`

---

## What This Repo Teaches (Full DevOps Stack)

| Category | Tools Covered |
|---|---|
| CI/CD | Jenkins, GitHub Actions, ArgoCD |
| Monitoring & Observability | Prometheus, Grafana, ELK Stack (Elasticsearch + Logstash + Kibana), Jaeger |
| Infrastructure as Code | Terraform (Azure) |
| Containerization | Docker, Podman |
| GitOps | ArgoCD, FluxCD |
| Cloud Platform | Azure DevOps, AKS, Azure VMs, ACR |
| Service Mesh | Istio, NGINX Ingress |
| Collaboration | ChatOps (Slack, Teams bots) |
| AIOps | AI-assisted incident detection |
| End-to-End | Full pipeline, canary deploy, incident response, infra provisioning |

The learning path goes: Containers → CI/CD → GitOps → Monitoring → IaC → Service Mesh → AIOps

---

## Tone and Language

- Write for a **non-native English speaker** — use short sentences, avoid idioms
- Use **bold** for the first occurrence of every important term
- Use tables to compare options instead of long paragraphs
- Use `code blocks` for every command, file path, metric name, and config key — never inline plain text
- Add a one-line comment after every non-obvious command explaining why it is there
- Always say "you will see:" before showing expected output
