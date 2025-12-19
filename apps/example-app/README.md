# Example App with Integrated SealedSecrets

This is an example application showing how to include SealedSecrets directly in your app structure.

## Structure

```
example-app/
├── application.yaml          # ArgoCD Application manifest
├── base/                     # Application manifests
│   ├── deployment.yaml       # Uses secrets from SealedSecret
│   ├── service.yaml
│   └── sealedsecret.yaml    # ✨ Encrypted secrets (SAFE to commit!)
├── secrets/                  # Helper directory (not deployed)
│   └── create-secrets.sh    # Script to create/update secrets
└── README.md                # This file
```

## How It Works

1. **SealedSecret is part of the app** - `base/sealedsecret.yaml` is deployed with the app
2. **ArgoCD syncs everything** - Both app and secrets deploy together
3. **Controller decrypts automatically** - No manual intervention needed
4. **App uses the secret** - Just reference it like any Kubernetes Secret

## Deployment Flow

```
Git Push
   ↓
ArgoCD Detects Changes
   ↓
Syncs to Cluster
   ├─→ Deployment ──────────┐
   ├─→ Service              │
   └─→ SealedSecret ─→ Controller Decrypts ─→ Secret
                                                 ↓
                                           App Uses It
```

## Creating/Updating Secrets

### Method 1: Manual

```bash
# 1. Create regular secret
cat > temp-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: example-app-secrets
  namespace: example-app
stringData:
  database-url: "postgresql://user:pass@db:5432/mydb"
  api-key: "sk-1234567890abcdef"
  admin-password: "changeme123"
EOF

# 2. Encrypt it
kubeseal --format=yaml < temp-secret.yaml > base/sealedsecret.yaml

# 3. Delete original (NEVER commit!)
rm temp-secret.yaml

# 4. Commit encrypted version
git add base/sealedsecret.yaml
git commit -m "Update application secrets"
git push
```

### Method 2: Using Helper Script

```bash
# Use the provided script
cd secrets
./create-secrets.sh
```

## Using Secrets in Pods

### As Environment Variables

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: example-app-secrets
        key: database-url
```

### As Files

```yaml
volumeMounts:
  - name: secrets
    mountPath: /etc/secrets
    readOnly: true
volumes:
  - name: secrets
    secret:
      secretName: example-app-secrets
```

Then access as files:
- `/etc/secrets/database-url`
- `/etc/secrets/api-key`
- `/etc/secrets/admin-password`

## Security Notes

1. ✅ **DO commit** `base/sealedsecret.yaml` - It's encrypted!
2. ❌ **DON'T commit** regular secret YAML files
3. ✅ **DO backup** your cluster's encryption keys
4. ✅ **DO rotate** secrets periodically

## Updating Secrets

```bash
# 1. Create new version of secret
# 2. Re-encrypt with kubeseal
# 3. Update base/sealedsecret.yaml
# 4. Commit and push
# 5. ArgoCD auto-syncs and controller updates the Secret
```

## Adding More Secrets

Just add more keys to the `stringData` section before encrypting:

```yaml
stringData:
  database-url: "..."
  api-key: "..."
  admin-password: "..."
  new-secret: "..."        # Add new secrets here
  another-secret: "..."
```

## Troubleshooting

### Secret not decrypting
```bash
# Check SealedSecret status
kubectl describe sealedsecret example-app-secrets -n example-app

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Pod can't access secret
```bash
# Verify secret exists
kubectl get secret example-app-secrets -n example-app

# Check secret data
kubectl get secret example-app-secrets -n example-app -o yaml
```

## See Also

- [Main Sealed Secrets Guide](../../SEALED_SECRETS.md)
- [Examples](../../examples/sealed-secrets/)
