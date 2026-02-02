# GitOps Repository

This repository manages Kubernetes applications using ArgoCD and Kustomize.

## 🚀 Quick Start

### Enable/Disable Apps

1. Edit `kustomization.yaml` in the root of the repo:

```yaml
resources:
  # ...
  # Applications (comment out to disable)
  - apps/ollama/application.yaml
  - apps/open-webui/application.yaml
  # - apps/media-stack/application.yaml
```

2. Commit and push to deploy changes:

```bash
git add kustomization.yaml
git commit -m "Enable ollama and open-webui"
git push
```

### Add New Application

1. **Create manifests** in `apps/<myapp>/manifests/`.
2. **Create ArgoCD Application** in `apps/<myapp>/application.yaml`.
3. **Enable in root** `kustomization.yaml`.
4. **Push** to deploy.

## 📁 Repository Structure

```
gitops/
├── kustomization.yaml          # ⭐ Root configuration (Edit this to enable/disable apps)
│
├── bootstrap/                  # ArgoCD Bootstrap
│   ├── root.yaml              # App-of-Apps parent application
│   └── ...
│
├── apps/                       # Application manifests & ArgoCD Apps
│   ├── ollama/
│   ├── open-webui/
│   └── ...
│
├── infrastructure/             # Infrastructure manifests & ArgoCD Apps
│   ├── cilium/
│   ├── traefik/
│   └── ...
│
├── projects/                   # ArgoCD Projects
└── scripts/                    # Helper scripts
```

## 📱 Deployed Applications

### Infrastructure (Core)
- **Cilium** - Container networking
- **Traefik** - Ingress controller
- **Authentik** - Identity & access management
- **External Secrets** - Secrets management
- **CloudNative-PG** - PostgreSQL operator
- **Longhorn** - Distributed storage

### Applications (Optional)
- **Ollama** - Local LLM runner
- **Open WebUI** - UI for LLMs
- **Media Stack** - (Disabled) Plex, *ARR suite, etc.

## 🔄 Sync Waves

Applications deploy in order based on sync waves:

- **-10**: Bootstrap & Critical Config (ArgoCD Config, Cilium)
- **-5**: Secrets & Ingress (External Secrets, Traefik)
- **-4**: Operators (CloudNativePG)
- **-3**: Data Layer (PostgreSQL, Authentik)
- **-2**: Storage (Longhorn)
- **-1**: Utilities (Reloader, Metrics Server)
- **0**: Standard Applications (Default)

## 🧰 Troubleshooting

### Application Not Syncing

```bash
# Refresh application
kubectl patch application root -n argocd --type=merge -p='{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### View Applications

```bash
kubectl get applications -n argocd
```
