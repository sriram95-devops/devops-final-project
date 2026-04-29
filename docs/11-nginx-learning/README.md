# NGINX Learning Path — Zero to Production

Welcome. This folder teaches you NGINX from scratch.
You do not need to know anything about NGINX to start here.
By the end you will be able to set up NGINX in every environment used in real production.

---

## What You Will Learn

| Step | Guide | What It Teaches |
|------|-------|-----------------|
| 1 | [01-what-is-nginx.md](01-what-is-nginx.md) | What NGINX is, how it works, key terms, architecture |
| 2 | [02-nginx-on-local-and-vscode.md](02-nginx-on-local-and-vscode.md) | Run NGINX on your local Windows machine and VS Code |
| 3 | [03-nginx-on-onprem-server.md](03-nginx-on-onprem-server.md) | Deploy on a Linux bare-metal or on-prem VM |
| 4 | [04-nginx-in-kubernetes-pods.md](04-nginx-in-kubernetes-pods.md) | NGINX Ingress Controller on Minikube — route traffic to multiple pods |
| 5 | [05-nginx-on-azure.md](05-nginx-on-azure.md) | Deploy on Azure VM and AKS (cloud production) |
| 6 | [06-nginx-debug-troubleshoot.md](06-nginx-debug-troubleshoot.md) | Read logs, fix errors, debug every environment |
| 7 | [07-nginx-cheatsheet.md](07-nginx-cheatsheet.md) | Quick reference — commands and config snippets |
| 8 | [08-nginx-testing-and-exercises.md](08-nginx-testing-and-exercises.md) | Hands-on exercises, visual output, load testing, Grafana dashboard |

---

## Recommended Learning Order

If you are new to NGINX, follow the steps in order:

```
Step 1 → Read "What is NGINX" (30 min)
Step 2 → Install on your local machine and test in VS Code (30 min)
Step 3 → Deploy on an on-prem Ubuntu server with multiple backends (1 hour)
Step 4 → Deploy NGINX Ingress in Kubernetes (Minikube) (1 hour)
Step 5 → Deploy on Azure VM and AKS (1–2 hours)
Step 6 → Learn to debug and troubleshoot (read alongside Steps 2–5)
Step 7 → Bookmark the cheat sheet for daily use
Step 8 → Run hands-on exercises — test visually, load test, watch live traffic (1 hour)
```

---

## What NGINX Does (One Line)

NGINX sits in front of your applications and routes incoming requests to the right container, server, or service.

---

## Related Guides

- [NGINX Ingress Complete Reference](../08-service-mesh-networking/nginx-ingress-guide.md) — advanced annotations and production config
- [Istio Service Mesh](../08-service-mesh-networking/istio-complete-guide.md) — east-west traffic between pods
- [Prometheus Monitoring](../02-monitoring-observability/prometheus-complete-guide.md) — scrape NGINX metrics
