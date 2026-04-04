# ChatOps Guide — Slack & MS Teams Integration with Jenkins, Kubernetes & Prometheus

## 1. Overview & Why You Need It

**ChatOps** brings DevOps operations into your chat platform — notifications, alerts, and even commands are handled in Slack or MS Teams channels.

| Platform | Best For | Jenkins Plugin | Alertmanager Support |
|----------|----------|---------------|---------------------|
| **Slack** | Most DevOps teams, rich formatting | ✅ Official plugin | ✅ Native receiver |
| **MS Teams** | Microsoft-heavy orgs | ✅ Office 365 plugin | ✅ Webhook receiver |

**Why ChatOps?**
- Instant visibility into build/deploy status
- Alerts land where the team already is
- Faster incident response (no log-in required to see first signal)
- Audit trail of events in chat history

---

## 2. Slack Setup

### 2.1 Create a Slack App & Bot

```
1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From Scratch"
3. App Name: "DevOps Bot"   Workspace: <your workspace>
4. Click "Create App"
5. In the app settings:
   - Go to "OAuth & Permissions"
   - Add Bot Token Scopes: chat:write, chat:write.public, channels:read
   - Click "Install to Workspace" → Allow
   - Copy the "Bot User OAuth Token" (starts with xoxb-)
6. Go to "Incoming Webhooks" → Toggle ON
   - Click "Add New Webhook to Workspace"
   - Select channel: #devops-alerts
   - Copy the Webhook URL
```

### 2.2 Test Webhook

```bash
# Test Slack webhook
WEBHOOK_URL="https://hooks.slack.com/services/<TEAM_ID>/<CHANNEL_ID>/<TOKEN>"

curl -X POST \
  -H 'Content-type: application/json' \
  --data '{"text":"🚀 Hello from DevOps Bot! Setup complete."}' \
  $WEBHOOK_URL
# Expected: "ok" response and message appears in Slack channel
```

---

## 3. Jenkins → Slack Integration

### 3.1 Install Slack Plugin in Jenkins

```
Jenkins → Manage Jenkins → Manage Plugins → Available
Search: "Slack Notification" → Install without restart
```

### 3.2 Configure Slack in Jenkins

```
Jenkins → Manage Jenkins → Configure System → Slack
- Workspace: your-workspace
- Credential: Add → Secret text → paste Bot User OAuth Token
- Default channel: #build-notifications
- Test Connection → verify "Success"
```

### 3.3 Jenkinsfile with Full Slack Notifications

```groovy
// Jenkinsfile — with Slack notifications at every stage
pipeline {
    agent any

    environment {
        SLACK_CHANNEL     = '#build-notifications'
        APP_NAME          = 'myapp'
        IMAGE_TAG         = "${BUILD_NUMBER}"
        JFROG_REGISTRY    = 'mycompany.jfrog.io'
        JFROG_REPO        = 'docker-local'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                slackSend(
                    channel: env.SLACK_CHANNEL,
                    color: '#439FE0',
                    message: "🔄 *Build Started*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}\nBranch: `${env.GIT_BRANCH}`\n<${env.BUILD_URL}|View Build>"
                )
            }
        }

        stage('SonarQube Scan') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh 'mvn sonar:sonar -Dsonar.projectKey=${APP_NAME}'
                }
            }
            post {
                success {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'good',
                        message: "✅ *SonarQube Passed*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}"
                    )
                }
                failure {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'danger',
                        message: "❌ *SonarQube FAILED*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}\n<${env.BUILD_URL}|View Logs>"
                    )
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

        stage('Docker Build & Push to JFrog') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'jfrog-credentials',
                    usernameVariable: 'JFROG_USER',
                    passwordVariable: 'JFROG_PASS'
                )]) {
                    sh """
                        docker build -t ${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG} .
                        docker login ${JFROG_REGISTRY} -u ${JFROG_USER} -p ${JFROG_PASS}
                        docker push ${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG}
                    """
                }
            }
            post {
                success {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'good',
                        message: "📦 *Image Pushed to JFrog*\nImage: `${JFROG_REGISTRY}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG}`"
                    )
                }
            }
        }

        stage('Deploy to Kubernetes via ArgoCD') {
            steps {
                sh """
                    # Update image tag in GitOps repo and let ArgoCD sync
                    argocd app set ${APP_NAME} \
                      --helm-set image.tag=${IMAGE_TAG} \
                      --server argocd.mycompany.com \
                      --auth-token ${ARGOCD_TOKEN}

                    argocd app sync ${APP_NAME} \
                      --server argocd.mycompany.com \
                      --auth-token ${ARGOCD_TOKEN}

                    argocd app wait ${APP_NAME} \
                      --health \
                      --timeout 300 \
                      --server argocd.mycompany.com \
                      --auth-token ${ARGOCD_TOKEN}
                """
            }
            post {
                success {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'good',
                        message: "🚀 *Deployment Successful!*\nApp: `${APP_NAME}` version `${IMAGE_TAG}`\nEnvironment: Production\n<${env.BUILD_URL}|View Build>"
                    )
                }
                failure {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'danger',
                        message: "💥 *Deployment FAILED!*\nApp: `${APP_NAME}` version `${IMAGE_TAG}`\nRolling back...\n<${env.BUILD_URL}|View Logs>"
                    )
                }
            }
        }
    }

    post {
        success {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'good',
                message: "✅ *Pipeline Complete - SUCCESS*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}\nDuration: ${currentBuild.durationString}\n<${env.BUILD_URL}|View Build>"
            )
        }
        failure {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'danger',
                message: "❌ *Pipeline FAILED*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}\n<${env.BUILD_URL}console|View Logs>"
            )
        }
        aborted {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'warning',
                message: "⚠️ *Pipeline Aborted*\nJob: `${env.JOB_NAME}` #${env.BUILD_NUMBER}"
            )
        }
    }
}
```

