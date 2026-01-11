# MediaManager

MediaManager is a self-hosted media management system for organizing and tracking your movies and TV shows.

## Documentation

- Official Documentation: https://maxdorninger.github.io/MediaManager/
- GitHub Repository: https://github.com/maxdorninger/MediaManager

## Architecture

### Components

- **MediaManager Server**: Main application (port 8000)
- **PostgreSQL Database**: Managed by CloudNativePG cluster
- **NFS Storage**: Media files storage
- **Longhorn Storage**: Application data storage

### Volumes

| Volume | Type | Size | Purpose |
|--------|------|------|---------|
| `mediamanager-media-nfs` | NFS | 1Ti | Media files (movies, TV shows) |
| `mediamanager-data` | Longhorn | 10Gi | Application data (images, torrents, database files) |

### NFS Mount

**Path**: `/volume/a5598d8d-6b2a-4d83-8b9a-b53d7fbd2d94/.srv/.unifi-drive/plex/.data`
**Server**: `172.16.16.91`
**Mounted at**: `/media` in the container

## Configuration

### Initial Setup

1. **Generate Token Secret**

   Generate a random token secret:
   ```bash
   openssl rand -hex 32
   ```

   Update the `token_secret` in `manifests/configmap.yaml`

2. **Configure Admin Email**

   Edit `manifests/configmap.yaml` and update `admin_emails`:
   ```toml
   admin_emails = ["your-email@example.com"]
   ```

3. **Default Admin User**

   On first boot, MediaManager creates a default admin user. Check the pod logs for credentials:
   ```bash
   kubectl logs -n mediamanager -l app=mediamanager
   ```

### Database Connection

Database credentials are managed via ExternalSecret in `postgresql/external-secrets/mediamanager-credentials-external-secret.yaml`:

- Username: `mediamanager`
- Password: From Azure Key Vault (`mediamanager-password`)
- Host: `postgresql-rw.postgres.svc`
- Database: `mediamanager`

The database role and database are managed by CloudNativePG:
- Role: `postgresql/cluster.yaml`
- Database: `postgresql/databases/mediamanager.yaml`

### Environment Variables

The deployment uses these environment variables (populated from the `mediamanager-credentials` secret):

- `DB_HOST`: PostgreSQL hostname
- `DB_PORT`: PostgreSQL port
- `DB_NAME`: Database name
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- `CONFIG_DIR`: Configuration directory path

## Accessing MediaManager

**URL**: https://mediamanager.torsteinbo.net

The ingress is configured in `manifests/ingress.yaml`.

## Optional Integrations

MediaManager supports optional integrations (configure in `manifests/configmap.yaml`):

### Download Clients
- qBittorrent
- Transmission
- SABnzbd

### Indexers
- Prowlarr
- Jackett

### Notifications
- Email (SMTP)
- Gotify
- Ntfy
- Pushover

### Authentication
- OpenID Connect / OAuth 2.0

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n mediamanager
```

### View Logs
```bash
kubectl logs -n mediamanager -l app=mediamanager -f
```

### Check Database Connection
```bash
kubectl exec -it -n mediamanager deployment/mediamanager -- env | grep DB_
```

### Verify NFS Mount
```bash
kubectl exec -it -n mediamanager deployment/mediamanager -- ls -la /media
```

### Check Secrets
```bash
kubectl get secret -n mediamanager
kubectl describe secret mediamanager-credentials -n mediamanager
```

## Upgrading

MediaManager uses the `latest` tag. To upgrade:

```bash
kubectl rollout restart deployment/mediamanager -n mediamanager
```

Or use a specific version in `manifests/deployment.yaml`:
```yaml
image: ghcr.io/maxdorninger/mediamanager/mediamanager:1.12.1
```

## Resource Limits

Current configuration:

```yaml
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 1000m
  memory: 1Gi
```

Adjust in `manifests/deployment.yaml` based on your needs.
