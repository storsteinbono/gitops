# Sealed Secrets Guide

This guide explains how to use Sealed Secrets in your GitOps workflow to safely store encrypted secrets in Git.

## 📖 What is Sealed Secrets?

**Sealed Secrets** is a Kubernetes controller that allows you to encrypt Kubernetes Secrets so they can be safely stored in Git repositories. The encrypted secrets (SealedSecrets) can only be decrypted by the controller running in your cluster.

### How It Works

```
1. You create a regular Secret locally
   ↓
2. Encrypt it with kubeseal CLI → SealedSecret
   ↓
3. Commit SealedSecret to Git (safe!)
   ↓
4. ArgoCD syncs SealedSecret to cluster
   ↓
5. Sealed Secrets controller decrypts → Regular Secret
   ↓
6. Your app uses the Secret normally
```

### Key Benefits

- ✅ **GitOps-friendly**: Store secrets in Git safely
- ✅ **Encryption at rest**: Secrets encrypted with cluster-specific keys
- ✅ **No external dependencies**: Controller runs in-cluster
- ✅ **Kubernetes-native**: Uses standard CRDs
- ✅ **ArgoCD compatible**: Works seamlessly with GitOps workflows

## 🚀 Installation

### Already Installed!

Sealed Secrets is already configured in this repository at `infrastructure/sealed-secrets.yaml`.

To enable it, simply push to Git and ArgoCD will deploy it automatically:

```bash
git add infrastructure/sealed-secrets.yaml
git commit -m "Add Sealed Secrets"
git push
```

### Verify Installation

```bash
# Check if controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check if CRD is installed
kubectl get crd sealedsecrets.bitnami.com

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f
```

## 🔧 Installing kubeseal CLI

The `kubeseal` CLI is used to encrypt secrets locally before committing them.

### Linux (using wget)

```bash
# Download latest release
KUBESEAL_VERSION='0.26.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

# Extract and install
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Verify
kubeseal --version
```

### macOS (using Homebrew)

```bash
brew install kubeseal
```

### Using Krew (Kubernetes plugin manager)

```bash
kubectl krew install sealed-secrets
kubectl sealed-secrets --version
```

## 📝 Basic Usage

### 1. Create a Regular Secret

Create a file `my-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-database-secret
  namespace: production
type: Opaque
stringData:
  username: "admin"
  password: "super-secret-password-123"
  database-url: "postgresql://admin:password@db.example.com:5432/mydb"
```

### 2. Encrypt the Secret

```bash
# Basic encryption
kubeseal --format=yaml < my-secret.yaml > my-sealedsecret.yaml

# OR with scope specification
kubeseal --format=yaml --scope=strict < my-secret.yaml > my-sealedsecret.yaml
```

### 3. Review the SealedSecret

```bash
cat my-sealedsecret.yaml
```

Output will look like:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-database-secret
  namespace: production
spec:
  encryptedData:
    username: AgBQ7Vn8kF2xKz9...encrypted...
    password: AgCT9Kx2mE5pLw...encrypted...
    database-url: AgDX4Zp1wR3qM...encrypted...
  template:
    metadata:
      name: my-database-secret
      namespace: production
    type: Opaque
```

### 4. Commit to Git

```bash
# Add the SealedSecret (safe!)
git add my-sealedsecret.yaml

# DELETE the original secret (NEVER commit this!)
rm my-secret.yaml

# Commit
git commit -m "Add encrypted database credentials"
git push
```

### 5. Deploy via ArgoCD

The SealedSecret will be automatically synced by ArgoCD and decrypted by the controller!

```bash
# Check if secret was created
kubectl get secret my-database-secret -n production

# View the decrypted secret (requires permissions)
kubectl get secret my-database-secret -n production -o yaml
```

## 🎯 Secret Scopes

Sealed Secrets supports three encryption scopes:

### Strict Scope (Default - Recommended)

Secret is bound to a specific namespace and name.

```bash
kubeseal --scope=strict < secret.yaml > sealedsecret.yaml
```

**Use when**: You know the exact namespace and name (most secure).

### Namespace-wide Scope

Secret can be used with any name in the specified namespace.

```bash
kubeseal --scope=namespace-wide < secret.yaml > sealedsecret.yaml
```

**Use when**: Secret name might change, but namespace is fixed.

### Cluster-wide Scope

Secret can be used anywhere in the cluster.

```bash
kubeseal --scope=cluster-wide < secret.yaml > sealedsecret.yaml
```

**Use when**: Secret needs to be used across multiple namespaces.

⚠️ **Security Note**: Use the strictest scope possible. Cluster-wide secrets are less secure.

## 📁 Repository Organization

### Recommended Structure

```
gitops/
├── infrastructure/
│   ├── sealed-secrets.yaml         # Controller deployment
│   └── secrets/                    # Infrastructure secrets
│       └── infrastructure-db.yaml  # SealedSecret
│
├── apps/
│   ├── my-app/
│   │   ├── deployment.yaml
│   │   └── secrets/
│   │       └── app-secrets.yaml    # SealedSecret
│   └── another-app/
│       └── secrets/
│           └── api-keys.yaml       # SealedSecret
│
└── examples/
    └── sealed-secrets/
        ├── example-secret.yaml      # Example (not committed)
        └── example-sealedsecret.yaml # Example (safe)
```

## 🔄 Common Workflows

### Updating a Secret

```bash
# 1. Create updated secret
cat > updated-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-database-secret
  namespace: production
stringData:
  username: "admin"
  password: "new-secure-password-456"  # Updated!
