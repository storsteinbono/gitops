# PostgreSQL Deployment Guide

Quick reference for deploying PostgreSQL from your Ansible configuration to Kubernetes.

## Prerequisites

- ✅ Kubernetes cluster running
- ✅ ArgoCD installed
- ✅ Longhorn storage class available
- ✅ kubeseal CLI installed
- ✅ kubectl configured

## Quick Start (5 Steps)

### Step 1: Generate Sealed Secrets

```bash
cd apps/postgresql/secrets
./generate-and-seal-secrets.sh
```

**Output:**
```
✅ Success! Sealed secrets saved to: ../base/sealed-secrets.yaml
```

### Step 2: Commit Sealed Secrets

```bash
git add apps/postgresql/base/sealed-secrets.yaml
git commit -m "Add PostgreSQL sealed secrets"
git push
```

### Step 3: Deploy CloudNativePG Operator

```bash
kubectl apply -f infrastructure/cloudnativepg-operator.yaml
```

**Wait for operator:**
```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=300s
```

**Expected output:**
```
pod/cloudnative-pg-<hash> condition met
```

### Step 4: Deploy PostgreSQL Cluster

```bash
kubectl apply -f infrastructure/postgresql.yaml
```

**Monitor deployment:**
```bash
# Watch cluster creation
kubectl get cluster -n postgresql -w

# Watch pods
kubectl get pods -n postgresql -w
```

**Expected state:**
```
NAME               INSTANCES   READY   STATUS                     AGE
postgres-cluster   3           3       Cluster in healthy state   5m

NAME                  READY   STATUS    RESTARTS   AGE
postgres-cluster-1    1/1     Running   0          5m
postgres-cluster-2    1/1     Running   0          4m
postgres-cluster-3    1/1     Running   0          3m
```

### Step 5: Verify Everything

```bash
# Check databases
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "\l" | grep -E "semaphore_ui|immich|teslamate"

# Check users
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "\du" | grep -E "terraform|semaphore|immich|teslamate"

# Check CronJob status
kubectl get cronjob postgres-reconcile -n postgresql
```

**Expected output:**
```
 semaphore_ui | terraform | UTF8     | en_US.utf8 | en_US.utf8 |
 immich       | terraform | UTF8     | en_US.utf8 | en_US.utf8 |
 teslamate    | terraform | UTF8     | en_US.utf8 | en_US.utf8 |

 terraform  | Create DB, Create role           | {}
 semaphore  |                                  | {}
 immich     |                                  | {}
 teslamate  |                                  | {}

NAME                SCHEDULE        SUSPEND   ACTIVE   LAST SCHEDULE   AGE
postgres-reconcile  */15 * * * *    False     0        2m              5m
```

## Deployment Timeline

| Time | Event |
|------|-------|
| T+0s | Apply operator application |
| T+30s | Operator pod running |
| T+45s | Apply PostgreSQL application |
| T+60s | First pod (postgres-cluster-1) starts |
| T+120s | Cluster initialized, databases created |
| T+180s | Second pod (postgres-cluster-2) starts |
| T+240s | Third pod (postgres-cluster-3) starts |
| T+300s | First CronJob run completes |
| T+305s | ✅ Cluster fully operational |

## Accessing Your Databases

### Connection Endpoints

```bash
# Read-Write (Primary)
postgres-cluster-rw.postgresql.svc.cluster.local:5432

# Read-Only (Replicas)
postgres-cluster-ro.postgresql.svc.cluster.local:5432
```

### Get Connection Strings

```bash
# Semaphore UI
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.semaphore-uri}' | base64 -d && echo

# Immich
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.immich-uri}' | base64 -d && echo

# Teslamate
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.teslamate-uri}' | base64 -d && echo
```

### Test Connections

```bash
# Test as terraform user
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U terraform -d semaphore_ui -c "SELECT version();"

# Test as teslamate user
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U teslamate -d teslamate -c "SELECT version();"
```

## What Gets Created

### Namespaces
- `cnpg-system` - CloudNativePG operator
- `postgresql` - PostgreSQL cluster and resources

