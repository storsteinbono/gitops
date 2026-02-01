# Kustomize GitOps Configuration Guide

This repository now uses Kustomize to manage which applications are deployed to your cluster. This makes it easy to enable/disable apps without modifying individual manifests.

## Directory Structure

```
gitops/
├── base/                          # Base configuration
│   └── kustomization.yaml        # Includes core bootstrap files
├── overlays/                      # Environment-specific configs
│   └── production/
│       └── kustomization.yaml    # Controls what gets deployed
├── components/                    # Reusable components
│   ├── infrastructure/
│   │   ├── core/                 # Essential infrastructure (required)
│   │   ├── gpu/                  # NVIDIA GPU support (optional)
│   │   └── harbor/               # Container registry (optional)
│   ├── postgresql/               # Database layer
│   └── apps/                     # Applications
│       ├── homepage/
│       ├── immich/
│       ├── media-stack/
│       ├── ai-stack/
│       └── ...
└── bootstrap/                     # Original ArgoCD apps (referenced by components)
```

## How to Enable/Disable Applications

Edit `/overlays/production/kustomization.yaml` and comment/uncomment the components you want:

```yaml
components:
  # Core Infrastructure (always enabled)
  - ../../components/infrastructure/core

  # Optional Infrastructure
  - ../../components/infrastructure/gpu      # GPU support
  # - ../../components/infrastructure/harbor # Uncomment to enable

  # Applications
  - ../../components/apps/homepage           # Enabled
  # - ../../components/apps/media-stack     # Disabled (commented)
  - ../../components/apps/ai-stack           # Enabled
```

## Quick Start

### 1. Test Your Configuration

Build the Kustomize output to see what will be deployed:

```bash
cd overlays/production
kustomize build .
```

### 2. Deploy to ArgoCD

The root ArgoCD application will automatically sync from the Kustomize overlay. Just commit and push:

```bash
git add .
git commit -m "Configure apps via Kustomize"
git push
```

### 3. Verify in ArgoCD

Check the ArgoCD UI or CLI:

```bash
kubectl get applications -n argocd
```

## Common Tasks

### Enable Media Stack

Uncomment in `overlays/production/kustomization.yaml`:

```yaml
- ../../components/apps/media-stack
```

This will deploy: Plex, Radarr, Sonarr, Prowlarr, Overseerr, SABnzbd, Deluge, etc.

### Enable AI Stack (Ollama + Open WebUI)

Requires GPU components:

```yaml
# Enable GPU support first
- ../../components/infrastructure/gpu

# Then enable AI apps
- ../../components/apps/ai-stack
```

### Disable an Application

Simply comment it out:

```yaml
# - ../../components/apps/homepage  # Disabled
```

## Component Categories

### Infrastructure Components

**Core** (Always Required):
- Cilium (networking)
- Traefik (ingress)
- External Secrets
- Authentik (auth)
- CloudNative-PG
- Longhorn (storage)
- Reloader
- Metrics Server
- Netbird (VPN)

**GPU** (Optional):
- NVIDIA Device Plugin
- NVIDIA RuntimeClass

**Harbor** (Optional):
- Container Registry

### Application Components

**Dashboard**:
- homepage

**Media**:
- immich
- media-stack (Plex, *ARR suite, downloaders)

**AI**:
- ai-stack (Ollama, Open WebUI)
- openhands

**Utility**:
- filebrowser
- bambustudio
- bentopdf
- karakeep

## Creating New Components

To add a new application:

1. Create component directory:
```bash
mkdir -p components/apps/myapp
```

2. Create `components/apps/myapp/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - ../../../apps/myapp.yaml

labels:
  - pairs:
      app-category: utility
      app: myapp
```

3. Enable in overlay:
```yaml
# overlays/production/kustomization.yaml
components:
  - ../../components/apps/myapp
```

## Creating Environment Overlays

To create a staging environment:

```bash
mkdir -p overlays/staging
cat <<EOF > overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

components:
  # Select which apps for staging
  - ../../components/infrastructure/core
  - ../../components/apps/homepage

commonAnnotations:
  environment: staging

commonLabels:
  overlay: staging

namePrefix: staging-
EOF
```

## Kustomize Commands

### Build and Preview
```bash
# Preview what will be deployed
kustomize build overlays/production

# Save to file for inspection
kustomize build overlays/production > preview.yaml

# Check specific resource
kustomize build overlays/production | grep -A 20 "kind: Application"
```

### Validate
```bash
# Validate YAML syntax
kustomize build overlays/production | kubectl apply --dry-run=client -f -

# Check for errors
kustomize build overlays/production | kubectl apply --dry-run=server -f -
```

## Integration with ArgoCD

ArgoCD automatically detects and builds Kustomize directories. The root application should point to:

```yaml
spec:
  source:
    repoURL: <your-repo>
    targetRevision: main
    path: overlays/production  # Points to Kustomize overlay
```

ArgoCD will:
1. Detect `kustomization.yaml`
2. Run `kustomize build`
3. Apply the generated manifests
4. Monitor for changes

## Labels

All components add labels automatically:

- `managed-by: argocd`
- `gitops-repo: gitops`
- `overlay: production`
- Component-specific labels (e.g., `app: immich`, `app-category: media`)

Use labels for:
- Filtering: `kubectl get pods -l app-category=media`
- Monitoring dashboards
- Cost allocation
- RBAC policies

## Best Practices

1. **Keep base/ minimal** - Only core bootstrap files
2. **Use components for grouping** - Logical app/infrastructure groups
3. **Document dependencies** - Use labels (`requires: postgres`, `requires: gpu`)
4. **Test before committing** - Always run `kustomize build` first
5. **Use meaningful comments** - Explain why apps are disabled
6. **Version control overlays** - Track which apps are enabled per environment

## Troubleshooting

### Component not found
```bash
Error: unable to find one or more components
```
**Solution**: Check the path in your overlay - components use relative paths from the overlay directory.

### Duplicate resources
```bash
Error: duplicate resource
```
**Solution**: A resource is included multiple times. Check your components don't overlap.

### ArgoCD not syncing
```bash
# Force refresh
argocd app get root --refresh

# Check for errors
argocd app get root
```

## Migration Notes

The original bootstrap structure is preserved. Components reference existing Application manifests, so no disruption to running services.

To revert to non-Kustomize setup, update the root Application to point back to `bootstrap/` directory.
