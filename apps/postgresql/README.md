# PostgreSQL GitOps Setup

This directory contains the complete GitOps configuration for PostgreSQL with CloudNativePG, converted from your Ansible setup.

## Overview

**What's Included:**
- ✅ PostgreSQL 17 cluster with 3 replicas (HA)
- ✅ All databases: `semaphore_ui`, `immich`, `teslamate`
- ✅ All users: `terraform`, `semaphore`, `immich`, `teslamate`
- ✅ Custom schemas with proper ownership
- ✅ All privileges matching your Ansible configuration
- ✅ pg_hba rules (converted from Ansible)
- ✅ PostgreSQL parameters (logging_collector, listen_addresses, etc.)
- ✅ Automated reconciliation (CronJob runs every 15 minutes)

## Directory Structure

```
apps/postgresql/
├── README.md                    # This file
├── secrets/
│   ├── README.md               # Secret generation instructions
│   └── generate-and-seal-secrets.sh  # Script to generate sealed secrets
└── base/
    ├── namespace.yaml          # postgresql namespace
    ├── sealed-secrets.yaml     # Generated sealed secrets (DO NOT EDIT)
    ├── cluster.yaml            # CloudNativePG cluster config
    ├── databases.yaml          # Database CRDs (semaphore_ui, immich, teslamate)
    ├── user-schema-management.yaml  # SQL scripts + CronJob
    └── kustomization.yaml      # Kustomize configuration

infrastructure/
├── cloudnativepg-operator.yaml  # Operator installation
└── postgresql.yaml              # PostgreSQL cluster application
```

## Initial Setup

### 1. Generate Sealed Secrets

```bash
cd secrets
./generate-and-seal-secrets.sh
```

This will:
- Generate random passwords for all users
- Create Kubernetes secret manifests
- Seal them using kubeseal
- Save to `../base/sealed-secrets.yaml`
- Delete unencrypted secrets

### 2. Deploy the Operator

The operator must be deployed first:

```bash
# Commit the sealed secrets
git add apps/postgresql/base/sealed-secrets.yaml
git commit -m "Add PostgreSQL sealed secrets"
git push

# Apply the operator
kubectl apply -f infrastructure/cloudnativepg-operator.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=300s
```

### 3. Deploy PostgreSQL Cluster

```bash
# Apply the PostgreSQL application
kubectl apply -f infrastructure/postgresql.yaml

# Wait for cluster to be ready (this may take a few minutes)
kubectl wait --for=condition=ready cluster/postgres-cluster \
  -n postgresql \
  --timeout=600s

# Check cluster status
kubectl get cluster -n postgresql
kubectl get pods -n postgresql
```

### 4. Verify Setup

```bash
# Check that all 3 databases were created
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "\l" | grep -E "semaphore_ui|immich|teslamate"

# Check that all users exist
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "\du"

# Check schemas
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -d semaphore_ui -c "\dn"

# Verify CronJob is running
kubectl get cronjob -n postgresql
kubectl get jobs -n postgresql
```

## How It Works

### Declarative Database Creation

Databases are created using CloudNativePG's `Database` CRD:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: semaphore-ui-db
spec:
  name: semaphore_ui
  owner: terraform
  cluster:
    name: postgres-cluster
```

### Automated User/Schema/Privilege Management

A CronJob runs every 15 minutes to ensure:
- Users exist with correct passwords
- Schemas exist with correct owners
- Privileges are granted as specified

The SQL script is **idempotent** - it can run multiple times safely.

### pg_hba Configuration

Your Ansible `pg_hba_entries` are converted to CloudNativePG format in `cluster.yaml`:

**Ansible:**
```yaml
- { contype: host, databases: semaphore_ui, users: terraform, address: samenet, method: scram-sha-256 }
```

**CloudNativePG:**
```yaml
postgresql:
  pg_hba:
    - host semaphore_ui terraform 10.0.0.0/8 scram-sha-256
    - host semaphore_ui terraform 172.16.0.0/12 scram-sha-256
    - host semaphore_ui terraform 192.168.0.0/16 scram-sha-256
```

Note: `samenet` is replaced with common Kubernetes pod CIDR ranges.

## Making Changes

### Adding a New Database

1. Add to `base/databases.yaml`:
```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: newapp-db
  namespace: postgresql
spec:
  name: newapp
  owner: terraform
  cluster:
    name: postgres-cluster
```

2. Update `base/user-schema-management.yaml` SQL script to:
   - Create the user
   - Create the schema
   - Grant privileges

3. Commit and push - ArgoCD will sync automatically.

### Adding a New User

1. Generate sealed secret:
```bash
cd secrets
# Edit generate-and-seal-secrets.sh to add new user
./generate-and-seal-secrets.sh
```

2. Update SQL script in `base/user-schema-management.yaml`

3. Add pg_hba rule in `base/cluster.yaml` if needed

4. Commit and push

### Modifying pg_hba Rules

Edit `base/cluster.yaml` under `spec.postgresql.pg_hba`:

```yaml
postgresql:
  pg_hba:
    - host mydatabase myuser 10.0.0.0/8 scram-sha-256
