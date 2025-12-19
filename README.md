# GitOps Repository - ArgoCD App of Apps

This repository contains the GitOps configuration for managing Kubernetes applications using ArgoCD's App of Apps pattern. It follows the cluster bootstrapping best practices from [ArgoCD documentation](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/).

## 📁 Repository Structure

```
.
├── bootstrap/              # Root App of Apps manifests
│   ├── root.yaml          # Parent application (manages all other apps)
│   ├── infrastructure.yaml # Infrastructure app of apps
│   └── apps.yaml          # User applications app of apps
├── infrastructure/         # Infrastructure components
│   └── longhorn.yaml      # Longhorn distributed storage
├── apps/                  # User applications
│   └── .gitkeep           # Placeholder for your apps
├── projects/              # ArgoCD project definitions
│   ├── default.yaml       # Default project
│   └── infrastructure.yaml # Infrastructure project
└── terraform/             # Terraform for bootstrapping
    └── argocd-bootstrap.tf # Terraform to create root app
```

## 🎯 App of Apps Pattern

This repository implements the **App of Apps pattern**, where a root ArgoCD Application manages other Applications. This creates a hierarchy:

```
root (bootstrap/root.yaml)
├── infrastructure (bootstrap/infrastructure.yaml)
│   └── longhorn (infrastructure/longhorn.yaml)
└── applications (bootstrap/apps.yaml)
    └── (your apps here)
```

### Benefits

- **Single Source of Truth**: All applications defined in Git
- **Automated Sync**: Changes to Git automatically sync to cluster
- **Easy Rollback**: Git history = deployment history
- **Declarative Management**: Define desired state, ArgoCD ensures it
- **Progressive Delivery**: Add apps by adding YAML files

## 🚀 Getting Started

### Prerequisites

1. **Kubernetes cluster** with ArgoCD installed
2. **kubectl** configured to access your cluster
3. **Terraform** (optional, for automated bootstrap)
4. **Git repository** (this repo) accessible from your cluster

### Installation Methods

#### Method 1: Terraform Bootstrap (Recommended)

1. **Update the GitOps repository URLs** in all manifests:
   ```bash
   # Replace storsteinbono with your GitHub username
   find . -name "*.yaml" -type f -exec sed -i 's|https://github.com/storsteinbono/gitops.git|https://github.com/storsteinbono/gitops.git|g' {} +
   ```

2. **Configure Terraform**:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Apply Terraform**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

#### Method 2: Manual Bootstrap

1. **Update repository URLs** (see step 1 above)

2. **Apply the root application**:
   ```bash
   kubectl apply -f bootstrap/root.yaml
   ```

3. **Verify deployment**:
   ```bash
   kubectl get applications -n argocd
   ```

### Verify Installation

After bootstrapping, verify that applications are syncing:

```bash
# List all applications
kubectl get applications -n argocd

# Check application status
kubectl get application root -n argocd -o yaml

# View ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

## 📦 Adding New Applications

### Infrastructure Applications

1. Create a new YAML file in `infrastructure/`:
   ```yaml
   # infrastructure/cert-manager.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: cert-manager
     namespace: argocd
     finalizers:
       - resources-finalizer.argocd.argoproj.io
   spec:
     project: infrastructure
     source:
       chart: cert-manager
       repoURL: https://charts.jetstack.io
       targetRevision: v1.13.0
     destination:
       server: https://kubernetes.default.svc
       namespace: cert-manager
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

2. Commit and push:
   ```bash
   git add infrastructure/cert-manager.yaml
   git commit -m "Add cert-manager"
   git push
   ```

3. ArgoCD will automatically detect and deploy the new application!

### User Applications

Same process, but create files in the `apps/` directory.

## 🔧 Configuration

### Sync Policy

All applications use automated sync with:
- **prune: true** - Remove resources not in Git
- **selfHeal: true** - Revert manual changes
- **allowEmpty: false** - Prevent empty deployments

To disable automated sync for an application, remove the `syncPolicy.automated` section.

### Ignore Differences

