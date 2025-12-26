# ArgoCD Configuration

This directory contains ArgoCD configuration managed through GitOps.

## Files

- **`argocd-cm-patch.yaml`** - ArgoCD ConfigMap with custom settings

## Custom Health Checks

### PersistentVolume
- **Healthy**: When phase is `Bound` or `Available`
- **Degraded**: When phase is `Released` or `Failed`
- **Progressing**: Otherwise

### Ingress
- **Healthy**: Always (Ingress doesn't have meaningful health status)

## Why This Matters

Without custom health checks:
- Applications with PVs or Ingress stay in "Progressing" state forever
- ArgoCD can't determine when the application is actually healthy

With custom health checks:
- Applications properly show "Healthy" status
- Better visibility into application state
- Proper health monitoring

## How It Works

1. The `argocd-config` Application (in `bootstrap/`) deploys this ConfigMap
2. ArgoCD automatically reloads the ConfigMap within 5-10 minutes
3. All applications immediately benefit from the new health checks

## Adding New Health Checks

To add a new custom health check, edit `argocd-cm-patch.yaml`:

```yaml
resource.customizations.health.<group>_<kind>: |
  hs = {}
  # Your Lua health check logic here
  hs.status = "Healthy"  # or "Progressing", "Degraded", "Suspended"
  hs.message = "Resource is ready"
  return hs
```

Common statuses:
- `Healthy` - Resource is working correctly
- `Progressing` - Resource is being created/updated
- `Degraded` - Resource has issues
- `Suspended` - Resource is intentionally stopped

## Persistence

✅ **This configuration is managed through GitOps**
- Changes are stored in Git
- Automatically applied through ArgoCD
- Survives cluster rebuilds
- Version controlled

## Manual Override (Emergency Only)

If you need to patch the ConfigMap manually:
```bash
kubectl patch configmap argocd-cm -n argocd --type=merge -p='...'
```

**Note**: Manual changes will be overwritten by GitOps within minutes!