```

Changes apply within seconds after ArgoCD sync.

### Changing PostgreSQL Parameters

Edit `base/cluster.yaml` under `spec.postgresql.parameters`:

```yaml
postgresql:
  parameters:
    max_connections: "300"  # Change from 200
    logging_collector: "on"  # Change from off
```

**Note:** Some parameter changes require a PostgreSQL restart.

## Connection Information

### From Within Kubernetes

**Read-Write Endpoint (Primary):**
```
postgres-cluster-rw.postgresql.svc.cluster.local:5432
```

**Read-Only Endpoint (Load Balanced Replicas):**
```
postgres-cluster-ro.postgresql.svc.cluster.local:5432
```

### Connection Strings

Connection strings are available in the `postgres-connection-strings` secret:

```bash
# Get semaphore connection string
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.semaphore-uri}' | base64 -d

# Get immich connection string
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.immich-uri}' | base64 -d

# Get teslamate connection string
kubectl get secret postgres-connection-strings -n postgresql \
  -o jsonpath='{.data.teslamate-uri}' | base64 -d
```

### Connecting with psql

```bash
# Connect as postgres superuser
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres

# Connect to specific database
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U terraform -d semaphore_ui

# Port forward for external access
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n postgresql
# Then connect locally: psql -h localhost -U postgres
```

## Ansible to Kubernetes Mapping

| Ansible Config | Kubernetes Implementation |
|----------------|---------------------------|
| `postgresql_databases` | `base/databases.yaml` (Database CRDs) |
| `postgresql_users` | `base/user-schema-management.yaml` (SQL) |
| `postgresql_schemas` | `base/user-schema-management.yaml` (SQL) |
| `postgresql_privs` | `base/user-schema-management.yaml` (SQL) |
| `postgresql_hba_entries` | `base/cluster.yaml` (spec.postgresql.pg_hba) |
| `postgresql_options` | `base/cluster.yaml` (spec.postgresql.parameters) |
| Ansible vault passwords | Sealed Secrets |

## Troubleshooting

### Cluster Not Starting

```bash
# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -f

# Check cluster status
kubectl describe cluster postgres-cluster -n postgresql

# Check pod status
kubectl get pods -n postgresql
kubectl describe pod postgres-cluster-1 -n postgresql
```

### User/Schema Creation Failing

```bash
# Check CronJob logs
kubectl logs -n postgresql -l app=postgres-reconcile --tail=100

# Manually trigger the job
kubectl create job --from=cronjob/postgres-reconcile manual-run-1 -n postgresql
kubectl logs -n postgresql job/manual-run-1 -f
```

### Database Not Created

```bash
# Check Database resource status
kubectl get database -n postgresql
kubectl describe database semaphore-ui-db -n postgresql

# Check if owner user exists
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U postgres -c "\du terraform"
```

### Connection Issues

```bash
# Check pg_hba.conf
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  cat /var/lib/postgresql/data/pgdata/pg_hba.conf

# Test connection from another pod
kubectl run -it --rm psql-test --image=postgres:17-alpine -n postgresql -- \
  psql -h postgres-cluster-rw -U terraform -d semaphore_ui
```

## Backup and Recovery

### Manual Backup

```bash
# Backup a specific database
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  pg_dump -U postgres semaphore_ui > semaphore_ui_backup.sql
```

### Configure Automated Backups

Edit `base/cluster.yaml` and uncomment the backup section:

```yaml
backup:
  retentionPolicy: "30d"
  barmanObjectStore:
    destinationPath: s3://your-bucket/postgres-backups
    # ... configure S3 credentials
```

## Migration from Ansible

To migrate data from your existing Ansible-managed PostgreSQL:

1. **Dump existing databases:**
```bash
# On your Ansible-managed server
pg_dump -U postgres semaphore_ui > semaphore_ui.sql
pg_dump -U postgres immich > immich.sql
pg_dump -U postgres teslamate > teslamate.sql
```

2. **Deploy the Kubernetes cluster** (as described above)

3. **Restore data:**
```bash
# Copy dumps to a pod
kubectl cp semaphore_ui.sql postgresql/postgres-cluster-1:/tmp/

# Restore
kubectl exec -it postgres-cluster-1 -n postgresql -- \
  psql -U terraform -d semaphore_ui < /tmp/semaphore_ui.sql
```

## Security Notes

- ✅ All passwords stored as Sealed Secrets
- ✅ Never commit unencrypted secrets to git
- ✅ TLS/SSL connections enforced (hostssl rules)
- ✅ scram-sha-256 authentication (secure)
- ✅ Network policies can be added for additional security
- ✅ Backup encryption keys regularly (if using backups)

## Next Steps

1. **Add pgAdmin** for GUI management (see main PostgreSQL setup docs)
2. **Configure backups** to S3/MinIO for disaster recovery
3. **Enable monitoring** with Prometheus if available
4. **Set up network policies** for additional security
5. **Configure connection pooling** with PgBouncer if needed

## Support

For CloudNativePG documentation:
- https://cloudnative-pg.io/documentation/current/

For issues with this setup, check:
- ArgoCD UI: Applications → postgresql
- Cluster status: `kubectl get cluster -n postgresql`
- Pod logs: `kubectl logs -n postgresql postgres-cluster-1`
