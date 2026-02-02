# Kustomize GitOps - Simple Usage Guide

## ✅ Current Status

Your GitOps repository now uses Kustomize with a **simple, flat structure** at the repo root.

**Currently Deployed** (10 applications):
- ✅ Bootstrap: argocd-config, projects, postgresql
- ✅ Infrastructure: cilium, traefik, external-secrets, authentik, longhorn, netbird
- ✅ Root application (manages everything)
- ❌ All user apps disabled (as configured)

## 📝 How to Enable/Disable Apps

Edit **`/kustomization.yaml`** at the repo root:

```yaml
resources:
  # Infrastructure (always enabled)
  - infrastructure/traefik/traefik.yaml

  # Applications - Uncomment to enable:
  # - apps/homepage/application.yaml       # Dashboard
  # - apps/immich/application.yaml         # Photo management
  # - apps/filebrowser/application.yaml    # File browser
  # - apps/media-stack/application.yaml    # Media apps
  # - apps/ollama/application.yaml         # AI model
  # - apps/open-webui/application.yaml     # AI UI
```

**To enable an app:**
1. Remove the `#` from the line
2. Commit: `git add kustomization.yaml && git commit -m "Enable homepage" && git push`
3. ArgoCD syncs automatically

**To disable an app:**
1. Add `#` at the start of the line
2. Commit and push
3. ArgoCD will remove it (prune)

## 🧪 Test Before Deploying

```bash
# Preview what will be deployed
kubectl kustomize .

# Count how many Applications will be created
kubectl kustomize . | grep "kind: Application" | wc -l
```

## 📋 Available Applications

### Infrastructure (always enabled)
- cilium - Container networking
- traefik - Ingress controller (✅ running)
- external-secrets - Secrets management
- authentik - Authentication
- cloudnativepg - PostgreSQL operator
- longhorn - Storage
- reloader - Config reloader
- metrics-server - Metrics
- netbird - VPN

### GPU Support (enabled)
- nvidia-device-plugin
- nvidia-runtime

### Applications (all disabled - uncomment to enable)
- **homepage** - Service dashboard
- **immich** - Photo & video management
- **filebrowser** - File management
- **bambustudio** - 3D printing
- **karakeep** - Karaoke management
- **bentopdf** - PDF utilities
- **openhands** - AI agent
- **buildarr** - ARR automation
- **media-stack** - Plex, Radarr, Sonarr, etc. (parent app for 9 services)
- **ollama** - AI model runtime
- **open-webui** - LLM interface

## 🔍 Monitor Deployments

```bash
# List all ArgoCD applications
kubectl get applications -n argocd

# Check root app status
kubectl get application root -n argocd

# Watch for changes
kubectl get applications -n argocd -w

# Check Traefik (ingress)
kubectl get pods -n traefik
```

## 🎯 Common Tasks

### Enable Homepage Dashboard

```bash
vim kustomization.yaml
# Uncomment: - apps/homepage/application.yaml

git add kustomization.yaml
git commit -m "Enable homepage dashboard"
git push
```

### Enable Media Stack

```bash
vim kustomization.yaml
# Uncomment: - apps/media-stack/application.yaml

git add kustomization.yaml
git commit -m "Enable media stack (Plex, *ARR)"
git push
```

### Enable AI Stack

```bash
vim kustomization.yaml
# Uncomment both:
# - apps/ollama/application.yaml
# - apps/open-webui/application.yaml

git add kustomization.yaml
git commit -m "Enable AI stack (Ollama + WebUI)"
git push
```

## ⚠️ Important Notes

1. **Don't recreate parent apps**: The old `bootstrap/infrastructure.yaml` and `bootstrap/apps.yaml` have been removed. Don't recreate them - use Kustomize instead.

2. **Root app path**: The root application points to `.` (repo root), not `bootstrap/` or `overlays/`.

3. **commonLabels**: All resources get labeled with:
   - `managed-by: argocd`
   - `gitops-repo: gitops`
   - `environment: production`

4. **Immutable resources**: If you see errors about immutable fields (like DaemonSet selectors), delete the resource and let ArgoCD recreate it.

## 🐛 Troubleshooting

### Apps not deploying
```bash
# Check root app status
kubectl describe application root -n argocd

# Force refresh
kubectl patch application root -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Apps not being removed
```bash
# Check if old parent apps exist
kubectl get application infrastructure applications -n argocd

# If they exist, delete them
kubectl patch application infrastructure -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete application infrastructure -n argocd --force --grace-period=0
```

### Root app stuck
```bash
# Reset root app
kubectl delete application root -n argocd
kubectl apply -f bootstrap/root.yaml
```

## 📚 Files Structure

```
gitops/
├── kustomization.yaml           ⭐ Main config - edit this!
├── bootstrap/
│   ├── root.yaml                (root app definition)
│   ├── argocd-config.yaml
│   ├── projects.yaml
│   └── postgresql.yaml
├── infrastructure/
│   ├── traefik/traefik.yaml
│   ├── cilium/cilium.yaml
│   └── ...
└── apps/
    ├── homepage/application.yaml
    ├── immich/application.yaml
    └── ...
```

## ✨ Summary

- **One file to rule them all**: `/kustomization.yaml`
- **Comment/uncomment** lines to enable/disable apps
- **Commit and push** to deploy changes
- **ArgoCD syncs automatically** with prune enabled
- **Simple and effective** - no complex overlays or components

---

**Repository**: `git@github.com:storsteinbono/gitops.git`
**Main Config**: `/kustomization.yaml`
**Root App**: Points to `.` (repo root)
