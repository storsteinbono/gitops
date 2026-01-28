# NetBird with Authentik OIDC Integration

This document describes the NetBird VPN setup with Authentik as the identity provider (IdP).

## Architecture Overview

```
┌─────────────────┐     OIDC      ┌─────────────────┐
│   NetBird       │◄────────────►│    Authentik    │
│   Dashboard     │               │   (IdP/OIDC)    │
└────────┬────────┘               └────────┬────────┘
         │                                 │
         │ gRPC/API                        │ API
         ▼                                 ▼
┌─────────────────┐               ┌─────────────────┐
│   NetBird       │◄─────────────►│   IDP Manager   │
│   Management    │  User Sync    │  (Authentik)    │
└─────────────────┘               └─────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| NetBird Dashboard | Web UI for managing peers, users, and settings |
| NetBird Management | Backend API server, handles peer coordination |
| NetBird Signal | WebRTC signaling server for peer connections |
| Coturn | TURN/STUN server for NAT traversal |
| Authentik | Identity provider for OIDC authentication |
| PostgreSQL | Database for NetBird state |

## Configuration

### Terraform (prd/apps)

The Authentik OAuth2 provider and NetBird configuration are managed by Terraform in:
- `/talos/terraform/environments/prd/apps/`

#### Key Files

| File | Purpose |
|------|---------|
| `modules/netbird-authentik/main.tf` | Creates Authentik OAuth2 provider |
| `modules/netbird/main.tf` | Stores OIDC config in Key Vault |
| `authentik-service-accounts.tf` | Creates service account for IDP manager |

#### Authentik OAuth2 Provider Settings

```hcl
resource "authentik_provider_oauth2" "netbird" {
  name        = "NetBird"
  client_id   = "netbird"
  client_type = "public"  # Dashboard uses PKCE, no client secret

  # Signing key required for JWKS endpoint
  signing_key = data.authentik_certificate_key_pair.default.id

  # Redirect URIs for dashboard
  allowed_redirect_uris = [
    { url = "https://netbird.example.com/#callback", matching_mode = "strict" },
    { url = "https://netbird.example.com/silent-redirect", matching_mode = "strict" },
    { url = "https://netbird.example.com/peers", matching_mode = "strict" },
  ]

  sub_mode    = "hashed_user_id"
  issuer_mode = "per_provider"
  include_claims_in_id_token = true
}
```

#### Service Account for IDP Manager

NetBird uses a service account to sync users from Authentik:

```hcl
resource "authentik_user" "netbird_service_account" {
  username = "netbird-service-account"
  name     = "NetBird Service Account"
  type     = "service_account"
}

resource "authentik_token" "netbird_service_account" {
  identifier   = "netbird-idp-token"
  user         = authentik_user.netbird_service_account.id
  intent       = "api"
  expiring     = false
  retrieve_key = true
}
```

### Key Vault Secrets

Terraform stores these secrets in Azure Key Vault:

| Secret Name | Purpose |
|-------------|---------|
| `netbird-idp-client-id` | OAuth2 client ID |
| `netbird-idp-client-secret` | OAuth2 client secret (empty for public client) |
| `netbird-idp-issuer` | OIDC issuer URL |
| `netbird-idp-admin-username` | Service account username |
| `netbird-idp-admin-password` | Service account API token |
| `netbird-dashboard-auth-authority` | Dashboard OIDC authority |
| `netbird-dashboard-auth-client-id` | Dashboard client ID |
| `netbird-dashboard-auth-audience` | Dashboard audience |

### GitOps (Kubernetes)

Kubernetes manifests are in:
- `/gitops/infrastructure/netbird/manifests/`

#### External Secrets

`external-secret.yaml` syncs Key Vault secrets to Kubernetes:

```yaml
spec:
  data:
    - secretKey: NETBIRD_IDP_MGMT_CLIENT_ID
      remoteRef:
        key: netbird-idp-client-id
    - secretKey: NETBIRD_IDP_MGMT_EXTRA_USERNAME
      remoteRef:
        key: netbird-idp-admin-username
    - secretKey: NETBIRD_IDP_MGMT_EXTRA_PASSWORD
      remoteRef:
        key: netbird-idp-admin-password
    # ... etc
