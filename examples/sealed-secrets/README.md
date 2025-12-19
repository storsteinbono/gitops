# Sealed Secrets Examples

This directory contains example manifests for working with Sealed Secrets.

## Files

- **example-secret.yaml** - Regular Kubernetes Secret (DO NOT commit to Git!)
- **example-sealedsecret.yaml** - Encrypted SealedSecret (safe to commit)

## Usage

### 1. Create a Regular Secret

First, create a regular Kubernetes Secret locally:

```yaml
# my-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secret
  namespace: default
type: Opaque
stringData:
  username: "admin"
  password: "changeme123"
```

### 2. Encrypt it with kubeseal

```bash
kubeseal --format=yaml < my-secret.yaml > my-sealedsecret.yaml
```

### 3. Commit the SealedSecret

```bash
git add my-sealedsecret.yaml
git commit -m "Add encrypted secret"
git push
```

### 4. Delete the Original Secret

```bash
rm my-secret.yaml  # IMPORTANT: Don't commit this!
```

## ArgoCD Integration

To deploy a SealedSecret via ArgoCD:

1. Create your SealedSecret YAML in the appropriate directory:
   - Infrastructure secrets: `infrastructure/secrets/`
   - Application secrets: `apps/<app-name>/secrets/`

2. Create an ArgoCD Application that includes your secrets:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/storsteinbono/gitops.git
    path: apps/my-app
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

3. The Sealed Secrets controller will automatically decrypt them!

## Scopes

Sealed Secrets supports three scopes:

### Strict (Default)
Secret is sealed to a specific namespace and name.

```bash
kubeseal --scope strict < secret.yaml > sealedsecret.yaml
```

### Namespace-wide
Secret can be used with any name in the namespace.

```bash
kubeseal --scope namespace-wide < secret.yaml > sealedsecret.yaml
```

### Cluster-wide
Secret can be used anywhere in the cluster.

```bash
kubeseal --scope cluster-wide < secret.yaml > sealedsecret.yaml
```

## Best Practices

1. **Never commit regular Secrets** - Only commit SealedSecrets
2. **Use strict scope** - Unless you need flexibility
3. **Backup your keys** - Keep sealed-secrets encryption keys backed up
4. **Rotate secrets regularly** - Update and re-seal secrets periodically
5. **Use namespaces** - Keep secrets organized by namespace

## More Information

See [../SEALED_SECRETS.md](../../SEALED_SECRETS.md) for complete documentation.