EOF

# 2. Re-encrypt
kubeseal --format=yaml < updated-secret.yaml > my-sealedsecret.yaml

# 3. Delete original
rm updated-secret.yaml

# 4. Commit and push
git add my-sealedsecret.yaml
git commit -m "Rotate database password"
git push

# ArgoCD will sync and the controller will update the Secret!
```

### Using Secrets in Deployments

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
          # Use the decrypted secret
          - name: DB_USERNAME
            valueFrom:
              secretKeyRef:
                name: my-database-secret
                key: username
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: my-database-secret
                key: password
```

### Encrypting from Stdin

```bash
# Useful for automation
echo -n "my-secret-value" | kubectl create secret generic my-secret \
  --dry-run=client \
  --from-file=password=/dev/stdin \
  -o yaml | \
kubeseal --format=yaml > my-sealedsecret.yaml
```

### Encrypting Individual Values

```bash
# Encrypt just a value (useful for templating)
echo -n "my-password" | kubeseal --raw \
  --name=my-secret \
  --namespace=default \
  --from-file=/dev/stdin
```

## 🔐 Security Best Practices

### 1. Never Commit Unencrypted Secrets

```bash
# Add to .gitignore
echo "*-secret.yaml" >> .gitignore
echo "!*sealed-secret.yaml" >> .gitignore
```

### 2. Backup Encryption Keys

The Sealed Secrets controller uses a private key to decrypt secrets. **Backup this key!**

```bash
# Export the encryption key
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml

# Store this securely (e.g., Bitwarden, 1Password)
# DO NOT commit to Git!
```

### 3. Rotate Secrets Regularly

```bash
# Create a script for rotation
cat > rotate-secrets.sh <<'EOF'
#!/bin/bash
SECRET_FILE=$1
kubectl delete -f $SECRET_FILE
kubeseal --format=yaml < original-secret.yaml > $SECRET_FILE
git add $SECRET_FILE
git commit -m "Rotate secret: $SECRET_FILE"
git push
EOF

chmod +x rotate-secrets.sh
```

### 4. Use Namespace Isolation

Deploy secrets in the same namespace as the applications that use them.

### 5. Audit Secret Access

```bash
# Check who accessed secrets
kubectl get events --field-selector involvedObject.kind=Secret -n production

# Monitor sealed secrets controller
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=100
```

## 🛠️ Troubleshooting

### Secret Not Decrypting

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify SealedSecret exists
kubectl get sealedsecrets -n <namespace>

# Check for errors
kubectl describe sealedsecret <name> -n <namespace>
```

### Re-seal After Cluster Rebuild

If you rebuild your cluster, you need to restore the encryption keys:

```bash
# Apply backed-up key
kubectl apply -f sealed-secrets-key-backup.yaml

# Restart controller
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Key Renewal

By default, keys are renewed every 30 days. Old keys are retained for decryption.

```bash
# Check current keys
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key

# Force key renewal (not usually needed)
kubectl delete secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active
```

## 📊 Integration with ArgoCD

### Automatic Sync

SealedSecrets work seamlessly with ArgoCD's automated sync:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true  # Auto-update secrets when changed in Git
```

### Sync Waves

Deploy Sealed Secrets before applications:

```yaml
# infrastructure/sealed-secrets.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # Deploy first

# apps/my-app.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # Deploy after
```

## 🎓 Advanced Topics

### Using with Helm Charts

```bash
# Generate sealed secret for Helm values
cat > values-secret.yaml <<EOF
mysecret:
  password: "changeme"
EOF

kubectl create secret generic helm-values \
  --from-file=values.yaml=values-secret.yaml \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > helm-values-sealed.yaml
```

### CI/CD Integration

```yaml
# .github/workflows/seal-secrets.yml
name: Seal Secrets
on:
  pull_request:
    paths:
      - '**/*-secret.yaml'

jobs:
  seal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install kubeseal
        run: |
          wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
          tar xfz kubeseal-0.26.0-linux-amd64.tar.gz
          sudo install -m 755 kubeseal /usr/local/bin/kubeseal

      - name: Seal secrets
        run: |
          for file in **/*-secret.yaml; do
            kubeseal --format=yaml < $file > ${file%-secret.yaml}-sealedsecret.yaml
          done
```

## 📚 Additional Resources

- [Official Documentation](https://sealed-secrets.netlify.app/)
- [GitHub Repository](https://github.com/bitnami-labs/sealed-secrets)
- [Helm Chart](https://github.com/bitnami-labs/sealed-secrets/tree/main/helm/sealed-secrets)
- [Best Practices](https://github.com/bitnami-labs/sealed-secrets#best-practices)

## ❓ FAQ

**Q: Can I decrypt SealedSecrets locally?**
A: No, only the controller with the private key can decrypt them. This is by design for security.

**Q: What if I lose the encryption keys?**
A: You'll need to re-encrypt all secrets. **Always backup your keys!**

**Q: Can I use the same SealedSecret in multiple clusters?**
A: No, each cluster has unique encryption keys. Re-seal for each cluster.

**Q: How do I rotate the encryption keys?**
A: The controller automatically rotates keys every 30 days. Old keys are retained for decryption.

**Q: Is this suitable for production?**
A: Yes! Sealed Secrets is widely used in production and is a CNCF Sandbox project.

---

**Status**: ✅ Configured in this repository
**Installation**: `infrastructure/sealed-secrets.yaml`
**Examples**: `examples/sealed-secrets/`