```

#### Management Config

`management-config.yaml` contains the management.json configuration:

```json
{
  "HttpConfig": {
    "AuthAudience": "{{ .NETBIRD_IDP_MGMT_CLIENT_ID }}",
    "AuthUserIDClaim": "sub",
    "OIDCConfigEndpoint": "https://auth.example.com/application/o/netbird/.well-known/openid-configuration",
    "IdpSignKeyRefreshEnabled": true
  }
}
```

**Important:** `IdpSignKeyRefreshEnabled: true` allows the management server to refresh signing keys from Authentik when they rotate.

#### User Approval Job

`disable-user-approval-job.yaml` runs as a PostSync hook to disable user approval:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: disable-approval
          command:
            - psql -h postgresql-rw.postgres.svc -U netbird -d netbird
            - UPDATE accounts SET settings_extra_user_approval_required = false;
            - UPDATE users SET pending_approval = false, blocked = false;
```

## Setup Guide

### Prerequisites

1. Authentik instance running and accessible
2. Azure Key Vault configured with ExternalSecrets
3. PostgreSQL database for NetBird

### Step 1: Apply Terraform

```bash
cd /path/to/talos/terraform/environments/prd/apps
terraform init
terraform apply
```

This creates:
- Authentik OAuth2 provider with signing key
- Authentik application
- Service account and API token
- Key Vault secrets

### Step 2: Sync External Secrets

```bash
kubectl annotate externalsecret netbird-secrets -n netbird force-sync=$(date +%s) --overwrite
kubectl get externalsecret -n netbird  # Verify STATUS=SecretSynced
```

### Step 3: Deploy NetBird

```bash
kubectl apply -k /path/to/gitops/infrastructure/netbird/
# Or let ArgoCD sync
```

### Step 4: Verify OIDC Configuration

Check that the JWKS endpoint returns keys:

```bash
curl -s https://auth.example.com/application/o/netbird/jwks/ | jq '.keys | length'
# Should return 1 or more
```

Check management server loaded OIDC config:

```bash
kubectl logs -n netbird deployment/netbird-management | grep -i oidc
```

### Step 5: Test Login

1. Navigate to https://netbird.example.com
2. Click Login - should redirect to Authentik
3. Authenticate with Authentik credentials
4. Should redirect back to NetBird dashboard

## Troubleshooting

### Token Invalid / Unable to find appropriate key

**Symptom:** Dashboard login fails with "Token invalid" error.

**Cause:** JWKS endpoint has no keys or wrong signing key.

**Solution:**
1. Verify signing key is configured in Authentik OAuth2 provider:
   ```bash
   curl -s -H "Authorization: Bearer $TOKEN" \
     "https://auth.example.com/api/v3/providers/oauth2/" | \
     jq '.results[] | select(.name == "NetBird") | .signing_key'
   ```
2. If `null`, add signing key via Terraform or Authentik UI
3. Verify JWKS has keys:
   ```bash
   curl -s https://auth.example.com/application/o/netbird/jwks/ | jq '.keys'
   ```
4. Enable key refresh in management.json: `"IdpSignKeyRefreshEnabled": true`
5. Restart management: `kubectl rollout restart deployment/netbird-management -n netbird`

### User Pending Approval

**Symptom:** "User is pending approval" error after login.

**Cause:** User approval is enabled in NetBird account settings.

