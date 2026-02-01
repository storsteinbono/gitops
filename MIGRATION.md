# Migration to Kustomize

This guide helps you migrate your GitOps repository to use Kustomize for easier app management.

## What Changed

**Before**: ArgoCD root application pointed to `/bootstrap` directory and used directory recursion to discover all Application CRDs.

**After**: ArgoCD root application points to `/overlays/production` which uses Kustomize to selectively include components.

## Benefits

1. **Easy enable/disable**: Comment/uncomment lines in `overlays/production/kustomization.yaml`
2. **Logical grouping**: Apps organized by category (media, AI, utility, etc.)
3. **Dependency clarity**: Labels show what requires what (e.g., `requires: postgres`)
4. **Environment flexibility**: Easy to create staging/dev environments
5. **No manifest changes**: Original Application files remain untouched

## Migration Steps

### Step 1: Test Kustomize Build

```bash
# Make script executable
chmod +x scripts/test-kustomize.sh

# Run test
./scripts/test-kustomize.sh
```

This validates the Kustomize configuration without making any changes.

### Step 2: Review Component Selection

Edit `overlays/production/kustomization.yaml` to enable/disable apps:

```yaml
components:
  # Enabled apps have no # prefix
  - ../../components/apps/homepage

  # Disabled apps are commented out
  # - ../../components/apps/media-stack
```

**Currently Enabled** (based on your existing setup):
- Core infrastructure (Cilium, Traefik, Authentik, etc.)
- GPU support (NVIDIA)
- Harbor registry
- PostgreSQL
- Homepage
- Immich
- Filebrowser
- BambuStudio
- Karakeep
- BentoPDF
- OpenHands

**Currently Disabled** (comment out to disable):
- Media Stack (Plex, *ARR suite) - commented out by default
- AI Stack (Ollama, Open WebUI) - commented out by default

### Step 3: Switch to Kustomize (Automated)

```bash
# Make script executable
chmod +x scripts/switch-to-kustomize.sh

# Run migration
./scripts/switch-to-kustomize.sh
```

This script will:
1. Backup your current `root.yaml`
2. Replace it with Kustomize version
3. Test the build
4. Show you what to commit

### Step 4: Deploy

```bash
# Review the change
git diff bootstrap/root.yaml

# Commit everything
git add .
git commit -m "feat: Add Kustomize for easy app management

- Organized apps into components by category
- Added overlays/production for app selection
- Created helper scripts for testing and migration
- Documented usage in KUSTOMIZE_GUIDE.md
"

# Push to trigger ArgoCD sync
git push
```

### Step 5: Monitor Deployment

```bash
# Watch ArgoCD applications
kubectl get applications -n argocd -w

# Check root application
kubectl get application root -n argocd -o yaml

# View in ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then visit: https://localhost:8080
```

## What Happens During Migration

1. ArgoCD detects `root.yaml` change
2. Root app now syncs from `overlays/production` instead of `bootstrap`
3. Kustomize builds the configuration
4. Same Applications are created (no disruption)
5. Your services continue running

## Rollback Plan

If something goes wrong:

```bash
# Restore original root.yaml from backup
cp bootstrap/root.yaml.backup.* bootstrap/root.yaml

# Commit and push
git add bootstrap/root.yaml
git commit -m "Rollback to pre-Kustomize configuration"
git push
```

Your backup is automatically created at: `bootstrap/root.yaml.backup.<timestamp>`

## Manual Migration (Alternative)

If you prefer manual control:

1. **Edit root.yaml**:
```bash
vim bootstrap/root.yaml
```

2. **Change the path**:
```yaml
spec:
  source:
    path: overlays/production  # Changed from: bootstrap
    # Remove these lines:
    # directory:
    #   recurse: true
    #   exclude: 'root.yaml'
```

3. **Save and deploy**:
```bash
git add bootstrap/root.yaml
git commit -m "Switch to Kustomize"
git push
```

## Verifying Everything Works

After migration, verify:

```bash
# All expected apps are present
kubectl get applications -n argocd

# Check app health
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.health.status}{"\n"}{end}'

# View specific app
kubectl get application homepage -n argocd -o yaml

# Check Kustomize labels
kubectl get applications -n argocd -l managed-by=argocd
```

## Customizing After Migration

### Enable Media Stack

```bash
vim overlays/production/kustomization.yaml
```

Uncomment:
```yaml
- ../../components/apps/media-stack
```

Commit and push.

### Disable GPU Support

Comment out:
```yaml
# - ../../components/infrastructure/gpu
```

Commit and push.

### Create Staging Environment

```bash
mkdir -p overlays/staging
cp overlays/production/kustomization.yaml overlays/staging/
vim overlays/staging/kustomization.yaml
```

Adjust components for staging, then create an ArgoCD Application pointing to `overlays/staging`.

## Troubleshooting

### Build fails with "component not found"
**Cause**: Incorrect relative path in component reference.
**Fix**: Check paths in `overlays/production/kustomization.yaml` - they should be `../../components/...`

### ArgoCD shows "0 resources"
**Cause**: Kustomize build produced no output.
**Fix**: Run `./scripts/test-kustomize.sh` to debug. Check for YAML syntax errors.

### Apps not deploying
**Cause**: Component might be commented out.
**Fix**: Check `overlays/production/kustomization.yaml` - ensure components are not commented out.

### Duplicate resource errors
**Cause**: Resource included in multiple components.
**Fix**: Each Application YAML should only be referenced once across all components.

## FAQ

**Q: Will this disrupt running services?**
A: No. The same Application manifests are used, just organized differently.

**Q: Can I still edit individual app manifests?**
A: Yes. Edit the files in `apps/` or `infrastructure/` directories as before.

**Q: Do I need to install Kustomize locally?**
A: Not required. ArgoCD has Kustomize built-in. But it's helpful for testing: `scripts/test-kustomize.sh` will install it.

**Q: Can I revert to the old structure?**
A: Yes. Restore `bootstrap/root.yaml` from backup and push.

**Q: How do I add a new app?**
A:
1. Create the Application YAML in `apps/` (as before)
2. Create a component in `components/apps/myapp/`
3. Reference it in `overlays/production/kustomization.yaml`

**Q: Do I lose git history?**
A: No. All original files remain with full history. New files are added.

## Resources

- [Kustomize Guide](./KUSTOMIZE_GUIDE.md) - Detailed usage guide
- [Test Script](./scripts/test-kustomize.sh) - Validate configuration
- [Migration Script](./scripts/switch-to-kustomize.sh) - Automated migration
- [Kustomize Docs](https://kubectl.docs.kubernetes.io/references/kustomize/) - Official documentation