### In `postgresql` namespace:
- **Cluster:** `postgres-cluster` (3 pods)
- **Services:**
  - `postgres-cluster-rw` - Read-write endpoint
  - `postgres-cluster-ro` - Read-only endpoint
  - `postgres-cluster-r` - Metrics endpoint
- **Databases:** semaphore_ui, immich, teslamate
- **Users:** postgres, terraform, semaphore, immich, teslamate
- **Schemas:** semaphore, immich, teslamate
- **CronJob:** `postgres-reconcile` (every 15 minutes)
- **Secrets:** 6 sealed secrets (passwords)
- **PVCs:** 3 PVCs (one per pod, 50Gi each via Longhorn)

## Configuration Mapping

### Ansible → Kubernetes

```yaml
# Ansible
postgresql_databases: [semaphore_ui, immich, teslamate]

# Kubernetes
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: semaphore-ui-db
spec:
  name: semaphore_ui
  owner: terraform
```

```yaml
# Ansible
postgresql_users:
  - { name: terraform, password: "{{ vault_postgresql_terraform_password }}" }

# Kubernetes (in SQL script)
CREATE ROLE terraform WITH LOGIN PASSWORD :'TERRAFORM_PASSWORD';
```

```yaml
# Ansible
postgresql_hba_entries:
  - { contype: host, databases: semaphore_ui, users: terraform, address: samenet, method: scram-sha-256 }

# Kubernetes (in cluster.yaml)
postgresql:
  pg_hba:
    - host semaphore_ui terraform 10.0.0.0/8 scram-sha-256
```

## Troubleshooting

### Operator Not Starting

```bash
# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Common issues:
# - CRDs not installed (operator installs them)
# - RBAC issues (check ClusterRole)
```

### Cluster Stuck in "Waiting for instances"

```bash
# Check pod status
kubectl describe pod postgres-cluster-1 -n postgresql

# Common issues:
# - PVC not bound (check Longhorn)
# - Image pull errors
# - Insufficient resources
```

### Databases Not Created

```bash
# Check Database resource
kubectl describe database semaphore-ui-db -n postgresql

# Common issues:
# - Owner user doesn't exist yet (wait for CronJob)
# - Cluster not ready
```

### CronJob Failing

```bash
# Check latest job
kubectl get jobs -n postgresql
kubectl logs -n postgresql job/postgres-reconcile-<timestamp>

# Common issues:
# - Secrets not created (run generate-and-seal-secrets.sh)
# - Cluster not ready
# - SQL syntax error (check SQL script)
```

## Rollback

If something goes wrong:

```bash
# Delete the PostgreSQL application (keeps data)
kubectl delete application postgresql -n argocd

# Delete the cluster (WARNING: deletes data)
kubectl delete cluster postgres-cluster -n postgresql

# Delete PVCs (WARNING: deletes all data)
kubectl delete pvc -n postgresql --all

# Start over from Step 3
```

## Post-Deployment

### Verify GitOps is Working

```bash
# Make a change to cluster.yaml
# For example, change max_connections from 200 to 250

git add apps/postgresql/base/cluster.yaml
git commit -m "Increase max_connections to 250"
git push

# Watch ArgoCD sync
kubectl get application postgresql -n argocd -w

# Verify change applied
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "SHOW max_connections;"
```

### Add Your Applications

Your applications can now connect using these environment variables:

```yaml
# Example: Semaphore deployment
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: postgres-connection-strings
        key: semaphore-uri
```

## Next Steps

1. ✅ **Deploy pgAdmin** for GUI management
2. ✅ **Configure backups** to S3/MinIO
3. ✅ **Enable monitoring** if you have Prometheus
4. ✅ **Migrate data** from your Ansible-managed PostgreSQL
5. ✅ **Update your apps** to use new connection strings

## Support

**Check logs:**
```bash
# Operator
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -f

# Cluster
kubectl logs -n postgresql postgres-cluster-1 -f

# CronJob
kubectl logs -n postgresql -l app=postgres-reconcile --tail=50
```

**Check ArgoCD:**
```bash
# Application status
kubectl get application postgresql -n argocd

# Sync status
argocd app get postgresql -n argocd
```

**Documentation:**
- CloudNativePG: https://cloudnative-pg.io/documentation/current/
- This repo: `apps/postgresql/README.md`