**Solution:**
```bash
# Disable user approval and approve existing users
PGPASS=$(az keyvault secret show --vault-name kv-homelab-cmn --name postgres-netbird-password --query value -o tsv)
kubectl run psql-client --rm -i --restart=Never --image=postgres:15 \
  --env="PGPASSWORD=$PGPASS" -- \
  psql -h postgresql-rw.postgres.svc -U netbird -d netbird -c "
    UPDATE accounts SET settings_extra_user_approval_required = false;
    UPDATE users SET pending_approval = false, blocked = false;
  "
```

### User Blocked

**Symptom:** "User is blocked" error after login.

**Solution:**
```bash
# Same as above - unblock users
UPDATE users SET blocked = false WHERE blocked = true;
```

### 400 Bad Request on Token Exchange

**Symptom:** Browser console shows 400 error on POST to `/application/o/token/`.

**Cause:** Redirect URI mismatch or wrong client type.

**Solution:**
1. Check redirect URI matches exactly (including `#callback`)
2. Verify client_type is `public` for PKCE
3. Check Authentik provider settings via API or UI

### Token Request Failed

**Symptom:** "Token request failed" in browser console.

**Cause:** OAuth2 provider misconfiguration.

**Solution:**
1. Verify client_type is `public` (not `confidential`)
2. Check redirect URIs include `https://netbird.example.com/#callback`
3. Ensure signing key is configured

## Environment Variables

### Dashboard

| Variable | Description |
|----------|-------------|
| `AUTH_AUTHORITY` | OIDC issuer URL |
| `AUTH_CLIENT_ID` | OAuth2 client ID |
| `AUTH_AUDIENCE` | Token audience |
| `AUTH_SUPPORTED_SCOPES` | `openid profile email offline_access api` |
| `NETBIRD_TOKEN_SOURCE` | `idToken` |
| `USE_AUTH0` | `false` |

### Management

| Variable | Description |
|----------|-------------|
| `NETBIRD_IDP_MGMT_CLIENT_ID` | OAuth2 client ID |
| `NETBIRD_IDP_MGMT_CLIENT_SECRET` | Client secret (empty for public) |
| `NETBIRD_IDP_MGMT_EXTRA_USERNAME` | Service account username |
| `NETBIRD_IDP_MGMT_EXTRA_PASSWORD` | Service account API token |
| `NETBIRD_IDP_MGMT_EXTRA_ISSUER` | OIDC issuer URL |

## Improvements Backlog

This section tracks identified improvements based on security and operational best practices.

### Priority Definitions

| Priority | Description | SLA |
|----------|-------------|-----|
| **P1** | Security vulnerabilities or reliability risks | Fix within current sprint |
| **P2** | Availability and resilience improvements | Plan for next sprint |
| **P3** | Maintainability and operational improvements | Backlog |

---

### P1 - Security & Reliability

#### 1.1 Fix Coturn Secret Substitution (Injection Risk)

**Issue:** Using `sed` for secret substitution can fail if secret contains regex special characters.

**File:** `manifests/coturn-deployment.yaml`

**Current:**
```yaml
command:
  - sh
  - -c
  - |
    sed "s/__TURN_SECRET__/$TURN_SECRET/g" /config-template/turnserver.conf > /config/turnserver.conf
```

**Fixed:**
```yaml
command:
  - sh
  - -c
  - |
    export TURN_SECRET
    envsubst '${TURN_SECRET}' < /config-template/turnserver.conf > /config/turnserver.conf
```

**Also update ConfigMap** (`coturn-config.yaml`):
```
# Change from:
static-auth-secret=__TURN_SECRET__

# To:
static-auth-secret=${TURN_SECRET}
```

**Apply:**
```bash
kubectl rollout restart deployment/netbird-coturn -n netbird
```

---

#### 1.2 Add NetworkPolicy (Defense in Depth)

**Issue:** No network segmentation; all pods can communicate freely.

**Create:** `manifests/network-policy.yaml`