---

## 4. Prometheus Alertmanager → Slack

### 4.1 Alertmanager Config for Slack

```yaml
# alertmanager-config.yaml
# Routes Prometheus alerts to Slack channels by severity
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: slack-alerts
  namespace: monitoring
spec:
  route:
    groupBy: ['alertname', 'namespace']   # Group related alerts together
    groupWait: 30s                         # Wait before sending first notification
    groupInterval: 5m                      # Wait before sending new notifications for same group
    repeatInterval: 12h                    # Re-notify if alert still firing after 12h
    receiver: 'slack-critical'            # Default receiver
    routes:
    - matchers:
      - name: severity
        value: critical
      receiver: 'slack-critical'           # Critical alerts → #alerts-critical
    - matchers:
      - name: severity
        value: warning
      receiver: 'slack-warning'            # Warnings → #alerts-warning
    - matchers:
      - name: alertname
        value: Watchdog
      receiver: 'null'                     # Suppress watchdog alert

  receivers:
  - name: 'null'                           # Blackhole receiver

  - name: 'slack-critical'
    slackConfigs:
    - apiURL:
        name: alertmanager-slack-secret    # K8s Secret with webhook URL
        key: webhook-url
      channel: '#alerts-critical'
      sendResolved: true                   # Notify when alert is resolved
      title: '{{ template "slack.default.title" . }}'
      text: |
        {{ range .Alerts }}
        *Alert:* {{ .Annotations.summary }}
        *Severity:* `{{ .Labels.severity }}`
        *Namespace:* `{{ .Labels.namespace }}`
        *Description:* {{ .Annotations.description }}
        *Runbook:* {{ .Annotations.runbook_url }}
        {{ end }}
      color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'

  - name: 'slack-warning'
    slackConfigs:
    - apiURL:
        name: alertmanager-slack-secret
        key: webhook-url
      channel: '#alerts-warning'
      sendResolved: true
      title: '⚠️ Warning: {{ .GroupLabels.alertname }}'
      text: |
        {{ range .Alerts }}
        *Alert:* {{ .Annotations.summary }}
        *Details:* {{ .Annotations.description }}
        {{ end }}
      color: 'warning'
```

```bash
# Create Secret with Slack webhook URL
kubectl create secret generic alertmanager-slack-secret \
  --from-literal=webhook-url="https://hooks.slack.com/services/T00000/B00000/XXXX" \
  --namespace monitoring
```

### 4.2 Sample Alert Rules That Route to Slack

