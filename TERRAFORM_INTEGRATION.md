# Terraform Integration Guide

This guide explains how to integrate the GitOps repository bootstrap with your existing Terraform infrastructure in the `/talos` repository.

## Overview

The GitOps repository can be bootstrapped automatically as part of your Terraform deployment. This creates the root ArgoCD application that manages all other applications.

## Integration Options

### Option 1: Add to Existing ArgoCD Module (Recommended)

Add the following to your `/talos/terraform/environments/prd/kubernetes.argocd.tf`:

```hcl
# =============================================================================
# ArgoCD GitOps Bootstrap - Root Application
# =============================================================================

resource "kubectl_manifest" "argocd_gitops_root" {
  count = local.argocd_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = local.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
      annotations = {
        "argocd.argoproj.io/sync-wave" = "0"
      }
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/storsteinbono/gitops.git"
        targetRevision = "main"
        path           = "bootstrap"
        directory = {
          recurse = true
          exclude = "root.yaml"
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = local.argocd_namespace
      }
      syncPolicy = {
        automated = {
          prune      = true
          selfHeal   = true
          allowEmpty = false
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })

  depends_on = [
    module.argocd  # Wait for ArgoCD to be fully deployed
  ]
}

# Store GitOps repository information in Bitwarden
resource "bitwarden_item_secure_note" "gitops_repo" {
  count = local.argocd_enabled ? 1 : 0

  organization_id = var.bitwarden_organization_id
  name            = "GitOps Repository - ArgoCD"
  notes           = <<-EOT
    GitOps repository for ArgoCD App of Apps pattern.

    Repository: https://github.com/storsteinbono/gitops.git
    Branch: main

    This repository contains all Kubernetes application definitions.
    Changes pushed to this repository automatically sync to the cluster.
  EOT

  field {
    name = "repo_url"
    text = "https://github.com/storsteinbono/gitops.git"
  }

  field {
    name = "branch"
    text = "main"
  }
}
```

### Option 2: Separate Terraform Module

Create a new module at `/talos/terraform/modules/argocd-gitops-bootstrap/`:

```bash
cd /home/steffen/Documents/repos/private/talos/terraform/modules
mkdir -p argocd-gitops-bootstrap
```

**main.tf**:
```hcl
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "root"
      namespace  = var.argocd_namespace
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_branch
        path           = var.gitops_repo_path
        directory = {
          recurse = true
          exclude = "root.yaml"
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_namespace
      }
      syncPolicy = {
        automated = {
          prune      = true
          selfHeal   = true
          allowEmpty = false
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })
}
```

**variables.tf**:
```hcl
variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace where ArgoCD is installed"
}

variable "gitops_repo_url" {
  type        = string
  description = "URL of the GitOps repository"
}

variable "gitops_repo_branch" {
  type        = string
  default     = "main"
  description = "Branch to sync from"
}

variable "gitops_repo_path" {
  type        = string
  default     = "bootstrap"
  description = "Path in repo containing root app"
}
```

Then use in your environment:

```hcl
module "argocd_gitops_bootstrap" {
  count  = local.argocd_enabled ? 1 : 0
  source = "../../modules/argocd-gitops-bootstrap"

  argocd_namespace    = local.argocd_namespace
  gitops_repo_url     = "https://github.com/storsteinbono/gitops.git"
  gitops_repo_branch  = "main"
  gitops_repo_path    = "bootstrap"

  depends_on = [module.argocd]
}
```

## Variables Configuration

Add these variables to your `/talos/terraform/environments/prd/variables.tf`:

```hcl
variable "gitops_repo_url" {
  type        = string
  description = "GitOps repository URL for ArgoCD App of Apps"
  default     = "https://github.com/storsteinbono/gitops.git"
}

variable "gitops_repo_branch" {
  type        = string
  description = "GitOps repository branch"
  default     = "main"
}

variable "enable_gitops_bootstrap" {
  type        = bool
  description = "Enable automatic GitOps repository bootstrap"
  default     = true
}
```

And in your `prd-config.tfvars`:

```hcl
# GitOps Configuration
enable_gitops_bootstrap = true
gitops_repo_url         = "https://github.com/steffenb/gitops.git"
gitops_repo_branch      = "main"
```

## Bitwarden Integration

Store GitOps credentials in Bitwarden for SSH access (if using private repo):

```hcl
# Generate SSH key for GitOps repository (in CMN environment)
resource "tls_private_key" "gitops_deploy_key" {
  algorithm = "ED25519"
}

# Store in Bitwarden
resource "bitwarden_item_secure_note" "gitops_deploy_key" {
  organization_id = var.bitwarden_organization_id
  name            = "GitOps Repository Deploy Key"
  notes           = "SSH deploy key for GitOps repository access"

  field {
    name = "private_key"
    text = tls_private_key.gitops_deploy_key.private_key_openssh
  }

  field {
    name = "public_key"
    text = tls_private_key.gitops_deploy_key.public_key_openssh
  }
}
```

Then configure ArgoCD to use the SSH key:

```hcl
resource "kubernetes_secret" "gitops_repo_ssh" {
  count = local.argocd_enabled ? 1 : 0

  metadata {
    name      = "gitops-repo-ssh"
    namespace = local.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = "git@github.com:storsteinbono/gitops.git"
    sshPrivateKey = tls_private_key.gitops_deploy_key.private_key_openssh
  }

  depends_on = [module.argocd]
}
```

## Testing

After applying Terraform:

```bash
# Apply Terraform
cd /home/steffen/Documents/repos/private/talos
./scripts/terraform.sh -e prd -c apply

# Verify root app was created
kubectl get application root -n argocd

# Watch apps sync
kubectl get applications -n argocd -w
```

## Troubleshooting

### Root app not created
```bash
# Check Terraform state
terraform state list | grep argocd_root

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Repository access issues
```bash
# Verify repository secret
kubectl get secret -n argocd | grep gitops

# Check ArgoCD can access repo
argocd repo list
```

## Best Practices

1. **Use CMN environment** to generate and store SSH keys
2. **Version your manifests** - use Git tags for production releases
3. **Test in DEV first** - bootstrap DEV environment before PRD
4. **Monitor sync status** - set up alerts for failed syncs
5. **Use branch protection** - require reviews for main branch

## Next Steps

1. Apply the Terraform configuration
2. Verify the root application is created
3. Watch as ArgoCD syncs all applications from Git
4. Make changes to GitOps repo and see them auto-deploy!

---

For more information, see the [main README](README.md).