```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netbird-default-deny
  namespace: netbird
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netbird-allow-ingress
  namespace: netbird
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: netbird
  policyTypes:
    - Ingress
  ingress:
    # Allow from ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
    # Allow internal netbird communication
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/part-of: netbird
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netbird-allow-egress
  namespace: netbird
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: netbird
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
    # PostgreSQL
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: postgres
      ports:
        - protocol: TCP
          port: 5432
    # Authentik (OIDC)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: authentik
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 9443
    # External HTTPS (for OIDC metadata, TURN)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
```

**Apply:**
```bash
kubectl apply -f manifests/network-policy.yaml
# Verify pods can still communicate
kubectl logs -n netbird deployment/netbird-management --tail=20
```

---

#### 1.3 Add Cert-Manager Annotation to Ingress

**Issue:** TLS certificate management not explicitly configured.

**File:** `manifests/ingress.yaml`

**Add annotation:**
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Adjust to your issuer
```

**Verify:**
```bash
kubectl get certificate -n netbird
kubectl describe ingress netbird -n netbird | grep -A5 TLS
```

---

#### 1.4 Service Account Token Rotation Strategy

**Issue:** Authentik service account token never expires.

**File:** `/talos/terraform/environments/prd/apps/authentik-service-accounts.tf`

**Option A - Set expiry (recommended):**
```hcl
resource "authentik_token" "netbird_service_account" {
  identifier   = "netbird-idp-token"
  user         = authentik_user.netbird_service_account.id
  intent       = "api"
  expiring     = true
  expires      = timeadd(timestamp(), "8760h")  # 1 year
  retrieve_key = true
}
```

**Option B - Document manual rotation:**
```bash
# Rotate token annually
# 1. Generate new token in Authentik
# 2. Update Key Vault secret
az keyvault secret set --vault-name $VAULT_NAME \
  --name netbird-idp-service-account-token \
  --value "$NEW_TOKEN"

# 3. Force ExternalSecret refresh
kubectl annotate externalsecret netbird-secrets -n netbird \
  force-sync=$(date +%s) --overwrite

# 4. Restart management to pick up new token
kubectl rollout restart deployment/netbird-management -n netbird
```

---

### P2 - Availability & Resilience

#### 2.1 Add PodDisruptionBudget

**Issue:** Single replica deployments vulnerable during node maintenance.

**Create:** `manifests/pdb.yaml`

```yaml
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: netbird-management-pdb
  namespace: netbird
spec:
  minAvailable: 0  # Allow disruption but track it
  selector:
    matchLabels:
      app: netbird-management
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: netbird-signal-pdb
  namespace: netbird
spec:
  minAvailable: 0
  selector:
    matchLabels:
      app: netbird-signal
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: netbird-dashboard-pdb
  namespace: netbird
spec:
  minAvailable: 0
  selector:
    matchLabels:
      app: netbird-dashboard
```

**Apply:**
```bash
kubectl apply -f manifests/pdb.yaml
kubectl get pdb -n netbird
```

---

#### 2.2 Increase Replicas for HA (Optional)

**Issue:** Single point of failure for all components.

**Files:** All deployment files

**Change:**
```yaml
spec:
  replicas: 2  # Was: 1
```

**Note:** Management server requires leader election or shared state for multi-replica. Test thoroughly before enabling.

**For dashboard only (stateless, safe to scale):**
```bash
kubectl scale deployment/netbird-dashboard -n netbird --replicas=2
```

---

#### 2.3 Configure PVC Backups

**Issue:** No backup strategy for persistent data.

**Option A - Longhorn Recurring Job:**
```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: netbird-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"  # Daily at 2 AM
  task: backup
  retain: 7
  concurrency: 1
  groups:
    - netbird
```

**Option B - Velero backup:**
```bash
velero schedule create netbird-daily \
  --schedule="0 2 * * *" \
  --include-namespaces=netbird \
  --ttl=168h