```yaml
# prometheus-alert-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: k8s-alerts
  namespace: monitoring
  labels:
    release: prometheus                    # Must match Prometheus operator selector
spec:
  groups:
  - name: kubernetes-pods
    interval: 30s
    rules:
    - alert: PodCrashLoopBackOff
      expr: |
        rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 5
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"
        description: "Pod has restarted {{ $value }} times in 15 minutes"
        runbook_url: "https://wiki.mycompany.com/runbooks/pod-crash-loop"

    - alert: PodNotReady
      expr: kube_pod_status_ready{condition="false"} == 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is not ready"
        description: "Pod has been not ready for 5 minutes"

    - alert: NodeHighCPU
      expr: |
        100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Node {{ $labels.node }} CPU is {{ $value }}%"
        description: "Node CPU above 85% for 5 minutes"

    - alert: DeploymentReplicasMismatch
      expr: |
        kube_deployment_spec_replicas != kube_deployment_status_available_replicas
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} replicas mismatch"
        description: "Expected {{ $value }} replicas but available count differs"
```

---

## 5. MS Teams Integration

### 5.1 Create Teams Incoming Webhook

```
1. Open MS Teams
2. Go to a channel (e.g., #devops-alerts)
3. Click "..." → Connectors → Incoming Webhook → Configure
4. Name: "DevOps Alerts"   Upload an icon (optional)
5. Click "Create" → Copy the Webhook URL
```

### 5.2 Test Teams Webhook

```bash
TEAMS_WEBHOOK="https://mycompany.webhook.office.com/webhookb2/xxx/IncomingWebhook/yyy/zzz"

curl -X POST \
  -H 'Content-Type: application/json' \
  --data '{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "0076D7",
    "summary": "DevOps Bot Test",
    "sections": [{
      "activityTitle": "🚀 DevOps Bot Connected",
      "activitySubtitle": "MS Teams integration is working!",
      "activityImage": "https://www.jenkins.io/images/logos/jenkins/jenkins.png",
      "facts": [{
        "name": "Status",
        "value": "Connected"
      }]
    }]
  }' \
  $TEAMS_WEBHOOK
# Expected: "1" response and card appears in Teams channel
```

### 5.3 Jenkins → MS Teams (Jenkinsfile)

```groovy
// Send Teams notification from Jenkinsfile
def sendTeamsNotification(String status, String color, String emoji) {
    def teamsWebhook = credentials('teams-webhook-url')
    def payload = """
    {
        "@type": "MessageCard",
        "@context": "http://schema.org/extensions",
        "themeColor": "${color}",
        "summary": "Jenkins Pipeline ${status}",
        "sections": [{
            "activityTitle": "${emoji} Pipeline ${status}: ${env.JOB_NAME}",
            "activitySubtitle": "Build #${env.BUILD_NUMBER}",
            "facts": [
                {"name": "Branch", "value": "${env.GIT_BRANCH}"},
                {"name": "Duration", "value": "${currentBuild.durationString}"},
                {"name": "Status", "value": "${status}"}
            ],
            "markdown": true
        }],
        "potentialAction": [{
            "@type": "OpenUri",
            "name": "View Build",
            "targets": [{"os": "default", "uri": "${env.BUILD_URL}"}]
        }]
    }
    """
    sh "curl -X POST -H 'Content-Type: application/json' --data '${payload}' ${teamsWebhook}"
}

pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean package'
            }
        }
    }
    post {
        success { sendTeamsNotification('SUCCESS', '00FF00', '✅') }
        failure { sendTeamsNotification('FAILED', 'FF0000', '❌') }
    }
}
```

### 5.4 Alertmanager → MS Teams

```yaml
# alertmanager-teams-receiver.yaml
# Uses webhook_configs with Teams-specific JSON format
receivers:
- name: 'teams-critical'
  webhook_configs:
  - url: 'https://mycompany.webhook.office.com/webhookb2/xxx'
    send_resolved: true
    http_config:
      bearer_token_file: /dev/null
    # Note: Alertmanager sends JSON; Teams expects MessageCard format
    # Use a proxy/adapter like prometheus-msteams for rich formatting

# Better option: prometheus-msteams adapter
# Converts Prometheus alerts to Teams MessageCard format
```

```bash
# Install prometheus-msteams adapter
helm repo add prometheus-msteams https://prometheus-msteams.github.io/prometheus-msteams/
helm install prometheus-msteams prometheus-msteams/prometheus-msteams \
  --namespace monitoring \
  --set connectors[0].name=teams-critical \
  --set connectors[0].webhookURL="https://mycompany.webhook.office.com/webhookb2/xxx"

# Then configure Alertmanager to send to the adapter
# url: http://prometheus-msteams:2000/teams-critical
```

