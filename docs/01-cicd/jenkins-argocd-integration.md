# Jenkins and ArgoCD Integration Guide

A comprehensive guide to wiring Jenkins CI pipelines with ArgoCD GitOps delivery — covering architecture, configuration, complete Jenkinsfiles, webhook setup, App-of-Apps patterns, rollback procedures, and troubleshooting.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [ArgoCD Plugin in Jenkins](#3-argocd-plugin-in-jenkins)
4. [Complete Jenkinsfile Examples](#4-complete-jenkinsfile-examples)
5. [Webhook Setup](#5-webhook-setup)
6. [App-of-Apps Triggered by Jenkins](#6-app-of-apps-triggered-by-jenkins)
7. [Rollback Procedure from Jenkins](#7-rollback-procedure-from-jenkins)
8. [Verification Steps](#8-verification-steps)
9. [Troubleshooting](#9-troubleshooting)
10. [Cheat Sheet](#10-cheat-sheet)

---

## 1. Overview

### Why Jenkins + ArgoCD?

Jenkins and ArgoCD have complementary roles in a modern GitOps pipeline:

| Responsibility | Jenkins | ArgoCD |
|---------------|---------|--------|
| Source code checkout | ✅ | ❌ |
| Static code analysis (SonarQube) | ✅ | ❌ |
| Unit & integration tests | ✅ | ❌ |
| Docker image build | ✅ | ❌ |
| Image push to registry (JFrog) | ✅ | ❌ |
| Update Helm chart values in Git | ✅ | ❌ |
| Apply Kubernetes manifests | ❌ | ✅ |
| Drift detection & self-healing | ❌ | ✅ |
| Rollback via Git history | ❌ | ✅ |
| GitOps audit trail | ❌ | ✅ |
| Progressive delivery (canary) | ❌ | ✅ (with Argo Rollouts) |

### The Handoff Point

Jenkins' job ends when it commits a new image tag to Git. ArgoCD takes over from that commit, reconciling the cluster state. This separation of concerns means:

- **Jenkins never needs `kubectl` cluster access** (huge security win)
- **ArgoCD never needs to know about Jenkins** (it only watches Git)
- The Git repository becomes the **single source of truth**
- Every deployment is **auditable** via Git history

---

## 2. Architecture

### Mermaid Diagram

```mermaid
flowchart TD
    Dev["👨‍💻 Developer\npushes code"] -->|git push| GH["GitHub / GitLab\n(app repo)"]
    GH -->|webhook POST /github-webhook/| JK["Jenkins\nCI Server"]

    subgraph CI ["Jenkins CI Pipeline"]
        JK --> CO["1. Checkout\nsource code"]
        CO --> SQ["2. SonarQube\ncode scan"]
        SQ --> QG["3. Quality Gate\ncheck"]
        QG -->|pass| DB["4. Docker build\ndocker buildx"]
        DB --> JP["5. Push image\nto JFrog"]
        JP --> UH["6. Update Helm\nvalues.yaml in Git"]
        UH -->|git commit + push| GH2["GitHub\n(config/helm repo)"]
    end

    GH2 -->|ArgoCD polls every 3 min\nor webhook| ACD["ArgoCD\nGitOps Controller"]

    subgraph CD ["ArgoCD GitOps Delivery"]
        ACD --> DIFF["Diff:\nGit vs. Live state"]
        DIFF -->|out of sync| SYNC["Apply manifests\nto Kubernetes"]
        SYNC --> K8S["Kubernetes Cluster\n(AKS / Minikube)"]
        K8S -->|pull image| JF["JFrog Artifactory\nDocker Registry"]
    end

    K8S -->|health status| ACD
    ACD -->|notify| SLACK["Slack / Teams\nNotification"]
```

### ASCII Architecture Diagram

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                         JENKINS CI PIPELINE                          │
 │                                                                      │
 │  GitHub ──webhook──► Jenkins ──► SonarQube ──► Docker Build         │
 │                          │                          │                │
 │                          │                    Push to JFrog          │
 │                          │                          │                │
 │                          └──────► Update values.yaml in Git          │
 └─────────────────────────────────────────┬────────────────────────────┘
                                           │
                                     git push (image tag bump)
                                           │
                                           ▼
 ┌──────────────────────────────────────────────────────────────────────┐
 │                        ARGOCD GITOPS PIPELINE                        │
 │                                                                      │
 │  Git Repo ◄──poll/webhook──► ArgoCD ──diff──► Kubernetes Apply      │
 │                                  │                    │              │
 │                                  │               Pull image          │
 │                                  │               from JFrog          │
 │                                  │                    │              │
 │                                  └──── Health Check ◄─┘              │
 └──────────────────────────────────────────────────────────────────────┘
```

### Flow Summary

1. **Developer** pushes code to GitHub
2. **GitHub webhook** triggers Jenkins pipeline
3. **Jenkins** runs: checkout → SonarQube → quality gate → Docker build → push to JFrog → update Helm `values.yaml` → git push
4. **ArgoCD** detects the new commit in the config repo (polls every 3 minutes, or via webhook)
5. **ArgoCD** computes the diff between Git state and live Kubernetes state
6. **ArgoCD** applies the updated manifests to Kubernetes
7. **Kubernetes** pulls the new image from JFrog and rolls out the new version
8. **ArgoCD** reports health status back; sends Slack notification

---

## 3. ArgoCD Plugin in Jenkins

### Install the ArgoCD Plugin

1. In Jenkins, go to **Manage Jenkins → Plugins → Available plugins**
2. Search for `ArgoCD`
3. Install **Argo CD** plugin by `argoproj-labs`
4. Restart Jenkins when prompted

Or install via CLI (on the Jenkins server):

```bash
jenkins-plugin-cli --plugins argocd:latest
sudo systemctl restart jenkins
```

### Configure ArgoCD Server in Jenkins

1. Go to **Manage Jenkins → System → ArgoCD**
2. Click **Add ArgoCD Server**
3. Fill in:
   - **Name:** `argocd-prod`
   - **Server URL:** `https://argocd.yourdomain.com` (or `https://localhost:8080` for local)
   - **Credentials:** Add ArgoCD token credential (see below)
4. Click **Test Connection** → should show `Connected`
5. **Save**

### Create ArgoCD Credentials in Jenkins

#### Option A: ArgoCD Auth Token

```bash
# On the ArgoCD server, create a service account and generate token
argocd login argocd.yourdomain.com --username admin

# Create a Jenkins user
kubectl patch configmap argocd-cm -n argocd \
  --type merge \
  --patch '{"data":{"accounts.jenkins":"apiKey"}}'

# Grant RBAC permissions
kubectl patch configmap argocd-rbac-cm -n argocd \
  --type merge \
  --patch '{"data":{"policy.csv":"p, jenkins, applications, sync, */*, allow\np, jenkins, applications, get, */*, allow\np, jenkins, applications, action, */*, allow\n"}}'

# Generate the API token
JENKINS_TOKEN=$(argocd account generate-token --account jenkins)
echo "${JENKINS_TOKEN}"
```

In Jenkins UI:
1. **Manage Jenkins → Credentials → (global) → Add Credentials**
2. Kind: **Secret text**
3. Secret: paste the token
4. ID: `argocd-auth-token`
5. Description: `ArgoCD API Token for Jenkins`

#### Option B: ArgoCD Username/Password

In Jenkins UI:
1. Kind: **Username with password**
2. Username: `admin`
3. Password: ArgoCD admin password
4. ID: `argocd-credentials`

### Configure Git Credentials in Jenkins

For the pipeline to push changes back to GitHub:

1. **Manage Jenkins → Credentials → (global) → Add Credentials**
2. Kind: **Username with password**
3. Username: `your-github-username`
4. Password: GitHub Personal Access Token (`ghp_xxxxx`)
5. ID: `github-push-credentials`

For JFrog:

1. Kind: **Username with password**
2. Username: `your-jfrog-email`
3. Password: JFrog Access Token
4. ID: `jfrog-credentials`

---

## 4. Complete Jenkinsfile Examples

### 4.1 Production-Ready Full Pipeline Jenkinsfile

This Jenkinsfile covers the complete CI/CD flow:
`checkout → SonarQube → quality gate → Docker build → push to JFrog → update Helm values → ArgoCD sync`

```groovy
// Jenkinsfile — Production-ready GitOps pipeline
// Requires: Docker, ArgoCD CLI, SonarQube Scanner installed on Jenkins agent

pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: docker
      image: docker:27-dind
      securityContext:
        privileged: true
      volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
    - name: tools
      image: bitnami/kubectl:latest
      command: [sleep, infinity]
      env:
        - name: ARGOCD_SERVER
          valueFrom:
            secretKeyRef:
              name: argocd-config
              key: server
  volumes:
    - name: docker-sock
      hostPath:
        path: /var/run/docker.sock
'''
            defaultContainer 'tools'
        }
    }

    environment {
        // ─── Application ──────────────────────────────────────────────────
        APP_NAME          = 'sample-app'
        APP_VERSION       = ''   // populated from pom.xml or package.json

        // ─── Git ──────────────────────────────────────────────────────────
        GIT_APP_REPO      = 'https://github.com/your-org/sample-app.git'
        GIT_CONFIG_REPO   = 'https://github.com/your-org/devops-final-project.git'
        GIT_CREDENTIALS   = 'github-push-credentials'
        HELM_VALUES_PATH  = 'helm/sample-app/values-dev.yaml'

        // ─── JFrog ────────────────────────────────────────────────────────
        JFROG_SERVER      = 'yourname-devops.jfrog.io'
        JFROG_REPO        = 'docker-local'
        JFROG_CREDENTIALS = 'jfrog-credentials'

        // ─── ArgoCD ───────────────────────────────────────────────────────
        ARGOCD_SERVER     = 'argocd.yourdomain.com'
        ARGOCD_APP_DEV    = 'sample-app-dev'
        ARGOCD_APP_STAGING= 'sample-app-staging'
        ARGOCD_CREDENTIALS= 'argocd-auth-token'

        // ─── SonarQube ────────────────────────────────────────────────────
        SONAR_PROJECT_KEY = 'sample-app'
        SONAR_ENV         = 'sonarqube-server'

        // ─── Docker ───────────────────────────────────────────────────────
        IMAGE_TAG         = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        FULL_IMAGE        = "${JFROG_SERVER}/${JFROG_REPO}/${APP_NAME}:${IMAGE_TAG}"
    }

    options {
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        ansiColor('xterm')
    }

    stages {

        // ─────────────────────────────────────────────────────────────────
        stage('Checkout') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                    // Read version from package.json or pom.xml
                    if (fileExists('package.json')) {
                        env.APP_VERSION = sh(
                            script: "node -p \"require('./package.json').version\"",
                            returnStdout: true
                        ).trim()
                    } else if (fileExists('pom.xml')) {
                        env.APP_VERSION = sh(
                            script: "mvn help:evaluate -Dexpression=project.version -q -DforceStdout",
                            returnStdout: true
                        ).trim()
                    } else {
                        env.APP_VERSION = '1.0.0'
                    }
                }
                echo "Building ${APP_NAME} v${env.APP_VERSION} from commit ${env.GIT_COMMIT}"
                echo "Author: ${env.GIT_AUTHOR}"
                echo "Message: ${env.GIT_COMMIT_MSG}"
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('SonarQube Analysis') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                withSonarQubeEnv("${SONAR_ENV}") {
                    sh '''
                        # For Maven projects
                        if [ -f pom.xml ]; then
                            mvn sonar:sonar \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.projectName="${APP_NAME}" \
                              -Dsonar.projectVersion="${APP_VERSION}" \
                              -Dsonar.sources=src/main \
                              -Dsonar.tests=src/test \
                              -Dsonar.java.coveragePlugin=jacoco \
                              -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml

                        # For Node.js projects
                        elif [ -f package.json ]; then
                            npm ci
                            npm run test:coverage || true
                            sonar-scanner \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.sources=src \
                              -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info

                        # For Python projects
                        elif [ -f requirements.txt ]; then
                            pip install -r requirements.txt
                            pytest --cov=. --cov-report=xml:coverage.xml || true
                            sonar-scanner \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.python.coverage.reportPaths=coverage.xml
                        fi
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Quality Gate') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                failure {
                    echo "❌ SonarQube quality gate FAILED. Stopping pipeline."
                    // Notify Slack
                    slackSend(
                        channel: '#devops-alerts',
                        color: 'danger',
                        message: "Quality Gate FAILED for ${APP_NAME} | Branch: ${GIT_BRANCH} | <${BUILD_URL}|Build #${BUILD_NUMBER}>"
                    )
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Unit Tests') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                sh '''
                    if [ -f pom.xml ]; then
                        mvn test -Dmaven.test.failure.ignore=false
                    elif [ -f package.json ]; then
                        npm ci && npm test
                    elif [ -f requirements.txt ]; then
                        pip install -r requirements.txt
                        pytest tests/ -v --junitxml=test-results.xml
                    fi
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: '**/test-results.xml, **/surefire-reports/*.xml'
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Docker Build') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                container('docker') {
                    sh '''
                        echo "Building Docker image: ${FULL_IMAGE}"

                        docker buildx build \
                          --platform linux/amd64 \
                          --file Dockerfile \
                          --tag ${FULL_IMAGE} \
                          --tag ${JFROG_SERVER}/${JFROG_REPO}/${APP_NAME}:latest \
                          --label "git.commit=${GIT_COMMIT}" \
                          --label "git.branch=${GIT_BRANCH}" \
                          --label "build.number=${BUILD_NUMBER}" \
                          --label "build.url=${BUILD_URL}" \
                          --cache-from type=registry,ref=${JFROG_SERVER}/${JFROG_REPO}/${APP_NAME}:cache \
                          --cache-to   type=registry,ref=${JFROG_SERVER}/${JFROG_REPO}/${APP_NAME}:cache,mode=max \
                          --push=false \
                          .

                        echo "Docker build successful: ${FULL_IMAGE}"
                        docker images | grep ${APP_NAME}
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Container Security Scan') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                container('docker') {
                    sh '''
                        # Trivy scan — fails on CRITICAL vulnerabilities
                        docker run --rm \
                          -v /var/run/docker.sock:/var/run/docker.sock \
                          aquasec/trivy:latest image \
                            --exit-code 1 \
                            --severity CRITICAL \
                            --no-progress \
                            ${FULL_IMAGE} || \
                        (echo "⚠️ CRITICAL CVEs found — review before pushing" && exit 1)
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Push to JFrog') {
        // ─────────────────────────────────────────────────────────────────
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: "${JFROG_CREDENTIALS}",
                        usernameVariable: 'JFROG_USER',
                        passwordVariable: 'JFROG_TOKEN'
                    )]) {
                        sh '''
                            echo "${JFROG_TOKEN}" | docker login ${JFROG_SERVER} \
                              --username "${JFROG_USER}" \
                              --password-stdin

                            docker push ${FULL_IMAGE}
                            docker push ${JFROG_SERVER}/${JFROG_REPO}/${APP_NAME}:latest

                            echo "✅ Pushed: ${FULL_IMAGE}"

                            docker logout ${JFROG_SERVER}
                        '''
                    }
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Update Helm Values (Dev)') {
        // ─────────────────────────────────────────────────────────────────
            when {
                // Only update Helm values when building from main or develop branch
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${GIT_CREDENTIALS}",
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_TOKEN'
                )]) {
                    sh '''
                        # Clone the config repo (separate from app repo)
                        git config --global user.email "jenkins@ci.yourdomain.com"
                        git config --global user.name  "Jenkins CI"

                        CLONE_URL="https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/devops-final-project.git"

                        if [ -d config-repo ]; then rm -rf config-repo; fi
                        git clone "${CLONE_URL}" config-repo
                        cd config-repo

                        # Update the image tag in dev values file
                        sed -i "s|tag:.*|tag: \\"${IMAGE_TAG}\\"|g" ${HELM_VALUES_PATH}

                        # Verify the change
                        grep "tag:" ${HELM_VALUES_PATH}

                        # Commit and push
                        git add ${HELM_VALUES_PATH}
                        git diff --staged
                        git commit -m "ci: bump ${APP_NAME} image tag to ${IMAGE_TAG} [skip ci]

Build: ${BUILD_NUMBER}
Commit: ${GIT_COMMIT}
Author: ${GIT_AUTHOR}
"
                        git push origin main
                        echo "✅ Helm values updated and pushed to config repo"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('ArgoCD Sync (Dev)') {
        // ─────────────────────────────────────────────────────────────────
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                withCredentials([string(
                    credentialsId: "${ARGOCD_CREDENTIALS}",
                    variable: 'ARGOCD_TOKEN'
                )]) {
                    sh '''
                        # Install ArgoCD CLI if not present
                        if ! command -v argocd &>/dev/null; then
                            ARGOCD_VERSION=$(curl -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
                            curl -sSL -o /usr/local/bin/argocd \
                              "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64"
                            chmod +x /usr/local/bin/argocd
                        fi

                        # Login using token
                        argocd login ${ARGOCD_SERVER} \
                          --auth-token "${ARGOCD_TOKEN}" \
                          --insecure \
                          --grpc-web

                        # Sync dev application
                        echo "🔄 Syncing ArgoCD app: ${ARGOCD_APP_DEV}"
                        argocd app sync ${ARGOCD_APP_DEV} \
                          --timeout 120 \
                          --prune

                        # Wait for healthy status
                        argocd app wait ${ARGOCD_APP_DEV} \
                          --health \
                          --timeout 300

                        echo "✅ ArgoCD sync complete for ${ARGOCD_APP_DEV}"
                        argocd app get ${ARGOCD_APP_DEV}
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Integration Tests') {
        // ─────────────────────────────────────────────────────────────────
            when {
                branch 'main'
            }
            steps {
                sh '''
                    # Run integration tests against the dev environment
                    # Requires DEV_APP_URL to be set (from ArgoCD/Kubernetes service)
                    DEV_APP_URL="http://sample-app.dev.svc.cluster.local"

                    # Health check
                    curl -f "${DEV_APP_URL}/health" || \
                      (echo "❌ Integration health check failed" && exit 1)

                    # Smoke tests
                    curl -f "${DEV_APP_URL}/api/v1/status" | \
                      python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status']=='ok'"

                    echo "✅ Integration tests passed"
                '''
            }
        }

        // ─────────────────────────────────────────────────────────────────
        stage('Promote to Staging') {
        // ─────────────────────────────────────────────────────────────────
            when {
                branch 'main'
            }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: "${GIT_CREDENTIALS}", usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN'),
                    string(credentialsId: "${ARGOCD_CREDENTIALS}", variable: 'ARGOCD_TOKEN')
                ]) {
                    sh '''
                        CLONE_URL="https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/devops-final-project.git"

                        if [ -d config-repo-staging ]; then rm -rf config-repo-staging; fi
                        git clone "${CLONE_URL}" config-repo-staging
                        cd config-repo-staging

                        STAGING_VALUES="helm/sample-app/values-staging.yaml"
                        sed -i "s|tag:.*|tag: \\"${IMAGE_TAG}\\"|g" "${STAGING_VALUES}"

                        git add "${STAGING_VALUES}"
                        git commit -m "ci: promote ${APP_NAME} ${IMAGE_TAG} to staging [skip ci]"
                        git push origin main

                        # Sync staging — with manual approval gate (input step below)
                        argocd login ${ARGOCD_SERVER} \
                          --auth-token "${ARGOCD_TOKEN}" \
                          --insecure --grpc-web

                        argocd app sync ${ARGOCD_APP_STAGING} --timeout 120
                        argocd app wait ${ARGOCD_APP_STAGING} --health --timeout 300
                    '''
                }
            }
        }

    } // end stages

    post {
        success {
            echo "✅ Pipeline succeeded: ${APP_NAME} ${IMAGE_TAG} deployed to dev/staging"
            slackSend(
                channel: '#deployments',
                color: 'good',
                message: """
✅ *Deployment Successful*
App: `${APP_NAME}` | Tag: `${IMAGE_TAG}`
Branch: `${GIT_BRANCH}` | Build: <${BUILD_URL}|#${BUILD_NUMBER}>
Author: ${env.GIT_AUTHOR}
Commit: ${env.GIT_COMMIT_MSG}
""".stripIndent()
            )
        }
        failure {
            echo "❌ Pipeline failed: ${APP_NAME}"
            slackSend(
                channel: '#devops-alerts',
                color: 'danger',
                message: """
❌ *Deployment FAILED*
App: `${APP_NAME}` | Branch: `${GIT_BRANCH}`
Build: <${BUILD_URL}|#${BUILD_NUMBER}> | Stage: ${env.STAGE_NAME}
""".stripIndent()
            )
        }
        always {
            // Clean up workspace
            sh 'rm -rf config-repo config-repo-staging || true'
            cleanWs()
        }
    }
}
```

---

### 4.2 Triggering ArgoCD via REST API (curl)

When the ArgoCD CLI is not available on the Jenkins agent, use the REST API directly:

```groovy
stage('ArgoCD Sync via API') {
    steps {
        withCredentials([string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_TOKEN')]) {
            script {
                def argocdServer = "argocd.yourdomain.com"
                def appName = "sample-app-dev"

                // Trigger sync
                def syncResponse = sh(
                    script: """
                        curl -s -o sync_response.json -w "%{http_code}" \\
                          -X POST \\
                          -k \\
                          -H "Authorization: Bearer \${ARGOCD_TOKEN}" \\
                          -H "Content-Type: application/json" \\
                          -d '{
                            "revision": "${GIT_COMMIT}",
                            "prune": false,
                            "dryRun": false,
                            "strategy": {
                              "hook": {
                                "force": false
                              }
                            }
                          }' \\
                          "https://${argocdServer}/api/v1/applications/${appName}/sync"
                    """,
                    returnStdout: true
                ).trim()

                echo "Sync HTTP status: ${syncResponse}"
                if (syncResponse != "200") {
                    error("ArgoCD sync failed with HTTP ${syncResponse}")
                }

                // Poll for health status
                timeout(time: 5, unit: 'MINUTES') {
                    waitUntil {
                        def health = sh(
                            script: """
                                curl -s -k \\
                                  -H "Authorization: Bearer \${ARGOCD_TOKEN}" \\
                                  "https://${argocdServer}/api/v1/applications/${appName}" \\
                                  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status']['health']['status'])"
                            """,
                            returnStdout: true
                        ).trim()
                        echo "App health: ${health}"
                        return health == "Healthy"
                    }
                }
            }
        }
    }
}
```

---

### 4.3 Simplified Jenkinsfile (ArgoCD Plugin)

This version uses the official ArgoCD Jenkins plugin for cleaner syntax:

```groovy
pipeline {
    agent any

    environment {
        ARGOCD_SERVER = 'argocd.yourdomain.com'
        APP_NAME      = 'sample-app-dev'
        IMAGE_TAG     = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        JFROG_SERVER  = 'yourname-devops.jfrog.io'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'jfrog-credentials',
                    usernameVariable: 'JFROG_USER',
                    passwordVariable: 'JFROG_TOKEN'
                )]) {
                    sh '''
                        echo "${JFROG_TOKEN}" | docker login ${JFROG_SERVER} \
                          -u "${JFROG_USER}" --password-stdin
                        docker build -t ${JFROG_SERVER}/docker-local/${APP_NAME}:${IMAGE_TAG} .
                        docker push ${JFROG_SERVER}/docker-local/${APP_NAME}:${IMAGE_TAG}
                        docker logout ${JFROG_SERVER}
                    '''
                }
            }
        }

        stage('Update Git') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-push-credentials',
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_TOKEN'
                )]) {
                    sh '''
                        git config user.email "jenkins@ci.example.com"
                        git config user.name "Jenkins CI"
                        sed -i "s/tag:.*/tag: \\"${IMAGE_TAG}\\"/" helm/sample-app/values-dev.yaml
                        git add helm/sample-app/values-dev.yaml
                        git commit -m "ci: bump image tag to ${IMAGE_TAG} [skip ci]"
                        git push https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/devops-final-project.git HEAD:main
                    '''
                }
            }
        }

        stage('ArgoCD Sync') {
            steps {
                // Uses the ArgoCD Jenkins plugin
                argocdAppSync(
                    server: "${ARGOCD_SERVER}",
                    application: "${APP_NAME}",
                    credentialsId: 'argocd-auth-token',
                    waitForSync: true,
                    waitTimeout: 300
                )
            }
        }
    }
}
```

---

## 5. Webhook Setup

### 5.1 GitHub → Jenkins Webhook

#### In Jenkins

1. Go to your pipeline job → **Configure**
2. Under **Build Triggers**, check **GitHub hook trigger for GITScm polling**
3. Save

Ensure the GitHub plugin is installed: **Manage Jenkins → Plugins → GitHub Integration**.

#### In GitHub

1. Go to your repository → **Settings → Webhooks → Add webhook**
2. Fill in:
   - **Payload URL:** `https://jenkins.yourdomain.com/github-webhook/`
   - **Content type:** `application/json`
   - **Secret:** (optional but recommended — store in Jenkins as credential)
   - **Events:** Select **Just the push event** (or customize)
3. Click **Add webhook**
4. Verify the green checkmark after the first delivery

#### Using ngrok for Local Jenkins

If Jenkins is running locally and GitHub cannot reach it:

```bash
# Install ngrok
curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

# Start tunnel
ngrok http 8080
# Use the https://xxx.ngrok.io URL as your GitHub webhook URL
```

### 5.2 GitLab → Jenkins Webhook

1. In Jenkins, install the **GitLab** plugin
2. Go to **Manage Jenkins → Configure System → GitLab**:
   - **GitLab host URL:** `https://gitlab.yourdomain.com`
   - **Credentials:** Add a GitLab API token
3. In your Jenkins job, check **Build when a change is pushed to GitLab** under Build Triggers
4. Note the **GitLab webhook URL** shown (e.g., `https://jenkins.yourdomain.com/project/my-pipeline`)
5. In GitLab: **Repository → Settings → Webhooks**:
   - **URL:** the Jenkins webhook URL
   - **Trigger:** Push events
   - **Secret Token:** generate and add to Jenkins credentials

### 5.3 GitHub → ArgoCD Webhook (direct sync trigger)

Instead of ArgoCD polling every 3 minutes, add a webhook so ArgoCD syncs immediately on push.

#### In ArgoCD

ArgoCD webhook URL format: `https://<ARGOCD_SERVER>/api/webhook`

#### In GitHub

1. **Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://argocd.yourdomain.com/api/webhook`
3. **Content type:** `application/json`
4. **Secret:** Generate a random secret, configure in ArgoCD:

```bash
kubectl patch secret argocd-secret -n argocd \
  --type merge \
  --patch '{"stringData":{"webhook.github.secret":"your-webhook-secret"}}'
```

5. **Events:** Push events only

---

## 6. App-of-Apps Triggered by Jenkins

The App-of-Apps pattern lets Jenkins trigger deployment of an entire environment by updating a single parent Application manifest.

### Repository Structure

```
argocd/
├── app-of-apps-dev.yaml       # parent Application for dev
├── app-of-apps-staging.yaml   # parent Application for staging
└── apps/
    dev/
    ├── sample-app.yaml
    ├── backend-api.yaml
    └── redis.yaml
    staging/
    ├── sample-app.yaml
    ├── backend-api.yaml
    └── redis.yaml
```

### Parent Application YAML

```yaml
# argocd/app-of-apps-dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-apps
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/your-org/devops-final-project.git
    targetRevision: main
    path: argocd/apps/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Child Application YAML (auto-generated or manually placed)

```yaml
# argocd/apps/dev/sample-app.yaml
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

### Jenkins Stage to Update and Trigger App-of-Apps

```groovy
stage('Update All Apps (App-of-Apps)') {
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'github-push-credentials',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
        )]) {
            sh '''
                git config user.email "jenkins@ci.example.com"
                git config user.name "Jenkins CI"

                CLONE_URL="https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/devops-final-project.git"
                git clone "${CLONE_URL}" config-repo && cd config-repo

                # Update all dev app values files
                for values_file in helm/*/values-dev.yaml; do
                    APP_DIR=$(echo ${values_file} | cut -d'/' -f2)
                    # Only update apps that have the matching image name
                    if grep -q "${APP_NAME}" "${values_file}"; then
                        sed -i "s|tag:.*|tag: \\"${IMAGE_TAG}\\"|g" "${values_file}"
                        echo "Updated ${values_file}"
                    fi
                done

                git add -A
                git diff --staged
                git commit -m "ci: batch update dev images to ${IMAGE_TAG} [skip ci]" || \
                  echo "No changes to commit"
                git push origin main
            '''
        }
        // ArgoCD will auto-detect the App-of-Apps parent change and cascade to children
        withCredentials([string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_TOKEN')]) {
            sh '''
                argocd login ${ARGOCD_SERVER} --auth-token "${ARGOCD_TOKEN}" --insecure --grpc-web
                argocd app sync dev-apps
                argocd app wait dev-apps --health --timeout 60
                # Child apps sync automatically via App-of-Apps
            '''
        }
    }
}
```

---

## 7. Rollback Procedure from Jenkins

### Option 1: ArgoCD UI Rollback

1. Open ArgoCD UI → **Applications → sample-app-dev**
2. Click **History and Rollback**
3. Find the previous healthy deployment
4. Click **Rollback** on the desired revision
5. Confirm the rollback

### Option 2: ArgoCD CLI Rollback

```bash
# View deployment history
argocd app history sample-app-dev

# Output:
# ID  DATE                           REVISION
# 0   2024-01-15 10:00:00 +0000 UTC  main (abc1234)
# 1   2024-01-15 11:00:00 +0000 UTC  main (def5678)
# 2   2024-01-15 12:00:00 +0000 UTC  main (ghi9012)  ← current (broken)

# Rollback to ID 1
argocd app rollback sample-app-dev 1

# Wait for rollback to complete
argocd app wait sample-app-dev --health --timeout 180
argocd app get sample-app-dev
```

### Option 3: Jenkins Rollback Stage

Add a dedicated rollback stage that can be triggered manually:

```groovy
pipeline {
    agent any

    parameters {
        string(name: 'ROLLBACK_TO_TAG', defaultValue: '',
               description: 'Image tag to rollback to (e.g., abc1234). Leave empty to use ArgoCD history.')
        string(name: 'ARGOCD_HISTORY_ID', defaultValue: '',
               description: 'ArgoCD history ID to rollback to. Leave empty to use image tag.')
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'],
               description: 'Target environment for rollback')
    }

    environment {
        ARGOCD_SERVER = 'argocd.yourdomain.com'
        APP_NAME      = "sample-app-${params.ENVIRONMENT}"
    }

    stages {
        stage('Rollback Decision') {
            steps {
                script {
                    if (params.ARGOCD_HISTORY_ID) {
                        echo "Rolling back ${APP_NAME} to ArgoCD history ID: ${params.ARGOCD_HISTORY_ID}"
                    } else if (params.ROLLBACK_TO_TAG) {
                        echo "Rolling back ${APP_NAME} to image tag: ${params.ROLLBACK_TO_TAG}"
                    } else {
                        error("Must specify either ROLLBACK_TO_TAG or ARGOCD_HISTORY_ID")
                    }
                }
            }
        }

        stage('ArgoCD Rollback') {
            when {
                expression { params.ARGOCD_HISTORY_ID?.trim() }
            }
            steps {
                withCredentials([string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_TOKEN')]) {
                    sh '''
                        argocd login ${ARGOCD_SERVER} \
                          --auth-token "${ARGOCD_TOKEN}" \
                          --insecure --grpc-web

                        echo "Rolling back ${APP_NAME} to history ID ${ARGOCD_HISTORY_ID}"
                        argocd app rollback ${APP_NAME} ${ARGOCD_HISTORY_ID}
                        argocd app wait ${APP_NAME} --health --timeout 300

                        echo "✅ Rollback complete"
                        argocd app get ${APP_NAME}
                    '''
                }
            }
        }

        stage('Git Revert Rollback') {
            when {
                expression { params.ROLLBACK_TO_TAG?.trim() }
            }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'github-push-credentials',
                        usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN'),
                    string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_TOKEN')
                ]) {
                    sh '''
                        git config user.email "jenkins@ci.example.com"
                        git config user.name "Jenkins CI [Rollback]"

                        CLONE_URL="https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/devops-final-project.git"
                        git clone "${CLONE_URL}" rollback-repo && cd rollback-repo

                        VALUES_FILE="helm/sample-app/values-${ENVIRONMENT}.yaml"
                        echo "Reverting image tag to: ${ROLLBACK_TO_TAG}"
                        sed -i "s|tag:.*|tag: \\"${ROLLBACK_TO_TAG}\\"|g" "${VALUES_FILE}"

                        git add "${VALUES_FILE}"
                        git commit -m "ci: ROLLBACK ${APP_NAME} to ${ROLLBACK_TO_TAG} on ${ENVIRONMENT} [skip ci]

Rollback triggered by: Jenkins Build #${BUILD_NUMBER}
Reason: Manual rollback request
"
                        git push origin main

                        # Trigger immediate sync
                        argocd login ${ARGOCD_SERVER} \
                          --auth-token "${ARGOCD_TOKEN}" \
                          --insecure --grpc-web

                        argocd app sync ${APP_NAME}
                        argocd app wait ${APP_NAME} --health --timeout 300

                        echo "✅ Git-based rollback complete"
                    '''
                }
            }
        }
    }

    post {
        success {
            slackSend(
                channel: '#deployments',
                color: 'warning',
                message: "⏪ *ROLLBACK* completed: `${APP_NAME}` → `${params.ROLLBACK_TO_TAG ?: 'history-' + params.ARGOCD_HISTORY_ID}` | <${BUILD_URL}|Build #${BUILD_NUMBER}>"
            )
        }
        failure {
            slackSend(
                channel: '#devops-alerts',
                color: 'danger',
                message: "❌ *ROLLBACK FAILED*: `${APP_NAME}` | <${BUILD_URL}|Build #${BUILD_NUMBER}>"
            )
        }
    }
}
```

---

## 8. Verification Steps

### Post-Deployment Verification

```bash
# 1. Check ArgoCD application status
argocd app get sample-app-dev
# Expected: Sync Status: Synced, Health Status: Healthy

# 2. Check pods in target namespace
kubectl get pods -n dev -l app=sample-app
# Expected: all pods Running, READY shows container count

# 3. Verify correct image is deployed
kubectl get deployment sample-app -n dev -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: yourname-devops.jfrog.io/docker-local/sample-app:<IMAGE_TAG>

# 4. Check rollout status
kubectl rollout status deployment/sample-app -n dev --timeout=120s
# Expected: deployment "sample-app" successfully rolled out

# 5. Verify service is accessible
kubectl port-forward svc/sample-app -n dev 8081:80 &
curl -f http://localhost:8081/health
# Expected: {"status":"ok"}

# 6. Check recent events for errors
kubectl get events -n dev --sort-by='.lastTimestamp' | tail -20

# 7. Verify JFrog image was pulled successfully
kubectl describe pod -l app=sample-app -n dev | grep -A5 "Events:"
# Should NOT contain ImagePullBackOff or ErrImagePull
```

### Automated Post-Deployment Test Script

```bash
#!/usr/bin/env bash
# post-deploy-verify.sh
APP_NAME="${1:-sample-app}"
NAMESPACE="${2:-dev}"
EXPECTED_TAG="${3:-latest}"
ARGOCD_APP="${4:-sample-app-dev}"

set -euo pipefail

echo "═══ Post-Deployment Verification ═══"
echo "App: ${APP_NAME} | NS: ${NAMESPACE} | Tag: ${EXPECTED_TAG}"
echo ""

# ArgoCD health
HEALTH=$(argocd app get "${ARGOCD_APP}" -o json | jq -r '.status.health.status')
SYNC=$(argocd app get "${ARGOCD_APP}" -o json | jq -r '.status.sync.status')
echo "ArgoCD: Health=${HEALTH} Sync=${SYNC}"
[ "${HEALTH}" = "Healthy" ] || (echo "❌ App not Healthy" && exit 1)
[ "${SYNC}" = "Synced" ]    || (echo "❌ App not Synced" && exit 1)

# Pod status
PODS_READY=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.readyReplicas}')
PODS_DESIRED=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.replicas}')
echo "Pods: ${PODS_READY}/${PODS_DESIRED} ready"
[ "${PODS_READY}" = "${PODS_DESIRED}" ] || (echo "❌ Not all pods ready" && exit 1)

# Image tag
LIVE_TAG=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
echo "Image tag: ${LIVE_TAG} (expected: ${EXPECTED_TAG})"
[ "${LIVE_TAG}" = "${EXPECTED_TAG}" ] || (echo "❌ Wrong image tag deployed" && exit 1)

echo ""
echo "✅ All verification checks PASSED"
```

---

## 9. Troubleshooting

### Issue 1: Jenkins Cannot Push to Git (Update Helm Values)

**Symptom:** `remote: Permission to your-org/devops-final-project.git denied to jenkins-bot`

**Solution:**
```bash
# Ensure credentials in Jenkins are correct
# Token must have 'repo' scope in GitHub
# Test locally:
curl -H "Authorization: token ghp_your_token" \
  https://api.github.com/repos/your-org/devops-final-project

# If using SSH, ensure Jenkins agent has the SSH key
# Add the public key as a Deploy Key in GitHub → Settings → Deploy Keys
# Check "Allow write access"
```

---

### Issue 2: ArgoCD CLI Not Found in Jenkins Agent

**Symptom:** `argocd: command not found`

**Solution:**
```groovy
// Add to your stage:
sh '''
    if ! command -v argocd &>/dev/null; then
        ARGOCD_VERSION=$(curl -s \
          https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
        curl -sSL -o /usr/local/bin/argocd \
          "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64"
        chmod +x /usr/local/bin/argocd
        argocd version --client
    fi
'''
```

Or bake ArgoCD CLI into your Jenkins agent Docker image:

```dockerfile
FROM jenkins/inbound-agent:latest
USER root
RUN ARGOCD_VERSION=$(curl -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION) && \
    curl -sSL -o /usr/local/bin/argocd \
      "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd
USER jenkins
```

---

### Issue 3: ArgoCD Sync Fails After Jenkins Push

**Symptom:** ArgoCD shows `OutOfSync` but sync fails with `ComparisonError`

**Solution:**
```bash
# Check ArgoCD app events
argocd app get sample-app-dev -o json | jq '.status.conditions'

# Verify Git repo is accessible by ArgoCD
argocd repo list
argocd repo get https://github.com/your-org/devops-final-project.git

# Check if the commit made by Jenkins is visible
git log --oneline -5 # on the config repo
```

---

### Issue 4: `[skip ci]` Not Being Respected

**Symptom:** Jenkins triggers itself in a loop when it pushes Helm value updates.

**Solution:**
```groovy
// In Jenkinsfile, check commit message and abort if it's a CI commit
pipeline {
    stages {
        stage('Check Commit') {
            steps {
                script {
                    def commitMsg = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    if (commitMsg.contains('[skip ci]')) {
                        currentBuild.result = 'NOT_BUILT'
                        error("Skipping CI for auto-commit: ${commitMsg}")
                    }
                }
            }
        }
    }
}
```

Alternatively, configure the Jenkins job to skip builds with `[skip ci]` in the commit:
- In the Multibranch Pipeline → **Configure → Branch Sources → Behaviours**
- Add **Filter by message including `[skip ci]`**

---

### Issue 5: Docker Build Fails in Jenkins Agent

**Symptom:** `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`

**Solution:**
```yaml
# In Kubernetes pod template, mount the Docker socket:
volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock

containers:
  - name: docker
    image: docker:27-dind
    securityContext:
      privileged: true
    volumeMounts:
      - name: docker-sock
        mountPath: /var/run/docker.sock
```

Or use Kaniko for Docker-socket-free builds:

```groovy
stage('Kaniko Build & Push') {
    container('kaniko') {
        sh '''
            /kaniko/executor \
              --context . \
              --dockerfile Dockerfile \
              --destination ${JFROG_SERVER}/docker-local/${APP_NAME}:${IMAGE_TAG} \
              --cache=true \
              --cache-repo ${JFROG_SERVER}/docker-local/${APP_NAME}
        '''
    }
}
```

---

### Issue 6: JFrog Push Fails — 403 Forbidden

**Symptom:** `denied: Access denied. Not permitted to deploy`

```bash
# In JFrog UI: Administration → Repositories → docker-local
# Check: Deployment Policy = Allow Redeployment (for dev)
# Check: Exclude Patterns (ensure your image name is not excluded)

# Verify the user has the correct permissions:
# Administration → Identity and Access → Permissions
# Ensure the user or group has "Deploy" permission on docker-local
```

---

### Issue 7: Webhook Not Triggering Jenkins

**Symptom:** Pushes to GitHub do not trigger Jenkins builds.

```bash
# 1. Check webhook delivery in GitHub:
# Repository → Settings → Webhooks → (your webhook) → Recent Deliveries
# Look for non-200 responses

# 2. Verify Jenkins URL is reachable from GitHub
curl -I https://jenkins.yourdomain.com/github-webhook/

# 3. Check Jenkins system log
# Manage Jenkins → System Log → All Jenkins Logs
# Look for "Received POST" entries

# 4. Ensure the GitHub plugin is configured:
# Manage Jenkins → Configure System → GitHub → GitHub Servers
# Click "Test connection"

# 5. Check Jenkins job → GitHub hook trigger for GITScm polling is enabled
```

---

## 10. Cheat Sheet

### Jenkins Pipeline Commands

```groovy
// Trigger ArgoCD sync
argocdAppSync(server: 'argocd.domain.com', application: 'my-app', credentialsId: 'argocd-token')

// Update Helm values file
sh "sed -i 's/tag:.*/tag: \"${IMAGE_TAG}\"/' helm/app/values-dev.yaml"

// Docker build and push
sh "docker build -t ${REGISTRY}/${IMAGE}:${TAG} . && docker push ${REGISTRY}/${IMAGE}:${TAG}"

// Get current image tag
sh "kubectl get deployment app -n dev -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2"

// Wait for rollout
sh "kubectl rollout status deployment/app -n dev --timeout=120s"
```

### ArgoCD CLI from Jenkins

```bash
# Login with token
argocd login ${ARGOCD_SERVER} --auth-token ${ARGOCD_TOKEN} --insecure --grpc-web

# Sync app
argocd app sync ${APP_NAME} --timeout 120 --prune

# Wait for health
argocd app wait ${APP_NAME} --health --timeout 300

# Rollback
argocd app rollback ${APP_NAME} ${HISTORY_ID}

# Get sync status
argocd app get ${APP_NAME} -o json | jq .status.sync.status

# Get health status
argocd app get ${APP_NAME} -o json | jq .status.health.status
```

### ArgoCD API via curl from Jenkins

```bash
# Sync
curl -k -X POST \
  -H "Authorization: Bearer ${ARGOCD_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"prune":false,"dryRun":false}' \
  "https://${ARGOCD_SERVER}/api/v1/applications/${APP_NAME}/sync"

# Get health
curl -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" \
  "https://${ARGOCD_SERVER}/api/v1/applications/${APP_NAME}" \
  | jq .status.health.status

# List applications
curl -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" \
  "https://${ARGOCD_SERVER}/api/v1/applications" | jq '[.items[].metadata.name]'
```

### Environment Variables Reference

```
ARGOCD_SERVER           ArgoCD server URL (e.g., argocd.yourdomain.com)
ARGOCD_TOKEN            ArgoCD API token (Jenkins secret credential)
JFROG_SERVER            JFrog hostname (e.g., yourname-devops.jfrog.io)
JFROG_REPO              JFrog repository key (e.g., docker-local)
JFROG_USER              JFrog username (email)
JFROG_TOKEN             JFrog access token
GIT_CONFIG_REPO         URL of the Helm/config repository
GIT_CREDENTIALS         Jenkins credential ID for GitHub push access
APP_NAME                Application name
IMAGE_TAG               Docker image tag (usually short git commit SHA)
FULL_IMAGE              Full image path: JFROG_SERVER/JFROG_REPO/APP_NAME:IMAGE_TAG
ENVIRONMENT             Target environment: dev / staging / prod
```

### Jenkins Credential IDs Convention

| ID | Type | Usage |
|----|------|-------|
| `github-push-credentials` | Username/Password | Push Helm values to Git |
| `jfrog-credentials` | Username/Password | Docker login to JFrog |
| `argocd-auth-token` | Secret text | ArgoCD API/CLI authentication |
| `sonarqube-token` | Secret text | SonarQube analysis |
| `slack-webhook` | Secret text | Slack notifications |
| `azure-service-principal` | Username/Password | Azure CLI login in pipelines |

### Common Pipeline Failure Patterns

| Failure | Root Cause | Fix |
|---------|-----------|-----|
| Quality gate failed | Code coverage < threshold | Fix tests or update threshold |
| Docker push 403 | Wrong JFrog credentials | Re-check `jfrog-credentials` in Jenkins |
| Git push permission denied | Token lacks `repo` scope | Regenerate GitHub PAT with correct scope |
| ArgoCD login failed | Token expired or wrong | Regenerate ArgoCD token: `argocd account generate-token --account jenkins` |
| Webhook not triggering | Jenkins URL unreachable | Use ngrok locally; verify firewall for cloud |
| Build loop (`[skip ci]`) | CI commit triggers itself | Add commit message filter in Jenkins job config |
| Pod ImagePullBackOff | JFrog pull secret missing | Create `jfrog-registry` secret in target namespace |
| Rollout timeout | Pod crash or resource limits | `kubectl describe pod` + check resource limits |

---

*Last updated: 2024 | Maintained by the DevOps Engineering Team*
