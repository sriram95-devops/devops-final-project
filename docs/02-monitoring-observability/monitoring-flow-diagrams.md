# Monitoring Flow Diagrams

Visual guide to how the full monitoring stack works in this project — from deployment to alert firing — and what happens when each part succeeds or fails.

> All diagrams use Mermaid syntax. They render automatically on GitHub, VS Code (with Markdown Preview), and most modern documentation platforms.

---

## Table of Contents

1. [Overall Architecture](#1-overall-architecture)
2. [Setup and Deployment Flow](#2-setup-and-deployment-flow)
3. [Prometheus Scraping Flow — Success Path](#3-prometheus-scraping-flow--success-path)
4. [Prometheus Scraping Flow — Failure Paths](#4-prometheus-scraping-flow--failure-paths)
5. [Grafana Dashboard Flow — Success Path](#5-grafana-dashboard-flow--success-path)
6. [Grafana Dashboard Flow — Failure Paths](#6-grafana-dashboard-flow--failure-paths)
7. [Alert Firing Flow](#7-alert-firing-flow)
8. [Debug Decision Tree — "My Metrics Are Missing"](#8-debug-decision-tree--my-metrics-are-missing)
9. [Debug Decision Tree — "Grafana Is Broken"](#9-debug-decision-tree--grafana-is-broken)
10. [Full End-to-End Flow — Pod Crash Scenario](#10-full-end-to-end-flow--pod-crash-scenario)
11. [Interview Diagrams](#interview-diagrams) ← simplified diagrams + what to say

---

## 1. Overall Architecture

This shows every component in the monitoring stack and how they connect.

```mermaid
graph TB
    subgraph cluster["Minikube Cluster"]

        subgraph monitoring["namespace: monitoring"]
            HelmChart["kube-prometheus-stack\nHelm Chart v83.6.0"]
            Prom["Prometheus\nport 9090\nScrapes every 15s"]
            Graf["Grafana 12.4.3\nport 3000\nDashboards + Alerts"]
            AM["Alertmanager\nport 9093\nRoutes alerts"]
            KSM["kube-state-metrics\nCluster-level metrics"]
            NE["node-exporter\nNode-level metrics"]
            PromOp["Prometheus Operator\nWatches ServiceMonitor CRDs"]
            SM["ServiceMonitor CRD\necommerce-all-services\nWatches dev + test"]
        end

        subgraph dev["namespace: dev"]
            PS["product-service\n:8080/actuator/prometheus"]
            OS["order-service\n:8080/actuator/prometheus"]
            US["user-service\n:8080/actuator/prometheus"]
            AS["auth-service\n:8080/actuator/prometheus"]
            IS["inventory-service\n:8080/actuator/prometheus"]
            PAY["payment-service\n:8080/actuator/prometheus"]
            NOT["notification-service\n:8080/actuator/prometheus"]
            AG["api-gateway\n:8080/actuator/prometheus"]
        end

        subgraph test["namespace: test"]
            TestSvcs["same services\ntest builds"]
        end

    end

    subgraph local["Local Machine"]
        PF1["port-forward\nlocalhost:9090"]
        PF2["port-forward\nlocalhost:3000"]
        Browser["Browser\nPrometheus UI\nGrafana UI"]
    end

    HelmChart -->|deploys and manages| Prom
    HelmChart -->|deploys and manages| Graf
    HelmChart -->|deploys and manages| AM
    HelmChart -->|deploys and manages| KSM
    HelmChart -->|deploys and manages| NE
    HelmChart -->|deploys and manages| PromOp

    PromOp -->|reads CRD, generates scrape config| SM
    SM -->|targets services with monitor=true label| PS
    SM -->|targets services with monitor=true label| OS
    SM -->|targets services with monitor=true label| US
    SM -->|targets services with monitor=true label| AS

    Prom -->|scrapes /actuator/prometheus every 15s| PS
    Prom -->|scrapes /actuator/prometheus every 15s| OS
    Prom -->|scrapes /actuator/prometheus every 15s| US
    Prom -->|scrapes /actuator/prometheus every 15s| AS
    Prom -->|scrapes /actuator/prometheus every 15s| IS
    Prom -->|scrapes /actuator/prometheus every 15s| PAY
    Prom -->|scrapes /actuator/prometheus every 15s| NOT
    Prom -->|scrapes /actuator/prometheus every 15s| AG
    Prom -->|scrapes node metrics| NE
    Prom -->|scrapes cluster state| KSM
    Prom -->|fires alerts| AM

    Graf -->|queries PromQL| Prom
    Graf -->|receives alerts from| AM

    PF1 -->|tunnels to| Prom
    PF2 -->|tunnels to| Graf
    Browser --> PF1
    Browser --> PF2
```

---

## 2. Setup and Deployment Flow

How the entire monitoring stack gets deployed from scratch.

```mermaid
flowchart TD
    Start([Start: Fresh Minikube Cluster]) --> A

    A["kubectl create namespace monitoring\nkubectl create namespace dev\nkubectl create namespace test"]
    A --> B["kubectl apply -f k8s/namespaces.yaml\nLabel namespaces with environment + monitored-by labels"]
    B --> C["helm repo add prometheus-community\nhttps://prometheus-community.github.io/helm-charts\nhelm repo update"]
    C --> D["helm install kube-prometheus-stack\nprometheus-community/kube-prometheus-stack\n--namespace monitoring\n-f k8s/prometheus-stack-values.yaml"]

    D --> E{Helm install\nsuccessful?}

    E -->|Yes| F["kubectl get pods -n monitoring\nWait for all pods: Running"]
    E -->|No - OOMKilled| OOM["Increase memory limits\nin prometheus-stack-values.yaml\nRe-run helm install"]
    E -->|No - CrashLoop| CL["Check logs:\nkubectl logs deploy/...-grafana\nSee grafana-troubleshooting.md"]

    OOM --> D
    CL --> D

    F --> G["kubectl apply -f k8s/servicemonitor-all.yaml\nDeploy ServiceMonitor CRD"]
    G --> H["kubectl apply -f k8s/*.yaml\nDeploy all microservices to dev namespace"]
    H --> I["Verify services have monitor=true label\nkubectl get svc -n dev --show-labels"]

    I --> J{All services\nlabeled?}
    J -->|No| K["kubectl label svc NAME monitor=true -n dev"]
    K --> I
    J -->|Yes| L["kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring"]

    L --> M["Open http://localhost:9090/targets\nVerify all services show State: UP"]
    M --> N{All targets\nUP?}

    N -->|No| TSG["See prometheus-troubleshooting.md\nDebug section"]
    N -->|Yes| O["kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"]

    O --> P["Open http://localhost:3000\nLogin: admin / YourGrafanaPassword123!"]
    P --> Q["Verify Prometheus datasource: green OK"]
    Q --> R["Open Dashboards → Verify k8s-cluster,\nnode-exporter-full, k8s-pods load data"]
    R --> Done([✅ Monitoring Stack Ready])
```

---

## 3. Prometheus Scraping Flow — Success Path

What happens every 15 seconds when a scrape succeeds.

```mermaid
sequenceDiagram
    participant PO as Prometheus Operator
    participant SM as ServiceMonitor CRD
    participant P as Prometheus
    participant SVC as K8s Service (dev)
    participant POD as App Pod
    participant TSDB as Prometheus TSDB

    Note over PO,SM: One-time setup (on startup)
    PO->>SM: Watch for ServiceMonitor resources
    SM-->>PO: "Scrape services with monitor=true in dev + test"
    PO->>P: Generate scrape_config with discovered endpoints

    Note over P,TSDB: Every 15 seconds (scrape interval)
    P->>SVC: Resolve Service DNS → get Endpoints list
    SVC-->>P: Returns pod IPs + port 8080
    P->>POD: GET http://10.x.x.x:8080/actuator/prometheus
    POD-->>P: HTTP 200 + Prometheus text format metrics
    P->>TSDB: Store time series with labels {namespace="dev", pod="...", job="..."}
    TSDB-->>P: Stored ✅

    Note over P: Target status = UP, up=1
    P->>P: up{namespace="dev", job="product-service"} = 1
```

---

## 4. Prometheus Scraping Flow — Failure Paths

What Prometheus sees and records when something goes wrong.

```mermaid
flowchart TD
    P["Prometheus\nScrape interval triggered (15s)"]

    P --> DNS["Resolve Service DNS\neg. product-service.dev.svc.cluster.local"]

    DNS --> DNS_OK{DNS resolves?}

    DNS_OK -->|No - Service deleted| F1["❌ No Endpoints found\nTarget removed from scrape list\nup metric DISAPPEARS\nabsent() query returns 1"]
    DNS_OK -->|No - Wrong namespace| F2["❌ RBAC Forbidden\nPrometheus Operator logs error\nNo targets discovered at all"]
    DNS_OK -->|Yes| EP["Get Endpoints list\nfrom Kubernetes API"]

    EP --> EP_OK{Endpoints\nexist?}
    EP_OK -->|No - replicas=0| F3["❌ No pod endpoints\nTarget removed from scrape list\nup metric DISAPPEARS\nkube_deployment_status_replicas_available = 0"]
    EP_OK -->|Yes| SCRAPE["HTTP GET\n/actuator/prometheus\non pod IP:8080"]

    SCRAPE --> HTTP{HTTP\nresponse?}
    HTTP -->|404 Not Found| F4["❌ up = 0\nscrape_duration_seconds recorded\nTarget shows DOWN in UI\nLikely: wrong metrics path"]
    HTTP -->|Connection refused| F5["❌ up = 0\nTarget shows DOWN\nLikely: pod starting up or crashed"]
    HTTP -->|Timeout| F6["❌ up = 0\nTarget shows DOWN\nLikely: app overloaded or hung"]
    HTTP -->|200 OK| SUCCESS["✅ up = 1\nMetrics parsed and stored\nTarget shows UP in UI"]

    F1 --> FIX1["Fix: Scale replicas back up\nor use absent() to alert on absence"]
    F2 --> FIX2["Fix: Apply ClusterRole RBAC\nSee prometheus-troubleshooting.md Issue 5"]
    F3 --> FIX3["Fix: Scale replicas back up\nor detect with kube_deployment_spec_replicas != 0"]
    F4 --> FIX4["Fix: Check ServiceMonitor path\nMust match /actuator/prometheus"]
    F5 --> FIX5["Fix: Check pod logs\nkubectl logs POD -n dev\nCheck liveness probe config"]
    F6 --> FIX6["Fix: Check resource limits\nApp may need more CPU/memory"]
```

---

## 5. Grafana Dashboard Flow — Success Path

How a Grafana dashboard loads data from Prometheus correctly.

```mermaid
sequenceDiagram
    participant U as User Browser
    participant G as Grafana 12.x
    participant CP as ConfigMap / dashboardProviders
    participant DS as Prometheus Datasource
    participant P as Prometheus

    Note over G,CP: On Grafana startup
    G->>CP: Read /etc/grafana/provisioning/datasources/
    CP-->>G: Prometheus datasource (auto-created by Helm chart)\nisDefault: true, URL: http://prometheus-operated:9090
    G->>CP: Read /etc/grafana/provisioning/dashboards/dashboardproviders.yaml
    CP-->>G: Provider: watch /var/lib/grafana/dashboards/default
    G->>G: Load dashboard JSON files from that folder
    Note over G: Dashboards available in unified storage API

    Note over U,P: User opens a dashboard
    U->>G: GET /d/k8s-cluster (dashboard URL)
    G-->>U: Return dashboard JSON (panel definitions + PromQL queries)
    U->>G: Execute panel queries
    G->>DS: Validate datasource is healthy
    DS-->>G: HTTP 200 OK
    G->>P: POST /api/v1/query_range\nexpr=rate(http_requests_total[5m])\nstart=now-1h&end=now&step=60s
    P-->>G: JSON array of time series data points
    G-->>U: Render graph with data ✅
```

---

## 6. Grafana Dashboard Flow — Failure Paths

What breaks and why for each common Grafana failure.

```mermaid
flowchart TD
    GStart(["Grafana Container Starts"])

    GStart --> ReadDS["Read datasource provisioning\n/etc/grafana/provisioning/datasources/"]

    ReadDS --> DS_CHECK{How many datasources\nmarked isDefault: true?}

    DS_CHECK -->|Two or more| CRASH["💥 FATAL: config is invalid\nOnly one datasource per org\ncan be marked as default\n\nContainer EXITS\nkubelet restarts → CrashLoopBackOff"]
    DS_CHECK -->|Exactly one| ReadDB["Read dashboardProviders\n/etc/grafana/provisioning/dashboards/"]

    CRASH --> FIX_CRASH["Fix: Remove grafana.datasources block\nfrom prometheus-stack-values.yaml\nHelm chart creates datasource automatically\nhelm upgrade → Revision N+1"]

    ReadDB --> PATH_CHECK{dashboardproviders path\nmatches actual files location?}

    PATH_CHECK -->|Path mismatch| NO_DASH["❌ Dashboards NOT loaded\nGrafana starts successfully\nbut no dashboards appear\nUI shows empty state"]
    PATH_CHECK -->|Path correct| DS_HEALTH["Check datasource connectivity\nPrometheus URL reachable?"]

    NO_DASH --> FIX_PATH["Fix: Set dashboardProviders path\nto /var/lib/grafana/dashboards/default\nhelm upgrade\nkubectl rollout restart deploy/...grafana"]

    DS_HEALTH --> DS_UP{Prometheus\nreachable?}

    DS_UP -->|No - wrong URL| DS_FAIL["❌ Datasource shows red X\n'Bad gateway' error\nAll panels show 'No data'"]
    DS_UP -->|Yes| LOAD_PANEL["Dashboard opens\nPanels execute PromQL queries"]

    DS_FAIL --> FIX_DS["Fix: Check Prometheus service name\nDefault URL:\nhttp://prometheus-operated:9090\nor\nhttp://kube-prometheus-stack-prometheus:9090"]

    LOAD_PANEL --> DATA_CHECK{Prometheus returns\ndata for the query?}

    DATA_CHECK -->|No data - targets down| NO_DATA["❌ Panels show 'No data'\nMetrics exist but no current values\nCheck Prometheus /targets"]
    DATA_CHECK -->|No data - wrong query| WRONG_Q["❌ Panels show 'No data'\nQuery returns empty\nCheck namespace/label filters in PromQL"]
    DATA_CHECK -->|Data returned| SUCCESS_G["✅ Graph renders\nData visible in panels"]

    NO_DATA --> FIX_ND["Fix: Check up{namespace='dev'}\nin Prometheus\nAll services must show up=1"]
    WRONG_Q --> FIX_WQ["Fix: Edit panel → check variable\nfilters match your namespace/pod names\neg. namespace='dev' not 'default'"]
```

---

## 7. Alert Firing Flow

How a problem in a microservice eventually becomes a firing alert.

```mermaid
flowchart TD
    Pod["Pod enters CrashLoopBackOff\n(bad liveness probe / OOMKill / error)"]

    Pod --> Restart["kubelet kills and restarts container\nkube_pod_container_status_restarts_total increases"]

    Restart --> PScrape["Prometheus scrapes kube-state-metrics\nevery 15 seconds"]

    PScrape --> Eval["Prometheus evaluates alert rules\nevery evaluation_interval (default 1m)"]

    Eval --> Rule{"Alert rule expression\nincrease(kube_pod_container_status_restarts_total[15m]) > 3\nevaluates to TRUE?"}

    Rule -->|No, restarts < 3| Pending2["No alert\nkeep evaluating"]
    Rule -->|Yes, restarts > 3| Pending["Alert state = PENDING\nWaiting for 'for: 5m' duration"]

    Pending --> Timer{Has alert been\ncontinuously true\nfor 5 minutes?}

    Timer -->|No| Pending
    Timer -->|Yes| Firing["🔥 Alert state = FIRING\nPrometheus sends to Alertmanager"]

    Firing --> AM["Alertmanager receives alert\nChecks routing rules"]

    AM --> Route{Route matches\nwhich receiver?}

    Route -->|severity=critical| Page["Send to PagerDuty / OpsGenie\nPage on-call engineer immediately"]
    Route -->|severity=warning| Notify["Send to Slack / Teams channel\nPost notification message"]
    Route -->|no route match| Default["Send to default receiver\n(email or null receiver)"]

    Page --> Eng["Engineer receives page\nOpens Grafana dashboard\nInvestigates"]
    Notify --> Eng

    Eng --> GrafanaCheck["Check Grafana:\nk8s-pods dashboard\nFilter by namespace=dev"]
    GrafanaCheck --> PromCheck["Check Prometheus:\nup{namespace='dev'}\nkube_pod_container_status_restarts_total"]
    PromCheck --> Kubectl["kubectl describe pod PODNAME -n dev\nkubectl logs PODNAME -n dev --previous"]
    Kubectl --> Fix["Identify root cause:\n- Bad liveness probe path\n- OOMKilled → increase memory limit\n- App error → fix code + redeploy"]
    Fix --> Rollback["kubectl rollout undo deployment/NAME -n dev\nor\nkubectl apply -f updated-deployment.yaml"]
    Rollback --> Resolved["✅ Pod running, up=1\nAlert auto-resolves after 5m\nAlertmanager sends 'Resolved' notification"]
```

---

## 8. Debug Decision Tree — "My Metrics Are Missing"

Use this when a service is not showing up in Prometheus at all, or showing `up=0`.

```mermaid
flowchart TD
    Start(["Problem: Service not visible in Prometheus\nor showing up=0"]) --> Q1

    Q1{"Is the pod\nrunning?"}
    Q1 -->|No| A1["kubectl get pods -n dev\nLook for Pending / CrashLoopBackOff / Error\nFix the pod first before checking monitoring"]
    Q1 -->|Yes, Running| Q2

    Q2{"Does the service\nexist?"}
    Q2 -->|No| A2["kubectl apply -f k8s/service.yaml\nService object must exist for Prometheus to scrape"]
    Q2 -->|Yes| Q3

    Q3{"Does the service have\nmonitor=true label?"}
    Q3 -->|No| A3["kubectl label svc SERVICE-NAME monitor=true -n dev\nWait 15s → check /targets again"]
    Q3 -->|Yes| Q4

    Q4{"Is the namespace in\nServiceMonitor namespaceSelector?"}
    Q4 -->|No| A4["Edit servicemonitor-all.yaml\nAdd namespace to matchNames list\nkubectl apply -f k8s/servicemonitor-all.yaml"]
    Q4 -->|Yes| Q5

    Q5{"Can Prometheus read\nservices in that namespace?"}
    Q5 -->|No - RBAC error in Operator logs| A5["Apply ClusterRole + ClusterRoleBinding\nSee prometheus-troubleshooting.md Issue 5"]
    Q5 -->|Yes| Q6

    Q6{"Does the target show\nin /targets page?"}
    Q6 -->|No - not listed at all| A6["ServiceMonitor label selector mismatch\nCheck selector.matchLabels in servicemonitor-all.yaml\nvs labels on the Service object"]
    Q6 -->|Yes, listed but UP=0| Q7

    Q7{"What is the scrape\nerror message?"}
    Q7 -->|connection refused| A7a["Pod is not listening on port 8080\nCheck: kubectl port-forward POD 8080:8080 -n dev\ncurl localhost:8080/actuator/prometheus"]
    Q7 -->|404 not found| A7b["Wrong metrics path\nServiceMonitor path must be /actuator/prometheus\nCheck endpoint path in servicemonitor-all.yaml"]
    Q7 -->|context deadline exceeded| A7c["Pod is overloaded or metrics endpoint is slow\nCheck resource limits\nkubectl top pod -n dev"]
    Q7 -->|target shows UP=1| OK["✅ Metrics are being scraped correctly\nCheck Grafana datasource and queries instead"]
```

---

## 9. Debug Decision Tree — "Grafana Is Broken"

Use this when Grafana is crashing, not showing dashboards, or showing "No data".

```mermaid
flowchart TD
    GProb(["Problem: Grafana issue"]) --> TypeCheck

    TypeCheck{"What is the symptom?"}

    TypeCheck -->|Pod is in Error/CrashLoopBackOff| CrashPath
    TypeCheck -->|Pod is running but dashboards missing| DashPath
    TypeCheck -->|Dashboard opens but panels show No Data| NoDataPath
    TypeCheck -->|Cannot access Grafana UI at all| AccessPath

    subgraph CrashPath["🔴 CrashLoopBackOff"]
        C1["kubectl logs deploy/kube-prometheus-stack-grafana\n-n monitoring -c grafana --previous"]
        C1 --> C2{"Log contains:\n'datasource config is invalid'\n'only one datasource can be default'?"}
        C2 -->|Yes| C3["Remove grafana.datasources block\nfrom prometheus-stack-values.yaml\nDo NOT define Prometheus datasource manually\nHelm chart manages it automatically"]
        C3 --> C4["helm upgrade kube-prometheus-stack ...\n-f k8s/prometheus-stack-values.yaml"]
        C4 --> C5["kubectl get pods -n monitoring -w\nWait for 3/3 Running, 0 restarts"]
        C2 -->|No, different error| C6["Read full error message\nGoogle exact error + Grafana 12 + kube-prometheus-stack"]
    end

    subgraph DashPath["🟡 No Dashboards"]
        D1["Check dashboardProviders config:\nhelm get values kube-prometheus-stack -n monitoring"]
        D1 --> D2{"dashboardProviders\npath defined?"}
        D2 -->|No| D3["Add dashboardProviders block to values.yaml\npath: /var/lib/grafana/dashboards/default\nhelm upgrade"]
        D2 -->|Yes| D4["Check path matches sidecar mount\nkubectl exec -it GRAFANA-POD -n monitoring -c grafana\nls /var/lib/grafana/dashboards/default/\nShould show .json files"]
        D4 --> D5{"JSON files\npresent?"}
        D5 -->|No| D6["Sidecar is not downloading dashboards\nCheck grafana.dashboards in values.yaml\nkubectl logs GRAFANA-POD -c grafana-sc-dashboard"]
        D5 -->|Yes but still not showing| D7["Grafana 12: /api/search returns empty\nUse unified storage API instead:\ncurl localhost:3000/apis/dashboard.grafana.app/v1beta1/\nnamespaces/default/dashboards"]
    end

    subgraph NoDataPath["🟡 No Data in Panels"]
        N1["Test Prometheus datasource in Grafana UI\nConfiguration → Data Sources → Prometheus → Save & Test"]
        N1 --> N2{"Datasource\nhealthy?"}
        N2 -->|Red X| N3["Check Prometheus service is running\nkubectl get svc prometheus-operated -n monitoring\nCheck URL in datasource config"]
        N2 -->|Green OK| N4["Run query manually in Explore tab\nup{namespace='dev'}"]
        N4 --> N5{"Query returns\ndata?"}
        N5 -->|No| N6["Prometheus has no data\nCheck /targets — are all services UP?\nSee prometheus-troubleshooting.md"]
        N5 -->|Yes, data exists| N7["Dashboard variable filter is wrong\nEdit panel → check namespace/job label values\nmatch your actual namespace names"]
    end

    subgraph AccessPath["🔴 Cannot Access UI"]
        A1["On Minikube: LoadBalancer stays Pending\nThis is NORMAL — use port-forward"]
        A1 --> A2["kubectl port-forward\nsvc/kube-prometheus-stack-grafana\n3000:80 -n monitoring"]
        A2 --> A3["Open http://localhost:3000\nLogin: admin / YourGrafanaPassword123!"]
        A3 --> A4{"Login\nsuccessful?"}
        A4 -->|No - wrong password| A5["Check adminPassword in prometheus-stack-values.yaml\nOr reset: kubectl exec ... grafana-cli admin reset-admin-password"]
        A4 -->|Yes| A6["✅ Grafana accessible\nMove to dashboard debugging above"]
    end
```

---

## 10. Full End-to-End Flow — Pod Crash Scenario

This is the complete story of what happened in this project: product-service was made to crash-loop, and we validated the full monitoring chain.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant K8s as Kubernetes (Minikube)
    participant Kubelet as Kubelet
    participant KSM as kube-state-metrics
    participant Prom as Prometheus
    participant Graf as Grafana
    participant AM as Alertmanager

    Note over Dev,K8s: Step 1 — Simulate crash (bad liveness probe)
    Dev->>K8s: kubectl apply -f product-patched.json\n(liveness path = /bad-path)
    K8s->>Kubelet: New pod spec with liveness probe path = /bad-path
    Kubelet->>K8s: Start container (app starts successfully on port 8080)
    Kubelet->>K8s: Liveness check: GET /bad-path → 404
    Note over Kubelet: Failure 1/2
    Kubelet->>K8s: Liveness check: GET /bad-path → 404
    Note over Kubelet: Failure 2/2 → kill and restart
    K8s-->>Dev: Pod status: CrashLoopBackOff (kubectl get pods -n dev)

    Note over K8s,KSM: Step 2 — kube-state-metrics sees restart counter increase
    KSM->>K8s: Watch pod events via Kubernetes API
    K8s-->>KSM: container_status.restartCount = 1, 2, 3...
    KSM->>KSM: Expose metric: kube_pod_container_status_restarts_total{pod="product-service-..."} = 3

    Note over KSM,Prom: Step 3 — Prometheus scrapes and evaluates
    Prom->>KSM: GET /metrics (every 15s)
    KSM-->>Prom: kube_pod_container_status_restarts_total = 3
    Prom->>Prom: Store time series in TSDB
    Prom->>Prom: Evaluate alert rule:\nincrease(kube_pod_container_status_restarts_total[15m]) > 3\nResult: TRUE
    Prom->>AM: Send alert: PodCrashLooping\nseverity=critical\npod=product-service-xxx

    Note over Prom,Graf: Step 4 — Developer queries Prometheus directly
    Dev->>Prom: GET localhost:9090 → query: up{namespace="dev"}
    Prom-->>Dev: product-service: up=0 (pod is crashing during scrape window)\nall others: up=1
    Dev->>Prom: query: increase(kube_pod_container_status_restarts_total[5m])
    Prom-->>Dev: product-service: restarts=5 in last 5m

    Note over Dev,Graf: Step 5 — Developer opens Grafana dashboard
    Dev->>Graf: Open k8s-pods dashboard
    Graf->>Prom: PromQL: kube_pod_container_status_restarts_total{namespace="dev"}
    Prom-->>Graf: Time series data showing restart spikes
    Graf-->>Dev: Graph showing restart spike for product-service ✅

    Note over Dev,K8s: Step 6 — Fix and rollback
    Dev->>K8s: kubectl rollout undo deployment/product-service -n dev
    K8s->>Kubelet: Roll back to previous ReplicaSet (healthy liveness probe)
    Kubelet->>K8s: New pod starts, liveness check passes ✅
    K8s-->>Dev: kubectl get pods -n dev → 2/2 Running, 0 restarts

    Note over K8s,Prom: Step 7 — Prometheus confirms recovery
    Prom->>K8s: Scrape product-service /actuator/prometheus
    K8s-->>Prom: HTTP 200 OK + metrics
    Prom->>Prom: up{namespace="dev", job="product-service"} = 1
    Prom->>AM: Alert condition no longer true → send Resolved

    Note over AM,Dev: Step 8 — Alert resolves
    AM-->>Dev: "RESOLVED: PodCrashLooping - product-service"
```

---

## ASCII Summary Diagram

For environments where Mermaid does not render (plain text terminals, some editors):

```
MONITORING STACK — OVERALL DATA FLOW
=====================================

  [Minikube Cluster]
  ┌─────────────────────────────────────────────────────────────┐
  │                                                             │
  │  namespace: dev / test                                      │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
  │  │product-service│  │ order-service│  │  user-service│ ...  │
  │  │:8080/actuator │  │:8080/actuator│  │:8080/actuator│      │
  │  │  /prometheus  │  │  /prometheus │  │  /prometheus │      │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
  │         │                 │                  │               │
  │         └─────────────────┴──────────────────┘               │
  │                           │ scrape every 15s                  │
  │                           ▼                                   │
  │  namespace: monitoring                                        │
  │  ┌─────────────────────────────────────────────┐             │
  │  │              kube-prometheus-stack           │             │
  │  │                                             │             │
  │  │  Prometheus Operator                        │             │
  │  │       │ reads ServiceMonitor CRD            │             │
  │  │       ▼                                     │             │
  │  │  Prometheus ──────────────────────────────► │             │
  │  │  (stores TSDB)       alerts                 │             │
  │  │       │                   │                 │             │
  │  │       │               Alertmanager          │             │
  │  │       │               (routes alerts)       │             │
  │  │       │                                     │             │
  │  │       ▼                                     │             │
  │  │   Grafana                                   │             │
  │  │  (PromQL queries → dashboards)              │             │
  │  └─────────────────────────────────────────────┘             │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘
                    │                    │
           port-forward              port-forward
           localhost:9090            localhost:3000
                    │                    │
              Prometheus UI          Grafana UI
              /targets               /d/dashboards
              /graph                 Login: admin


WHAT HAPPENS WHEN THINGS BREAK
================================

  Pod crash-loops       →  up=0 in Prometheus
                        →  restart counter rises in kube-state-metrics
                        →  Alert fires after threshold met
                        →  Grafana dashboard shows spike

  Pod scaled to zero    →  Target disappears (NOT up=0, just absent)
                        →  absent() PromQL returns 1
                        →  No alert unless you use absent() rule

  Wrong Service label   →  Service not discovered by ServiceMonitor
                        →  Target never appears in /targets
                        →  No data at all

  Grafana crash         →  Usually: duplicate default datasource
                        →  Fix: remove grafana.datasources from values
                        →  helm upgrade → pod restarts healthy

  Dashboards missing    →  Usually: dashboardProviders path mismatch
                        →  Fix: add dashboardProviders with correct path
                        →  helm upgrade → dashboards load
```

---

## Interview Diagrams

> Use these diagrams when explaining the monitoring stack in an interview.
> Each one is small enough to draw on a whiteboard in under 2 minutes and covers exactly what an interviewer expects to hear.

---

### Interview Diagram 1 — "How does Prometheus collect metrics?"

**What the interviewer is asking:** Explain the scraping model. How does Prometheus know where to look?

```
  ┌─────────────────────────────────────────────────────┐
  │  How Prometheus discovers and scrapes targets        │
  └─────────────────────────────────────────────────────┘

   You deploy this:              Prometheus reads this:

   Service (K8s object)          ServiceMonitor (CRD)
   ┌──────────────────┐          ┌──────────────────────┐
   │ name: product-svc│◄─────────│ selector:            │
   │ label:           │  matches │   monitor: "true"    │
   │   monitor: "true"│          │ namespaces: [dev,test]│
   │ port: 8080       │          │ path: /actuator/     │
   └────────┬─────────┘          │         prometheus   │
            │                    └──────────────────────┘
            │ pod IP                        │
            ▼                    Prometheus Operator reads
   ┌──────────────────┐          the CRD and writes scrape
   │   App Pod        │          config into Prometheus
   │ :8080/actuator/  │◄──────────────────────────────────
   │   prometheus     │
   │                  │   Every 15s: GET /actuator/prometheus
   └──────────────────┘   Response: up=1 (success) or up=0 (fail)
```

**Say in the interview:**
> "Prometheus uses a pull model. It does not receive data — it goes out and asks each app for metrics every 15 seconds. In Kubernetes, we use a ServiceMonitor CRD to tell Prometheus which services to scrape. The Prometheus Operator watches for ServiceMonitor objects and automatically generates the scrape configuration. Services must have the `monitor: true` label to be discovered."

---

### Interview Diagram 2 — "How does Grafana connect to Prometheus?"

**What the interviewer is asking:** Explain the datasource + query model.

```
  ┌──────────────────────────────────────────────────────────┐
  │  Grafana → Prometheus data flow                           │
  └──────────────────────────────────────────────────────────┘

  User opens dashboard
         │
         ▼
     Grafana
  ┌──────────────┐
  │  Dashboard   │  contains panels, each panel has a PromQL query
  │              │
  │  Panel 1:    │──── PromQL: rate(http_requests_total[5m])
  │  Panel 2:    │──── PromQL: up{namespace="dev"}
  │  Panel 3:    │──── PromQL: kube_pod_container_status_restarts_total
  └──────┬───────┘
         │  HTTP POST /api/v1/query_range
         ▼
     Prometheus
  ┌──────────────┐
  │  TSDB        │  Time Series Database (stores all scraped metrics)
  │  (on disk)   │──── returns JSON array of data points
  └──────────────┘
         │
         ▼
  Grafana renders graph ✅
```

**Say in the interview:**
> "Grafana does not store any metrics. It is purely a visualization layer. Each dashboard panel contains a PromQL query. When you open a dashboard, Grafana sends those queries to Prometheus over HTTP, Prometheus runs them against its time series database and returns the results, and Grafana renders the graph. If there is no data, the problem is either in Prometheus (targets are down) or the PromQL query itself (wrong label filters)."

---

### Interview Diagram 3 — "Walk me through what happens when a pod crashes"

**What the interviewer is asking:** End-to-end incident flow. This is the most common interview question.

```
  ┌────────────────────────────────────────────────────────────────┐
  │  Pod crash → Alert → Engineer notified (end-to-end)            │
  └────────────────────────────────────────────────────────────────┘

  1. Pod crashes
     App pod ──► liveness probe fails ──► kubelet kills container
                                      ──► restarts it
                                      ──► CrashLoopBackOff

  2. kube-state-metrics sees it
     Kubernetes API ──► kube-state-metrics
     kube_pod_container_status_restarts_total{pod="product-..."} = 5

  3. Prometheus scrapes and evaluates
     Prometheus scrapes kube-state-metrics every 15s
     Evaluates alert rule:
       increase(restarts_total[15m]) > 3  →  TRUE
     Alert state: PENDING → (after 5 min) → FIRING

  4. Alertmanager routes the alert
     Prometheus ──► Alertmanager
                        │
                        ├── severity=critical ──► PagerDuty (page engineer)
                        └── severity=warning  ──► Slack (post message)

  5. Engineer investigates
     Grafana dashboard ──► see restart spike on k8s-pods dashboard
     Prometheus query  ──► up{namespace="dev"} shows up=0
     kubectl logs      ──► read the actual error message
     kubectl describe  ──► see liveness probe failure events

  6. Fix and verify
     kubectl rollout undo deployment/product-service -n dev
     up{namespace="dev"} returns 1 ──► alert auto-resolves
     Alertmanager sends "RESOLVED" notification
```

**Say in the interview:**
> "When a pod crashes, kubelet restarts it. kube-state-metrics tracks the restart count via the Kubernetes API. Prometheus scrapes kube-state-metrics every 15 seconds and evaluates alert rules against that data. When the restart count exceeds the threshold for the required duration, Prometheus fires the alert to Alertmanager. Alertmanager routes it — critical alerts go to PagerDuty, warnings go to Slack. The engineer then uses Grafana to see the dashboard spike and Prometheus to run queries. After the fix, Prometheus sees `up=1` again, the alert condition is no longer true, and Alertmanager sends a resolved notification."

---

### Interview Diagram 4 — "What did you debug in this project?"

**What the interviewer is asking:** Tell me about a real problem you solved. This is your answer.

```
  ┌────────────────────────────────────────────────────────────────┐
  │  Real problems solved in this project                          │
  └────────────────────────────────────────────────────────────────┘

  Problem 1: Grafana CrashLoopBackOff
  ─────────────────────────────────────
  Root cause:  Two datasources both marked isDefault: true
               (one from Helm auto-config + one I added manually)

  How I found it:
    kubectl logs deploy/...-grafana -c grafana --previous
    → "datasource config is invalid. Only one datasource per
       organization can be marked as default"

  Fix:
    Removed manual grafana.datasources block from values.yaml
    → Helm chart manages datasource automatically
    → helm upgrade → pod restarted healthy → 3/3 Running

  ─────────────────────────────────────
  Problem 2: Dashboards not showing after upgrade
  ─────────────────────────────────────
  Root cause:  dashboardProviders path was /tmp/dashboards (wrong)
               Dashboard JSON files were at /var/lib/grafana/dashboards/default

  How I found it:
    kubectl exec into Grafana pod
    → ls /var/lib/grafana/dashboards/default/ showed .json files exist
    → But provisioning config was watching wrong directory

  Fix:
    Added dashboardProviders block with correct path in values.yaml
    → helm upgrade → Grafana reloaded dashboards ✅

  ─────────────────────────────────────
  Problem 3: Tested monitoring by simulating a crash
  ─────────────────────────────────────
  What I did:
    Injected bad liveness probe path (/bad-path) into product-service
    → Pod entered CrashLoopBackOff
    → Verified up=0 in Prometheus
    → Verified restart counter rising in kube-state-metrics
    → Saw spike in Grafana k8s-pods dashboard
    → Rolled back with kubectl rollout undo
    → Confirmed up=1 restored
```

**Say in the interview:**
> "I hit two real issues. First, Grafana was in CrashLoopBackOff. I read the pod logs and found the error said 'only one datasource can be marked as default' — I had accidentally added a duplicate by manually defining the Prometheus datasource in the Helm values file, which the chart already creates automatically. Removing the manual block and running helm upgrade fixed it. Second, dashboards were not showing. I exec'd into the Grafana pod, confirmed the JSON files existed in the right folder, but found the provisioning config was pointing to the wrong path. I added the correct dashboardProviders path and upgraded again. I also validated the full monitoring chain by deliberately crashing a pod with a bad liveness probe, watching the restart counter rise in Prometheus, and confirming the alert would fire."

---

### Interview Diagram 5 — "What is the difference between Prometheus and Grafana?"

**What the interviewer is asking:** Can you explain their distinct roles clearly?

```
  ┌─────────────────────┬──────────────────────────────────────────┐
  │   Prometheus        │   Grafana                                │
  ├─────────────────────┼──────────────────────────────────────────┤
  │ Collects metrics    │ Displays metrics                         │
  │ Stores time series  │ Does NOT store anything                  │
  │ Evaluates alerts    │ Visualizes — graphs, tables, gauges       │
  │ Pushes to           │ Queries Prometheus using PromQL          │
  │   Alertmanager      │ Can show data from many datasources      │
  │ Pull-based model    │ UI layer only                            │
  │ (goes to the app)   │ (reads from backends)                    │
  │                     │                                          │
  │ You can use it      │ You NEED a backend like Prometheus       │
  │ without Grafana     │ to show any data                         │
  └─────────────────────┴──────────────────────────────────────────┘

  Think of it like:
  Prometheus = database that collects and stores sensor readings
  Grafana    = dashboard screen that displays those readings
```

**Say in the interview:**
> "Prometheus is the metrics database. It scrapes metrics from your apps on a schedule, stores them as time series data, and evaluates alert rules. Grafana is a visualization tool — it has no storage of its own. It queries Prometheus using PromQL and renders the results as graphs and dashboards. You could use Prometheus without Grafana by running queries in the Prometheus UI, but Grafana gives you much better visualizations and alerting UI. Grafana can also connect to other datasources like Elasticsearch or Loki, so in production teams often use one Grafana instance to visualize data from multiple backends."

---

### Quick Interview Cheat Sheet

> Read this the night before the interview.

```
KEY NUMBERS TO REMEMBER
  Scrape interval:    15 seconds (how often Prometheus polls apps)
  Evaluation interval: 1 minute  (how often alert rules are checked)
  Alert "for" duration: 5 minutes (how long condition must be true before firing)
  Helm chart:         kube-prometheus-stack (bundles everything)
  Helm revision:      3 (upgraded twice to fix issues)
  Grafana version:    12.4.3
  Namespace:          monitoring (all stack components)
                      dev / test (all application workloads)

KEY COMMANDS
  Check all monitoring pods:  kubectl get pods -n monitoring
  Check app pods:             kubectl get pods -n dev
  Access Prometheus:          kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring
  Access Grafana:             kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
  Upgrade stack:              helm upgrade kube-prometheus-stack ... -f prometheus-stack-values.yaml
  Check Grafana logs:         kubectl logs deploy/kube-prometheus-stack-grafana -c grafana -n monitoring
  Rollback a deploy:          kubectl rollout undo deployment/NAME -n dev

KEY CONCEPTS
  ServiceMonitor:   CRD that tells Prometheus which services to scrape
                    Must be in "monitoring" namespace
                    Service must have "monitor: true" label
  kube-state-metrics: Exposes cluster state as metrics (pod counts, restart counts, etc.)
  node-exporter:    Exposes node-level metrics (CPU, memory, disk of the VM/node)
  Alertmanager:     Receives alerts from Prometheus, routes to Slack/PagerDuty/email
  TSDB:             Time Series Database — how Prometheus stores metric data on disk
  PromQL:           Query language for Prometheus
                    rate() for counters, avg_over_time() for gauges, absent() for missing

INTERVIEW ANSWER STRUCTURE (use for any monitoring question)
  1. What the tool does (one sentence)
  2. How it connects to the other tools (data flow)
  3. What you configured in this project
  4. A real problem you hit and how you fixed it
```

---

## Related Guides

- [grafana-troubleshooting.md](grafana-troubleshooting.md) — All Grafana issues and fixes
- [prometheus-troubleshooting.md](prometheus-troubleshooting.md) — All Prometheus issues and fixes
- [cross-namespace-networking.md](cross-namespace-networking.md) — How networking works between namespaces
- [prometheus-beginner-to-practitioner.md](prometheus-beginner-to-practitioner.md) — Learning guide for Prometheus
- [grafana-beginner-to-practitioner.md](grafana-beginner-to-practitioner.md) — Learning guide for Grafana