---

## 6. K8s Events → Slack (kubernetes-event-exporter)

```yaml
# k8s-event-exporter.yaml
# Exports K8s cluster events (pod failures, OOMKill, etc.) to Slack
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: event-exporter
  template:
    metadata:
      labels:
        app: event-exporter
    spec:
      serviceAccountName: event-exporter
      containers:
      - name: event-exporter
        image: ghcr.io/resmoio/kubernetes-event-exporter:latest
        args:
        - -conf=/data/config.yaml
        volumeMounts:
        - name: config
          mountPath: /data
      volumes:
      - name: config
        configMap:
          name: event-exporter-config
---
# RBAC for event-exporter
apiVersion: v1
kind: ServiceAccount
metadata:
  name: event-exporter
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: event-exporter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: event-exporter
subjects:
- kind: ServiceAccount
  name: event-exporter
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: event-exporter
rules:
- apiGroups: [""]
  resources: ["events", "namespaces", "pods", "nodes"]
  verbs: ["get", "list", "watch"]
---
# Config for event-exporter
apiVersion: v1
kind: ConfigMap
metadata:
  name: event-exporter-config
  namespace: monitoring
data:
  config.yaml: |
    logLevel: info
    logFormat: json
    route:
      routes:
      - match:
        - receiver: "slack"
          reason:
          - "BackOff"
          - "OOMKilling"
          - "Failed"
          - "FailedScheduling"
          - "Unhealthy"
    receivers:
    - name: "slack"
      slack:
        webhookURL: "https://hooks.slack.com/services/T00000/B00000/XXXX"
        channel: "#k8s-events"
        layout:
          text: |
            *{{ .InvolvedObject.Kind }}*: `{{ .InvolvedObject.Name }}` ({{ .InvolvedObject.Namespace }})
            *Event*: {{ .Reason }} — {{ .Message }}
            *Time*: {{ .LastTimestamp }}
```

```bash
kubectl apply -f k8s-event-exporter.yaml

# Trigger a test event (delete a pod to see restart event)
kubectl delete pod -l app=myapp
# Watch for Slack notification in #k8s-events
```

---

## 7. ArgoCD → Slack Notifications

```yaml
# argocd-notifications-config.yaml
# ArgoCD has a built-in notifications controller
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token                  # References secret below
  template.app-deployed: |
    slack:
      attachments: |
        [{
          "title": "{{.app.metadata.name}} Deployed Successfully",
          "color": "#18be52",
          "fields": [
            {"title": "Sync Status", "value": "{{.app.status.sync.status}}", "short": true},
            {"title": "Health", "value": "{{.app.status.health.status}}", "short": true},
            {"title": "Revision", "value": "{{.app.status.sync.revision}}", "short": true}
          ]
        }]
  template.app-sync-failed: |
    slack:
      attachments: |
        [{
          "title": "{{.app.metadata.name}} Sync FAILED",
          "color": "#E96D76",
          "text": "{{.app.status.operationState.message}}"
        }]
  trigger.on-deployed: |
    - description: Application is synced and healthy
      send: [app-deployed]
      when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
  trigger.on-sync-failed: |
    - description: Application sync has failed
      send: [app-sync-failed]
      when: app.status.operationState.phase in ['Error', 'Failed']
  subscriptions: |
    - recipients:
      - slack:#argocd-deployments
      triggers:
      - on-deployed
      - on-sync-failed
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: "xoxb-your-bot-token-here"
```

```bash
kubectl apply -f argocd-notifications-config.yaml

# Install ArgoCD notifications controller (if not included)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/release-1.2/manifests/install.yaml

# Test notification
argocd app sync myapp
# Watch for notification in #argocd-deployments Slack channel
```

---

## 8. Real-World Scenarios

### Scenario 1: Full Deployment Pipeline in Slack

**What you'll see in Slack:**
```
🔄 Build Started | myapp #42 | branch: main
✅ SonarQube Passed | Quality Gate: OK
📦 Image Pushed | mycompany.jfrog.io/docker-local/myapp:42
🚀 Deployment Successful! | myapp v42 | Production
✅ Pipeline Complete | Duration: 4m 32s
```

