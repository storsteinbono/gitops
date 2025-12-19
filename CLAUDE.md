# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **GitOps repository** implementing ArgoCD's **App of Apps pattern** for managing Kubernetes applications. All Kubernetes manifests are stored in Git, and ArgoCD automatically syncs changes to the cluster.

**Key Principle**: This repository is declarative configuration only - no application code. Changes to this repository directly affect cluster state.

## Repository Architecture

### Three-Tier Hierarchy

```
root (bootstrap/root.yaml)
├── infrastructure (bootstrap/infrastructure.yaml)
│   ├── longhorn (distributed storage)
│   └── sealed-secrets (encrypted secrets management)
└── applications (bootstrap/apps.yaml)
    └── [user applications in apps/]
```

**Root Application**: Manages two child applications (`infrastructure` and `applications`)
**Infrastructure App**: Auto-discovers and deploys all YAML files in `infrastructure/` directory
**Applications App**: Auto-discovers and deploys all YAML files in `apps/` directory

### Directory Structure

- **`bootstrap/`** - Root App of Apps manifests (creates parent applications)
  - `root.yaml` - Parent application managing everything
  - `infrastructure.yaml` - App of Apps for infrastructure components
  - `apps.yaml` - App of Apps for user applications

- **`infrastructure/`** - Infrastructure component applications
  - Each file defines an ArgoCD Application for infrastructure (storage, networking, etc.)
  - Current: `longhorn.yaml` (storage), `sealed-secrets.yaml` (secrets)

- **`apps/`** - User application deployments
  - Each subdirectory or ArgoCD Application manifest represents an app
  - Example: `apps/example-app/` contains full Kubernetes manifests

- **`projects/`** - ArgoCD AppProject definitions
  - Define RBAC, source repos, and destination restrictions
  - `default.yaml` - Default project for general apps
  - `infrastructure.yaml` - Infrastructure project with cluster-wide permissions

- **`terraform/`** - Terraform for bootstrapping
  - `argocd-bootstrap.tf` - Creates the root application via Terraform

- **`examples/`** - Example manifests and documentation

### Important Files

- `bootstrap/root.yaml` - Entry point; excludes itself from recursion with `exclude: 'root.yaml'`
- `infrastructure/longhorn.yaml` - Helm chart with custom values for distributed storage
- All bootstrap applications use `ignoreDifferences` on `spec/syncPolicy` to allow manual debugging

## Common Commands

### Bootstrapping the Cluster

```bash
# Method 1: Direct kubectl (fastest)
kubectl apply -f bootstrap/root.yaml

# Method 2: Terraform (recommended for production)
cd terraform/
terraform init
terraform plan
terraform apply
```

### Viewing Application Status

```bash
# List all ArgoCD applications
kubectl get applications -n argocd

# Watch application sync status
kubectl get applications -n argocd -w

# Describe specific application
kubectl describe application <app-name> -n argocd

# View application details with argocd CLI
argocd app get <app-name> -n argocd
```

### Managing Applications

```bash
# Force sync an application
argocd app sync <app-name> -n argocd

# View sync status and errors
kubectl get application <app-name> -n argocd -o jsonpath='{.status.conditions}'

# Delete application (cascades to resources)
kubectl delete application <app-name> -n argocd
```

### Repository Updates

```bash
# After changing manifests
git add .
git commit -m "Description of changes"
git push

# ArgoCD automatically syncs within ~3 minutes
# Check sync status
kubectl get applications -n argocd
```

### Sealed Secrets

```bash
# Encrypt a secret
kubeseal --format=yaml --scope=strict < my-secret.yaml > my-sealedsecret.yaml

# Install kubeseal CLI (Linux)
KUBESEAL_VERSION='0.26.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Install kubeseal CLI (macOS)
brew install kubeseal
```

### ArgoCD UI Access

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Access at https://localhost:8080
```

## Development Workflow

### Adding a New Application

1. **Create application manifest** in `apps/` or `infrastructure/`:

```yaml
# apps/my-app.yaml or infrastructure/my-component.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/storsteinbono/gitops.git
    targetRevision: HEAD
    path: apps/my-app/base
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

2. **Commit and push** - ArgoCD auto-syncs within 3 minutes
3. **Verify deployment**: `kubectl get applications -n argocd`

### Repository URL Pattern

All manifests reference: `https://github.com/storsteinbono/gitops.git`

**When forking/cloning**: Run this to update all repository URLs:
```bash
find . -name "*.yaml" -type f -exec sed -i 's|storsteinbono|YOUR_USERNAME|g' {} +
```

### Sync Policies