```

---

#### 2.4 Use Image Digests for Immutability

**Issue:** `imagePullPolicy: IfNotPresent` with tags can serve stale images.

**Current:**
```yaml
image: netbirdio/management:0.64.1
imagePullPolicy: IfNotPresent
```

**Option A - Use digest:**
```yaml
image: netbirdio/management@sha256:<digest>
imagePullPolicy: IfNotPresent
```

**Get current digest:**
```bash
docker pull netbirdio/management:0.64.1
docker inspect --format='{{index .RepoDigests 0}}' netbirdio/management:0.64.1
```

**Option B - Change pull policy:**
```yaml
imagePullPolicy: Always
```

---

### P3 - Maintainability

#### 3.1 Externalize OIDC Endpoint to Secret

**Issue:** OIDC endpoint hardcoded in ConfigMap; domain change requires ConfigMap edit.

**Current** (`management-config.yaml`):
```json
"OIDCConfigEndpoint": "https://auth.torsteinbo.net/application/o/netbird/.well-known/openid-configuration"
```

**Option A - Use environment variable substitution:**
```json
"OIDCConfigEndpoint": "${NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT}"
```

**Option B - Accept current state:** Document that domain changes require ConfigMap update.

---

#### 3.2 Document Version Alignment Strategy

**Issue:** Dashboard uses `v2.x.x` while management uses `0.x.x` versioning.

**Recommendation:** Add to this README:

```markdown
### Version Management

| Component | Version Format | Update Cadence |
|-----------|---------------|----------------|
| Management | `0.x.x` (semver) | Monthly |
| Signal | `0.x.x` (matches management) | With management |
| Dashboard | `v2.x.x` (independent) | As needed |

**Upgrade procedure:**
1. Check [NetBird releases](https://github.com/netbirdio/netbird/releases)
2. Update management + signal together (same version)
3. Update dashboard independently
4. Test in staging before production
```

---

## Applying Improvements

### Quick Start (P1 Items Only)

```bash
# 1. Fix coturn (edit deployment, apply)
kubectl apply -f manifests/coturn-deployment.yaml
kubectl rollout restart deployment/netbird-coturn -n netbird

# 2. Add network policies
kubectl apply -f manifests/network-policy.yaml

# 3. Add cert-manager annotation (edit ingress, apply)
kubectl apply -f manifests/ingress.yaml

# 4. Verify everything works
kubectl get pods -n netbird
kubectl logs -n netbird deployment/netbird-management --tail=50
```

### Full Sprint Checklist

- [ ] **P1.1** Fix coturn secret substitution
- [ ] **P1.2** Add NetworkPolicy
- [ ] **P1.3** Add cert-manager annotation to ingress
- [ ] **P1.4** Document/implement token rotation
- [ ] **P2.1** Add PodDisruptionBudgets
- [ ] **P2.2** Consider replica increase for HA
- [ ] **P2.3** Configure PVC backups
- [ ] **P2.4** Evaluate image digest pinning
- [ ] **P3.1** Decide on OIDC endpoint externalization
- [ ] **P3.2** Document version strategy

### Validation Commands

```bash
# Check all pods healthy
kubectl get pods -n netbird -o wide

# Verify secrets synced
kubectl get externalsecret -n netbird

# Test OIDC connectivity
kubectl exec -n netbird deployment/netbird-management -- \
  wget -qO- https://auth.torsteinbo.net/application/o/netbird/.well-known/openid-configuration | head -5

# Check network policies applied
kubectl get networkpolicy -n netbird

# Verify PDBs
kubectl get pdb -n netbird

# Test login flow
curl -sI https://netbird.torsteinbo.net | head -5
```

---

## References

- [NetBird Self-Hosted Guide](https://docs.netbird.io/selfhosted/selfhosted-guide)
- [NetBird Identity Providers](https://docs.netbird.io/selfhosted/identity-providers)
- [Authentik OAuth2 Provider](https://docs.goauthentik.io/docs/providers/oauth2/)
- [NetBird API Documentation](https://docs.netbird.io/api/resources/accounts)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Longhorn Backup](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/)