```bash
# Trigger the pipeline
# 1. git push to main branch
# 2. Jenkins webhook fires
# 3. Watch Slack channel for sequential notifications
```

### Scenario 2: K8s Pod Crash → Slack Alert → kubectl Debug

```bash
# Simulate a pod crash
kubectl run crasher \
  --image=busybox \
  --restart=Always \
  -- sh -c "exit 1"

# This triggers:
# 1. K8s event-exporter detects BackOff event → Slack #k8s-events
# 2. Prometheus PodCrashLoopBackOff rule fires (after 5 restarts) → Alertmanager → Slack #alerts-critical

# Slack alert text will contain pod name and namespace
# DevOps engineer responds with kubectl commands:
kubectl describe pod crasher
kubectl logs crasher --previous
kubectl delete pod crasher
```

### Scenario 3: Interactive Slack Bot Commands

```bash
# Using Slack slash commands or a bot framework (e.g., Bolt for Python)
# Example bot commands:

# /deploy myapp staging   → triggers Jenkins job
# /rollback myapp prod    → triggers kubectl rollout undo
# /status myapp           → returns ArgoCD app status
# /logs myapp prod        → returns last 20 log lines from prod pod

# Simple implementation using Jenkins remote trigger:
# Slack → Slash command → Webhook → Jenkins API:
curl -X POST \
  "https://jenkins.mycompany.com/job/deploy-myapp/buildWithParameters" \
  --user "jenkins-user:jenkins-api-token" \
  --data "ENV=staging&APP=myapp"
```

---

## 9. Troubleshooting Guide

| Issue | Symptom | Fix |
|-------|---------|-----|
| Slack plugin not sending | No messages in channel | Check Jenkins credentials; verify bot is in channel |
| Webhook returns 403 | `403 Forbidden` from Slack | Regenerate webhook; check app is still installed |
| Alertmanager not routing | Alerts not in Slack | Check `kubectl logs -n monitoring alertmanager-xxx`; verify receiver name matches |
| Teams card not rendering | Plain text in Teams | Use AdaptiveCard format or install prometheus-msteams adapter |
| K8s event exporter missing events | Events not in Slack | Check ServiceAccount RBAC; verify event reasons match config |
| ArgoCD notifications silent | No deploy alerts | Check `argocd-notifications-controller` pod logs; verify secret key name |
| Rate limiting from Slack | 429 Too Many Requests | Add `groupInterval` and `repeatInterval` to Alertmanager config |
| Bot not in channel | `channel_not_found` | Add bot to channel: `/invite @DevOpsBot` |
| Teams webhook expired | `400 Bad Request` | Connectors expire; recreate webhook in Teams |
| Missing emoji in Jenkins | `?` in message | Use Unicode emoji directly or plain text |

---

## 10. Cheat Sheet

```bash
# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"test"}' \
  https://hooks.slack.com/services/T00000/B00000/XXXXX

# Test Teams webhook
curl -X POST -H 'Content-Type: application/json' \
  --data '{"text":"test"}' \
  https://mycompany.webhook.office.com/webhookb2/xxx

# Check Alertmanager config
kubectl exec -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0 \
  -- amtool check-config /etc/alertmanager/config_out/alertmanager.env.yaml

# Reload Alertmanager config
kubectl rollout restart statefulset alertmanager-prometheus-kube-prometheus-alertmanager \
  -n monitoring

# Check ArgoCD notifications controller
kubectl logs -n argocd deployment/argocd-notifications-controller --tail=50

# Send test alert from Alertmanager
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  --data '[{
    "labels": {"alertname": "TestAlert", "severity": "warning"},
    "annotations": {"summary": "Test alert from CLI"}
  }]'

# List active alerts
kubectl port-forward svc/alertmanager-operated 9093:9093 -n monitoring &
curl http://localhost:9093/api/v2/alerts
```

| Notification Type | Tool | Channel |
|------------------|------|---------|
| Build success/fail | Jenkins Slack plugin | #build-notifications |
| Quality gate alert | SonarQube webhook | #code-quality |
| Deploy success/fail | ArgoCD notifications | #deployments |
| K8s pod crashes | kubernetes-event-exporter | #k8s-events |
| Infra alerts (CPU/mem) | Prometheus Alertmanager | #alerts-critical / #alerts-warning |
| Grafana alert | Grafana alert channel | #monitoring |
