# Quick Start Guide

This guide will help you bootstrap your Kubernetes cluster with ArgoCD using the App of Apps pattern in under 5 minutes.

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- kubectl configured and working
- Git repository pushed to GitHub/GitLab

## Step 1: Update Repository URLs

Replace `storsteinbono` with your actual GitHub username:

```bash
cd /home/steffen/Documents/repos/private/gitops
find . -name "*.yaml" -type f -exec sed -i 's|storsteinbono|steffenb|g' {} +
```

## Step 2: Commit and Push

```bash
git add .
git commit -m "Initial GitOps setup with App of Apps pattern"
git push origin main
```

## Step 3: Bootstrap ArgoCD

### Option A: Using kubectl (Fastest)

```bash
kubectl apply -f bootstrap/root.yaml
```

### Option B: Using Terraform (Recommended for production)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your repository URL
terraform init
terraform apply
```

## Step 4: Verify

```bash
# Watch applications sync
kubectl get applications -n argocd -w

# Expected output:
# NAME              SYNC STATUS   HEALTH STATUS
# root              Synced        Healthy
# infrastructure    Synced        Healthy
# applications      Synced        Healthy
# longhorn          Synced        Progressing -> Healthy
```

## Step 5: Access ArgoCD UI

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Open browser to https://localhost:8080
# Login: admin / <password from above>
```

## What Happens Next?

1. **Root app** creates two child apps: `infrastructure` and `applications`
2. **Infrastructure app** creates `longhorn` storage system
3. **Applications app** waits for your apps (currently empty)

All apps sync automatically when you push changes to Git!

## Adding Your First Application

Create a file `infrastructure/my-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://my-helm-repo.com
    chart: my-chart
    targetRevision: 1.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: my-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Commit and push - ArgoCD will automatically deploy it!

```bash
git add infrastructure/my-app.yaml
git commit -m "Add my-app"
git push
```

## Troubleshooting

### Application stuck in "Progressing"
```bash
kubectl describe application <name> -n argocd
```

### Force sync
```bash
argocd app sync <name> -n argocd
```

### View logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
```

## Next Steps

- Read the full [README.md](README.md)
- Explore [Longhorn UI](infrastructure/longhorn.yaml) for storage management
- Add your applications to `apps/` directory
- Set up [monitoring and alerts](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)

---

**Need help?** Check the [troubleshooting section](README.md#troubleshooting) in the README.
