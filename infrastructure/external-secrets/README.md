# External Secrets Operator

This directory configures the External Secrets Operator to sync secrets from Azure Key Vault into Kubernetes.

## Architecture

- **Helm Chart**: Installs the External Secrets Operator
- **ClusterSecretStore**: Configures authentication to Azure Key Vault
- **ExternalSecrets**: Individual secret mappings from Azure Key Vault to Kubernetes secrets

## Prerequisites

### 1. Azure Service Principal Secret

The ClusterSecretStore requires a Kubernetes secret named `azure-secret-sp` in the `external-secrets` namespace containing Azure Service Principal credentials.

**This secret must be created manually** (not stored in Git for security):

```bash
kubectl create secret generic azure-secret-sp \
  --namespace external-secrets \
  --from-literal=ClientID='<your-azure-client-id>' \
  --from-literal=ClientSecret='<your-azure-client-secret>'
```

Or using a SealedSecret (recommended):

```bash
# Create sealed secret
kubectl create secret generic azure-secret-sp \
  --namespace external-secrets \
  --from-literal=ClientID='<your-azure-client-id>' \
  --from-literal=ClientSecret='<your-azure-client-secret>' \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > infrastructure/external-secrets/azure-secret-sp-sealed.yaml
```

### 2. Azure Key Vault Configuration

- **Vault URL**: `https://kv-homelab-cmn.vault.azure.net/`
- **Tenant ID**: `80bd2496-6210-4cee-8517-d3036473cffe`
- **Auth Type**: Service Principal

The Service Principal needs the following Azure Key Vault permissions:
- `Get` on Secrets
- `List` on Secrets (optional, for listing all secrets)

## How It Works

1. The External Secrets Operator is installed via Helm chart
2. The ClusterSecretStore authenticates to Azure Key Vault using the Service Principal credentials
3. Each ExternalSecret specifies:
   - Which Azure Key Vault secret to fetch (via `remoteRef.key`)
   - Which Kubernetes secret key to map it to (via `secretKey`)
   - Which Kubernetes secret to create (via `target.name`)

4. The operator continuously syncs secrets from Azure Key Vault to Kubernetes (default: every 1 hour)

## Adding New Secrets

To sync a new secret from Azure Key Vault:

1. Add the secret to Azure Key Vault (e.g., `my-app-password`)
2. Create an ExternalSecret manifest in `manifests/externalsecret.yaml`:

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app-keyvault
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: my-app-secret
    creationPolicy: Owner
  data:
    - secretKey: PASSWORD
      remoteRef:
        key: my-app-password
```

3. Commit and push to Git - ArgoCD will sync automatically

## Troubleshooting

Check ClusterSecretStore status:
```bash
kubectl get clustersecretstore azure-keyvault
```

Check ExternalSecret status:
```bash
kubectl get externalsecret -A
```

View ExternalSecret events:
```bash
kubectl describe externalsecret <name> -n <namespace>
```
