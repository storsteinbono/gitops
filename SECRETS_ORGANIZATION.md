# Organizing Secrets in App of Apps

This guide shows different patterns for organizing SealedSecrets in your GitOps repository with the App of Apps pattern.

## 🎯 Yes, Secrets Are Created Automatically!

**Answer**: SealedSecrets are deployed automatically as part of your applications. Just include them in your app directory and ArgoCD handles the rest!

## 📁 Organization Patterns

### Pattern 1: Inline with Application (Recommended)

Include SealedSecret directly in your application manifests.

```
apps/my-app/
├── application.yaml          # ArgoCD Application
└── base/
    ├── deployment.yaml       # Uses the secret
    ├── service.yaml
    └── sealedsecret.yaml    # ✨ Encrypted secret (auto-deployed!)
```

**Pros**:
- ✅ Everything in one place
- ✅ Secrets deploy with the app
- ✅ Easy to manage
- ✅ Clear ownership

**Example**: See `apps/example-app/`

### Pattern 2: Separate Secrets Directory

Dedicated directory for secrets within the app.

```
apps/my-app/
├── application.yaml
├── base/
│   ├── deployment.yaml
│   └── service.yaml
└── secrets/
    ├── database.sealedsecret.yaml
    ├── api-keys.sealedsecret.yaml
    └── certificates.sealedsecret.yaml
```

**Pros**:
- ✅ Organized when many secrets
- ✅ Clear separation
- ✅ Easy to find all secrets

**Use when**: App has multiple SealedSecrets

### Pattern 3: Kustomize with Secrets

Use Kustomize to manage secrets across environments.

```
apps/my-app/
├── application.yaml
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── sealedsecret.yaml      # Base secrets
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── sealedsecret.yaml  # Dev-specific secrets
│   └── prod/
│       ├── kustomization.yaml
│       └── sealedsecret.yaml  # Prod-specific secrets
```

**Pros**:
- ✅ Environment-specific secrets
- ✅ Kustomize integration
- ✅ DRY principle

**Use when**: Multiple environments need different secrets

### Pattern 4: Shared Infrastructure Secrets

Common secrets used by multiple apps.

```
infrastructure/
├── sealed-secrets.yaml         # Controller
└── shared-secrets/
    ├── application.yaml        # ArgoCD App for shared secrets
    └── base/
        ├── registry-creds.yaml
        ├── tls-certs.yaml
        └── api-keys.yaml
```

**Pros**:
- ✅ DRY - One secret, many apps
- ✅ Centralized management
- ✅ Easier rotation

**Use when**: Secrets shared across multiple apps

## 🔄 Deployment Flow

### How ArgoCD Deploys Your Secrets

```
1. You commit SealedSecret to Git
         ↓
2. ArgoCD detects change (within 3 min)
         ↓
3. ArgoCD syncs all manifests in app directory
   ├─→ deployment.yaml
   ├─→ service.yaml
   └─→ sealedsecret.yaml  ← This too!
         ↓
4. Sealed Secrets controller detects SealedSecret
         ↓
5. Controller decrypts → Creates regular Secret
         ↓
6. Deployment references the Secret
         ↓
7. Pod starts with decrypted secrets
```

### Automatic Features

✅ **Auto-sync**: Secrets deploy when app deploys
✅ **Auto-update**: Change secret in Git → Auto-updates in cluster
✅ **Auto-decrypt**: Controller handles decryption
✅ **Auto-heal**: ArgoCD reverts manual changes

## 📝 Complete Example

### Directory Structure

```
apps/web-app/
├── application.yaml
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── sealedsecret.yaml
└── secrets/
    └── create-secrets.sh
```

### application.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/storsteinbono/gitops.git
    path: apps/web-app/base  # ← Points to base directory
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: web-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### base/sealedsecret.yaml

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: web-app-secrets
  namespace: web-app
spec:
  encryptedData:
    DB_PASSWORD: AgBQ7Vn8kF...  # ← Encrypted, safe in Git!
    API_KEY: AgCT9Kx2mE...
  template:
    metadata:
      name: web-app-secrets
      namespace: web-app
    type: Opaque
```

### base/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: web-app-secrets  # ← References the Secret
                key: DB_PASSWORD
          - name: API_KEY
            valueFrom:
              secretKeyRef:
                name: web-app-secrets
                key: API_KEY
```

## 🛠️ Creating Secrets

### Method 1: Manual Command

```bash
# 1. Create regular secret
cat > temp-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: web-app-secrets
  namespace: web-app
stringData:
  DB_PASSWORD: "my-secure-password"
  API_KEY: "sk-1234567890"
EOF

# 2. Encrypt it
kubeseal --format=yaml < temp-secret.yaml > apps/web-app/base/sealedsecret.yaml

# 3. Clean up
rm temp-secret.yaml

# 4. Commit
git add apps/web-app/base/sealedsecret.yaml
git commit -m "Add web-app secrets"
git push
```

### Method 2: Using Helper Script

```bash
# Copy the helper script template
cp apps/example-app/secrets/create-secrets.sh apps/web-app/secrets/
# Customize it for your app
# Run it
cd apps/web-app/secrets
./create-secrets.sh
```

### Method 3: One-liner

```bash
echo -n "my-password" | \
kubectl create secret generic my-secret \
  --dry-run=client \
  --namespace=my-namespace \
  --from-file=password=/dev/stdin \
  -o yaml | \
kubeseal --format=yaml > sealedsecret.yaml
```

## 📦 Real-World Examples

### Example 1: Database Application