All applications use **automated sync** with:
- `prune: true` - Removes resources deleted from Git
- `selfHeal: true` - Reverts manual changes to cluster
- `allowEmpty: false` - Prevents empty deployments

**Parent applications** (infrastructure, apps) ignore child `syncPolicy` changes via `ignoreDifferences` to allow debugging.

### Helm Charts

Infrastructure components often use Helm charts (see `longhorn.yaml`):
- `chart:` - Chart name
- `repoURL:` - Helm repository URL
- `targetRevision:` - Chart version
- `helm.values:` - Inline values (YAML string)

## Secrets Management

### Sealed Secrets Integration

1. **Never commit unencrypted secrets** - Add to `.gitignore`:
   ```
   *-secret.yaml
   !*sealed-secret.yaml
   ```

2. **Encryption scopes**:
   - `--scope=strict` (default, most secure) - Bound to namespace + name
   - `--scope=namespace-wide` - Any name in namespace
   - `--scope=cluster-wide` - Anywhere in cluster

3. **Using secrets in deployments**:
   ```yaml
   env:
     - name: DATABASE_URL
       valueFrom:
         secretKeyRef:
           name: my-app-secrets
           key: database-url
   ```

4. **Backup encryption keys** (critical for disaster recovery):
   ```bash
   kubectl get secret -n kube-system \
     -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
     -o yaml > sealed-secrets-key-backup.yaml
   ```

## Terraform Integration

This repository can be bootstrapped via Terraform (see `TERRAFORM_INTEGRATION.md`).

**Key Terraform resource**:
```hcl
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = yamlencode({
    # Creates root application
  })
}
```

**Variables**:
- `gitops_repo_url` - Repository URL
- `gitops_repo_branch` - Branch to sync (default: `main`)
- `argocd_namespace` - ArgoCD namespace (default: `argocd`)

## Security Considerations

### Admin-Only Repository

- This repository has **admin-level access** to the cluster
- Pushing to this repo can modify **any** namespace
- Use branch protection and require PR reviews
- Only infrastructure team should have write access

### Project RBAC

Projects in `projects/` define:
- `sourceRepos` - Which Git repos can be used
- `destinations` - Which namespaces/clusters can be targeted
- `clusterResourceWhitelist` - Allowed cluster-scoped resources

**Warning**: Projects with access to `argocd` namespace have admin privileges.

### Longhorn Storage

Default configuration:
- 3 replicas for HA
- 200% over-provisioning
- `Retain` reclaim policy (data preserved on PV deletion)
- Storage class: `longhorn` (set as default)

## Troubleshooting

### Application Won't Sync

```bash
# Check application status
kubectl describe application <app-name> -n argocd

# View sync errors
kubectl get application <app-name> -n argocd -o jsonpath='{.status.conditions}'

# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
```

### Cascading Deletion

To delete an app and all its resources:
```bash
# Ensure finalizer exists (usually present by default)
kubectl patch application <app-name> -n argocd \
  -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' \
  --type=merge

# Delete application (cascades to all resources)
kubectl delete application <app-name> -n argocd
```

### Reset Entire GitOps Setup

```bash
# WARNING: This deletes ALL applications
kubectl delete application root -n argocd

# Reapply root
kubectl apply -f bootstrap/root.yaml
```

### Sealed Secret Not Decrypting

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f

# Verify SealedSecret exists
kubectl get sealedsecrets -n <namespace>

# Check for errors in SealedSecret
kubectl describe sealedsecret <name> -n <namespace>
```

## Key Patterns and Conventions

### File Naming

- Infrastructure components: `infrastructure/<component-name>.yaml`
- Applications: Either `apps/<app-name>.yaml` OR `apps/<app-name>/application.yaml`
- Projects: `projects/<project-name>.yaml`
- Sealed Secrets: Suffix with `-sealedsecret.yaml` or use `sealedsecret.yaml`

### Namespace Strategy

- ArgoCD applications live in `argocd` namespace
- Each application creates its own namespace via `syncOptions: [CreateNamespace=true]`
- Infrastructure components typically use system namespaces (`kube-system`, `longhorn-system`, etc.)

### App of Apps Recursion

The root app uses `directory.exclude: 'root.yaml'` to prevent infinite recursion. Child apps don't need this since they point to different paths.

### Retry and Backoff

Standard retry configuration:
```yaml
retry:
  limit: 5
  backoff:
    duration: 5s
    factor: 2
    maxDuration: 3m
```

## References

- ArgoCD App of Apps: https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/
- Sealed Secrets: https://sealed-secrets.netlify.app/
- Longhorn: https://longhorn.io/docs/