The parent applications ignore changes to child application `syncPolicy` to allow manual debugging. See `ignoreDifferences` in `bootstrap/infrastructure.yaml` and `bootstrap/apps.yaml`.

## 📊 Current Applications

### Infrastructure

| Application | Description | Namespace | Chart Version |
|------------|-------------|-----------|---------------|
| **sealed-secrets** | Encrypted secrets for GitOps | kube-system | 2.16.2 |
| **longhorn** | Distributed block storage | longhorn-system | 1.8.0 |

### Applications

(Empty - add your applications here)

## 🔐 Security Considerations

⚠️ **Important**: The App of Apps pattern is an **admin-only tool**.

- Only admins should have push access to this repository
- Review all pull requests carefully, especially the `project` field
- Projects with access to the `argocd` namespace have admin privileges
- Use branch protection and require reviews for changes

### Sealed Secrets

This repository includes **Sealed Secrets** for safely storing encrypted secrets in Git. See [SEALED_SECRETS.md](SEALED_SECRETS.md) for:

- How to encrypt secrets with `kubeseal` CLI
- How to store encrypted secrets in Git safely
- Best practices for secret management
- Integration with ArgoCD

**Quick Start:**
```bash
# Install kubeseal CLI
brew install kubeseal  # macOS
# or download from: https://github.com/bitnami-labs/sealed-secrets/releases

# Encrypt a secret
kubeseal --format=yaml < my-secret.yaml > my-sealedsecret.yaml

# Commit the encrypted version (safe!)
git add my-sealedsecret.yaml
git commit -m "Add encrypted secret"
git push
```

## 🎨 Customization

### Longhorn Configuration

The Longhorn installation can be customized by editing `infrastructure/longhorn.yaml`. Current settings:

- **Default Replicas**: 3 (for high availability)
- **Storage Class**: `longhorn` (set as default)
- **Reclaim Policy**: Retain (keeps data on PV deletion)
- **Over-provisioning**: 200% (allows more PVCs than physical storage)

### Adding Projects

Create new AppProject definitions in `projects/` directory. Projects control:
- Which repositories applications can deploy from
- Which namespaces and clusters they can deploy to
- RBAC policies for project access

Example:
```yaml
# projects/production.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production applications
  sourceRepos:
    - https://github.com/myorg/production-apps.git
  destinations:
    - namespace: 'production-*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
```

## 🛠️ Troubleshooting

### Application Won't Sync

```bash
# Check application status
kubectl describe application <app-name> -n argocd

# View sync errors
kubectl get application <app-name> -n argocd -o jsonpath='{.status.conditions}'

# Force sync
argocd app sync <app-name> -n argocd
```

### Cascading Deletion

To delete an app and all its resources:

```bash
# Ensure finalizer is present (it should be by default)
kubectl patch application <app-name> -n argocd -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type=merge

# Delete the application
kubectl delete application <app-name> -n argocd
```

### Reset Root Application

If you need to start over:

```bash
# Delete the root application (will cascade delete all child apps)
kubectl delete application root -n argocd

# Reapply
kubectl apply -f bootstrap/root.yaml
```

## 📚 Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/latest/user-guide/best_practices/)
- [Longhorn Documentation](https://longhorn.io/docs/)

## 🤝 Contributing

1. Create a feature branch
2. Add your application manifests
3. Test locally using `argocd app create --dry-run`
4. Submit a pull request with a clear description

## 📝 License

This configuration is provided as-is for infrastructure management purposes.

## 🔄 CI/CD Integration

This repository can be integrated with CI/CD pipelines to:
- Validate YAML syntax
- Check for security issues
- Test manifests against a development cluster
- Auto-merge approved changes

Example GitHub Actions workflow can be added in `.github/workflows/`.

## 🎓 Learning Resources

If you're new to GitOps or ArgoCD:
1. Start by understanding the [root application](bootstrap/root.yaml)
2. Look at how [Longhorn is deployed](infrastructure/longhorn.yaml)
3. Try adding a simple application
4. Read about [ArgoCD sync waves](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-waves/) for ordered deployments

---

**Last Updated**: 2025-12-17
**Maintained By**: Infrastructure Team