```
apps/postgres-app/
├── application.yaml
└── base/
    ├── deployment.yaml
    ├── service.yaml
    ├── pvc.yaml
    └── sealedsecret.yaml  # Contains: POSTGRES_PASSWORD, DB_USER
```

**SealedSecret contains**:
- Database password
- Admin credentials
- Connection strings

### Example 2: Web API with Multiple Secrets

```
apps/api-server/
├── application.yaml
└── base/
    ├── deployment.yaml
    ├── service.yaml
    ├── db-secret.yaml      # Database credentials
    ├── oauth-secret.yaml   # OAuth tokens
    └── tls-secret.yaml     # TLS certificates
```

**Multiple SealedSecrets for**:
- Separation of concerns
- Different rotation schedules
- Different access patterns

### Example 3: Microservices with Shared Secrets

```
infrastructure/
└── shared-secrets/
    ├── application.yaml
    └── base/
        └── registry-credentials.yaml  # Used by all apps

apps/
├── service-a/
│   └── base/
│       └── deployment.yaml  # Uses registry credentials
└── service-b/
    └── base/
        └── deployment.yaml  # Uses registry credentials
```

## 🔐 Security Best Practices

### 1. Never Commit Unencrypted Secrets

```bash
# Add to .gitignore
cat >> .gitignore <<EOF
# Unencrypted secrets
*-secret.yaml
!*sealedsecret.yaml
secrets/*.yaml
!secrets/create-*.sh
EOF
```

### 2. Use Namespace Scoping

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
  namespace: my-app  # ← Scoped to namespace
spec:
  # ...
```

### 3. Organize by Sensitivity

```
apps/my-app/
└── base/
    ├── config.yaml           # Public config
    ├── credentials.yaml      # High sensitivity
    └── api-keys.yaml        # Medium sensitivity
```

### 4. Use Secret Volumes for Files

```yaml
volumes:
  - name: tls-certs
    secret:
      secretName: tls-secrets
      items:
        - key: tls.crt
          path: tls.crt
        - key: tls.key
          path: tls.key
          mode: 0600  # ← Restrict permissions
```

## 🔄 Updating Secrets

### Update Process

```bash
# 1. Create new secret version
cat > temp-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-app
stringData:
  password: "new-secure-password"  # ← Updated!
EOF

# 2. Re-encrypt
kubeseal --format=yaml < temp-secret.yaml > apps/my-app/base/sealedsecret.yaml

# 3. Commit and push
git add apps/my-app/base/sealedsecret.yaml
git commit -m "Rotate application password"
git push

# 4. ArgoCD auto-syncs (within 3 minutes)
# 5. Controller updates the Secret
# 6. Pods pick up new secret (may need restart depending on app)
```

### Force Pod Restart After Secret Update

```yaml
# Add annotation to deployment to force restart
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        secret-version: "v2"  # ← Change this to force restart
```

## 🎯 Common Patterns

### Pattern: Database Credentials

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: my-app
spec:
  encryptedData:
    username: AgB...
    password: AgC...
    database: AgD...
    host: AgE...
    port: AgF...
  template:
    type: Opaque
```

### Pattern: TLS Certificates

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: tls-certs
  namespace: my-app
spec:
  encryptedData:
    tls.crt: AgB...
    tls.key: AgC...
    ca.crt: AgD...
  template:
    type: kubernetes.io/tls
```

### Pattern: Container Registry

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: registry-credentials
  namespace: my-app
spec:
  encryptedData:
    .dockerconfigjson: AgB...
  template:
    type: kubernetes.io/dockerconfigjson
```

### Pattern: OAuth/API Tokens

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: oauth-tokens
  namespace: my-app
spec:
  encryptedData:
    client-id: AgB...
    client-secret: AgC...
    callback-url: AgD...
  template:
    type: Opaque
```

## 📊 Comparison: Organization Patterns

| Pattern | Complexity | Flexibility | Use Case |
|---------|-----------|-------------|----------|
| **Inline** | Low | Low | Simple apps, 1-2 secrets |
| **Separate Dir** | Medium | Medium | Apps with many secrets |
| **Kustomize** | High | High | Multi-environment |
| **Shared** | Medium | High | Common infrastructure secrets |

## ✅ Checklist: Adding Secrets to Your App

- [ ] Create regular secret YAML (locally, don't commit!)
- [ ] Encrypt with `kubeseal`
- [ ] Save as `sealedsecret.yaml` in app directory
- [ ] Delete unencrypted version
- [ ] Commit encrypted version to Git
- [ ] Push to repository
- [ ] Verify ArgoCD syncs it
- [ ] Check controller decrypts it
- [ ] Test app can access secret

## 🎓 Quick Reference

### Create Secret
```bash
kubeseal --format=yaml < secret.yaml > sealedsecret.yaml
```

### Verify Secret Deployed
```bash
kubectl get sealedsecret -n <namespace>
kubectl get secret -n <namespace>
```

### View Secret Data
```bash
kubectl get secret <name> -n <namespace> -o yaml
```

### Update Secret
```bash
# Re-encrypt and commit
kubeseal --format=yaml < new-secret.yaml > sealedsecret.yaml
git add sealedsecret.yaml && git commit -m "Update secret" && git push
```

## 📚 See Also

- [SEALED_SECRETS.md](SEALED_SECRETS.md) - Complete Sealed Secrets guide
- [apps/example-app/](apps/example-app/) - Working example with secrets
- [examples/sealed-secrets/](examples/sealed-secrets/) - More examples

---

**Summary**: Yes! SealedSecrets are automatically deployed with your apps. Just include them in your app directory structure and ArgoCD handles everything!
