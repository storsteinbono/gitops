# =============================================================================
# ArgoCD Bootstrap Configuration
# =============================================================================
# This Terraform configuration bootstraps ArgoCD with the root application
# that follows the App of Apps pattern. It should be applied after ArgoCD
# is installed in the cluster.
#
# Prerequisites:
# 1. ArgoCD must be installed in the cluster (argocd namespace)
# 2. kubectl must be configured to access the cluster
# 3. The GitOps repository must be accessible from the cluster
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository (e.g., https://github.com/USERNAME/gitops.git)"
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch of the GitOps repository to sync from"
  type        = string
  default     = "main"
}

variable "gitops_repo_path" {
  description = "Path in the GitOps repository containing the root application"
  type        = string
  default     = "bootstrap"
}

# =============================================================================
# Data Sources
# =============================================================================

data "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

# =============================================================================
# ArgoCD Root Application (App of Apps)
# =============================================================================

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_branch
        path           = var.gitops_repo_path
        directory = {
          recurse = true
          exclude = "root.yaml" # Don't recursively create the root app
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

  depends_on = [data.kubernetes_namespace.argocd]
}

# =============================================================================
# Outputs
# =============================================================================

output "root_app_name" {
  description = "Name of the root ArgoCD application"
  value       = kubectl_manifest.argocd_root_app.name
}

output "gitops_repo_url" {
  description = "GitOps repository URL"
  value       = var.gitops_repo_url
}

output "gitops_repo_branch" {
  description = "GitOps repository branch"
  value       = var.gitops_repo_branch
}

output "next_steps" {
  description = "Next steps after applying this configuration"
  value       = <<-EOT
    ArgoCD root application has been created!

    To view the application status:
      kubectl get applications -n ${var.argocd_namespace}

    To access ArgoCD UI:
      kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443

    Then open: https://localhost:8080

    To sync the root application manually:
      argocd app sync root -n ${var.argocd_namespace}

    To view all applications:
      argocd app list -n ${var.argocd_namespace}
  EOT
}
