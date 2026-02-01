# GitOps Repository - Kustomize Enhanced

This repository manages Kubernetes applications using ArgoCD and Kustomize.

## 🚀 Quick Start

### Enable/Disable Apps

Edit `overlays/production/kustomization.yaml`:

```yaml
components:
  # Enabled apps
  - ../../components/apps/homepage
  - ../../components/apps/immich

  # Disabled apps (commented out)
  # - ../../components/apps/media-stack
  # - ../../components/apps/ai-stack
```

Commit and push to deploy changes.

### Test Configuration

```bash
./scripts/test-kustomize.sh
```

### Migrate to Kustomize

```bash
./scripts/switch-to-kustomize.sh
git add .
git commit -m "Switch to Kustomize"
git push
```

## 📁 Repository Structure

```
gitops/
├── overlays/production/          # ⭐ Main configuration file
│   └── kustomization.yaml        # Edit this to enable/disable apps
│
├── components/                   # Reusable app components
│   ├── infrastructure/
│   │   ├── core/                 # Required: Cilium, Traefik, Authentik, etc.
│   │   ├── gpu/                  # Optional: NVIDIA GPU support
│   │   └── harbor/               # Optional: Container registry
│   ├── postgresql/               # Database layer
│   └── apps/                     # Applications
│       ├── homepage/             # Dashboard
│       ├── immich/               # Photo management
│       ├── media-stack/          # Plex, *ARR suite, downloaders
│       ├── ai-stack/             # Ollama, Open WebUI
│       └── ...
│
├── base/                         # Base Kustomize configuration
├── bootstrap/                    # ArgoCD Applications (original)
├── apps/                         # Application manifests
├── infrastructure/               # Infrastructure manifests
├── projects/                     # ArgoCD Projects
└── scripts/                      # Helper scripts
```

## 📱 Deployed Applications

### Infrastructure

**Core** (Always Enabled):
- Cilium - Container networking
- Traefik - Ingress controller
- Authentik - Identity & access management
- External Secrets - Secrets management
- CloudNative-PG - PostgreSQL operator
- Longhorn - Distributed storage
- Reloader - ConfigMap/Secret watcher
- Metrics Server - Resource metrics
- Netbird - VPN management

**Optional**:
- NVIDIA GPU support (Device Plugin + RuntimeClass)
- Harbor - Container registry

### Applications

**Currently Enabled**:
- **Homepage** - Service dashboard
- **Immich** - Photo & video management
- **Filebrowser** - File management
- **BambuStudio** - 3D printing
- **Karakeep** - Karaoke management
- **BentoPDF** - PDF utilities
- **OpenHands** - AI agent platform

**Available (Disabled by Default)**:
- **Media Stack**: Plex, Radarr, Sonarr, Prowlarr, Overseerr, SABnzbd, Deluge, Pinchflat
- **AI Stack**: Ollama, Open WebUI (requires GPU)

## 🎯 Common Tasks

### Enable Media Stack

```bash
# Edit overlays/production/kustomization.yaml
# Uncomment:
- ../../components/apps/media-stack

# Deploy
git add overlays/production/kustomization.yaml
git commit -m "Enable media stack"
git push
```

### Enable AI Stack (Ollama + Open WebUI)

```bash
# Edit overlays/production/kustomization.yaml
# Ensure GPU support is enabled:
- ../../components/infrastructure/gpu

# Enable AI stack:
- ../../components/apps/ai-stack

# Deploy
git add overlays/production/kustomization.yaml
git commit -m "Enable AI stack"
git push
```

### Disable an Application

```bash
# Edit overlays/production/kustomization.yaml
# Comment out the component:
# - ../../components/apps/homepage

# Deploy
git add overlays/production/kustomization.yaml
git commit -m "Disable homepage"
git push
```

### Add New Application

1. **Create Application manifest** in `apps/`:
```bash
vim apps/myapp.yaml
```

2. **Create component**:
```bash
mkdir -p components/apps/myapp
cat <<EOF > components/apps/myapp/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - ../../../apps/myapp.yaml

labels:
  - pairs:
      app: myapp
      app-category: utility
EOF
```

3. **Enable in overlay**:
```bash
# Edit overlays/production/kustomization.yaml
# Add:
- ../../components/apps/myapp
```

4. **Deploy**:
```bash
git add .
git commit -m "Add myapp"
git push
```

## 📖 Documentation

- **[KUSTOMIZE_GUIDE.md](./KUSTOMIZE_GUIDE.md)** - Comprehensive Kustomize usage guide
- **[MIGRATION.md](./MIGRATION.md)** - Step-by-step migration instructions
- **[Context7 Kustomize Docs](https://context7.com/kubernetes-sigs/kustomize)** - Official documentation

## 🛠 Scripts

Located in `scripts/`:

- **`test-kustomize.sh`** - Test and validate Kustomize configuration
- **`switch-to-kustomize.sh`** - Automated migration to Kustomize

## 🔍 Monitoring

```bash
# List all applications
kubectl get applications -n argocd

# Check application health
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status

# Watch for changes
kubectl get applications -n argocd -w

# View specific app
kubectl describe application homepage -n argocd

# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Visit: https://localhost:8080
```

## 🏷 Labels

All resources are automatically labeled:

```yaml
managed-by: argocd
gitops-repo: gitops
overlay: production
```

Component-specific labels:
```yaml
# Infrastructure
component: infrastructure
tier: core|gpu|registry

# Applications
app: homepage|immich|...
app-category: dashboard|media|ai|utility
requires: postgres|gpu  # Dependencies
```

Query by labels:
```bash
# All media apps
kubectl get pods -n immich -l app-category=media

# All apps requiring postgres
kubectl get applications -n argocd -l requires=postgres

# GPU-enabled apps
kubectl get pods --all-namespaces -l requires=gpu
```

## 🔐 Secrets Management

Secrets are managed via External Secrets Operator:

- **Backend**: External secrets vault (configured in `infrastructure/external-secrets.yaml`)
- **Usage**: Apps reference `ExternalSecret` resources
- **PostgreSQL credentials**: Auto-generated and injected

## 💾 Storage

- **Longhorn**: Distributed block storage (default StorageClass)
- **NFS**: Shared storage for media apps
- **Local paths**: For specific workloads

## 🌐 Networking

- **Cilium**: CNI with eBPF dataplane
- **Traefik**: Ingress with automatic TLS
- **Authentik**: SSO integration for web UIs
- **Netbird**: VPN for remote access

## 📊 Database

**CloudNative-PG** manages PostgreSQL clusters:

- **Cluster**: HA PostgreSQL in `postgres` namespace
- **Databases**: Auto-provisioned via External Secrets
- **Apps using PostgreSQL**: Immich, Authentik, *ARR suite, Netbird

## 🎨 Customization

### Create Environment

```bash
# Staging environment
mkdir -p overlays/staging
cp overlays/production/kustomization.yaml overlays/staging/

# Edit to select different apps
vim overlays/staging/kustomization.yaml

# Create ArgoCD Application pointing to overlays/staging
```

### Override Configuration

Use Kustomize patches in components:

```yaml
# components/apps/myapp/kustomization.yaml
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: myapp
      spec:
        replicas: 3
    target:
      kind: Deployment
      name: myapp
```

## 🐛 Troubleshooting

### Kustomize Build Fails

```bash
# Test locally
cd overlays/production
kustomize build .

# Check for YAML syntax errors
kustomize build . | kubectl apply --dry-run=client -f -
```

### Application Not Syncing

```bash
# Refresh application
kubectl patch application root -n argocd --type=merge -p='{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller

# Force sync
kubectl get application root -n argocd -o yaml | kubectl replace -f -
```

### Resource Conflicts

```bash
# Check for duplicate resources
kustomize build overlays/production | grep "^kind:" | sort | uniq -c | grep -v "   1 "

# Identify the duplicate
kustomize build overlays/production | grep -B 5 "name: <duplicate-name>"
```

## 🤝 Contributing

1. Create feature branch
2. Make changes to components or overlays
3. Test: `./scripts/test-kustomize.sh`
4. Commit with conventional commits:
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation
   - `refactor:` - Code restructuring
5. Push and verify in ArgoCD

## 📝 Git Workflow

```bash
# Feature branch
git checkout -b feature/add-myapp

# Make changes
vim overlays/production/kustomization.yaml

# Test
./scripts/test-kustomize.sh

# Commit
git add .
git commit -m "feat: Add myapp to production overlay"

# Push
git push origin feature/add-myapp

# Merge to main
git checkout main
git merge feature/add-myapp
git push origin main

# ArgoCD automatically syncs
```

## 🔄 Sync Waves

Applications deploy in order based on sync waves:

- **-5**: External Secrets (dependencies for other apps)
- **-3**: Authentik (SSO provider)
- **0**: Most applications (default)
- **1+**: Apps depending on others

Set in Application manifest:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-5"
```

## 📈 Scaling

### Horizontal

Enable components as needed in `overlays/production/kustomization.yaml`.

### Vertical

Create additional overlays:
- `overlays/staging/`
- `overlays/development/`
- `overlays/production-us/`
- `overlays/production-eu/`

### Multi-cluster

Point ArgoCD Applications at different destination clusters:

```yaml
spec:
  destination:
    server: https://cluster-2.example.com
```

## 📦 Updates

### Update Application

```bash
# Edit app manifest
vim apps/homepage/manifests/deployment.yaml

# Changes auto-sync via ArgoCD
git add apps/homepage/
git commit -m "fix: Update homepage image version"
git push
```

### Update Infrastructure

```bash
# Edit infrastructure
vim infrastructure/traefik/manifests/deployment.yaml

# Deploy
git add infrastructure/traefik/
git commit -m "fix: Update Traefik configuration"
git push
```

### Update Kustomize Structure

```bash
# Modify components or overlays
vim components/apps/myapp/kustomization.yaml

# Test
./scripts/test-kustomize.sh

# Deploy
git add components/
git commit -m "refactor: Reorganize myapp component"
git push
```

## 🔒 Security

- **RBAC**: Configured via ArgoCD Projects
- **Network Policies**: Managed by Cilium
- **Secrets**: Never committed (External Secrets only)
- **TLS**: Automatic via Traefik + Let's Encrypt
- **Authentication**: Authentik SSO for all web UIs

## 📞 Support

- **Issues**: Document in GitHub Issues
- **Documentation**: See `KUSTOMIZE_GUIDE.md` and `MIGRATION.md`
- **Kustomize Help**: https://kubectl.docs.kubernetes.io/references/kustomize/
- **ArgoCD Help**: https://argo-cd.readthedocs.io/

---

**Repository**: `git@github.com:storsteinbono/gitops.git`
**Branch**: `main`
**Kustomize Overlay**: `overlays/production`
