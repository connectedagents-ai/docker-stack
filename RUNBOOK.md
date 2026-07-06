# OneWishOS Docker Stack — Operational Runbook

## Common Commands

```bash
make up          # Start all services
make down        # Stop all services
make restart     # Restart all services
make health      # Run health checks on all services
make secrets     # Inject secrets from 1Password
make up-all      # Inject secrets + start (full bootstrap)
make logs        # Tail logs for all services
make ps          # List running containers
make shell-pg    # Open psql shell
make shell-redis # Open redis-cli shell
make clean       # Prune Docker system (reclaim disk)
```

## Troubleshooting

### Docker Desktop Won't Start

**Symptoms:** `Cannot connect to the Docker daemon` errors

```bash
# 1. Kill all Docker processes
pkill -9 -f "Docker Desktop"
pkill -9 -f "com.docker"
sleep 3

# 2. Check disk space — need at least 8GB free
df -h /

# 3. If disk is low, free space first
rm -rf ~/Library/Caches/pip ~/Library/Caches/go-build ~/Library/Caches/CloudKit
find ~/.gemini/antigravity/scratch -name "node_modules" -type d | xargs rm -rf

# 4. If Docker VM is corrupted, delete it
rm -rf ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw

# 5. Restart Docker Desktop
open -a Docker
# Wait ~75 seconds for startup

# 6. Verify
docker info
```

### Docker 500 Error (Runtime Crashed)

```bash
pkill -9 -f "Docker Desktop"
pkill -9 -f "com.docker.backend"
sleep 5
open -a Docker
sleep 60
cd ~/dev/docker-stack && bash scripts/start.sh --skip-secrets
```

### Container Keeps Restarting

```bash
# Check the logs for the specific container
docker logs onewish-<service> --tail 50

# Common causes:
# - Port already in use → lsof -i :<port>
# - Missing environment variable → check .env
# - Volume permission issue → docker volume inspect <volume>
```

### Postgres Connection Refused

```bash
# 1. Check if container is running
docker ps | grep onewish-postgres

# 2. Check if Postgres is ready
docker exec onewish-postgres pg_isready

# 3. Check credentials in .env
grep POSTGRES .env

# 4. Check Postgres logs
docker logs onewish-postgres --tail 20

# 5. If corrupted, reset the volume
docker compose down
docker volume rm docker-stack_pgdata
make secrets
make up
```

### Disk Full

```bash
# 1. Run the auto-cleanup agent
bash ~/dev/docker-stack/scripts/docker-ops-agent.sh

# 2. Or manual cleanup
docker system prune -f
docker volume prune -f
rm -rf ~/Library/Caches/pip ~/Library/Caches/go-build
find ~ -name "node_modules" -type d -prune -exec rm -rf {} + 2>/dev/null

# 3. Check disk after cleanup
df -h /
```

## Backup Procedures

### Postgres Backup

```bash
# Full database dump
docker exec onewish-postgres pg_dump -U onewish -d onewish > \
  ~/dev/docker-stack/backups/postgres-$(date +%Y%m%d-%H%M%S).sql

# Compressed backup
docker exec onewish-postgres pg_dump -U onewish -d onewish | \
  gzip > ~/dev/docker-stack/backups/postgres-$(date +%Y%m%d-%H%M%S).sql.gz
```

### Qdrant Backup

```bash
# Create snapshot via API
curl -X POST http://localhost:6333/snapshots

# List snapshots
curl http://localhost:6333/snapshots

# Download snapshot
curl http://localhost:6333/snapshots/<snapshot_name> -o \
  ~/dev/docker-stack/backups/qdrant-$(date +%Y%m%d-%H%M%S).snapshot
```

### Full Stack Backup

```bash
# Stop the stack
make down

# Backup all volumes
for vol in pgdata redisdata qdrantdata portainer_data; do
  docker run --rm -v docker-stack_${vol}:/data -v ~/dev/docker-stack/backups:/backup \
    alpine tar czf /backup/${vol}-$(date +%Y%m%d).tar.gz -C /data .
done

# Restart
make up
```

## Recovery Procedures

### Restore Postgres from Backup

```bash
# Stop Postgres
docker compose stop postgres

# Drop and recreate database
docker exec onewish-postgres psql -U onewish -c "DROP DATABASE IF EXISTS onewish;"
docker exec onewish-postgres psql -U onewish -c "CREATE DATABASE onewish;"

# Restore
cat backups/postgres-YYYYMMDD-HHMMSS.sql | docker exec -i onewish-postgres psql -U onewish -d onewish
```

### Complete Reset

```bash
# Nuclear option — destroys all data
make down
docker volume prune -f
make secrets
make up
make health
```

## Monitoring

### Auto-Recovery LaunchAgent

The LaunchAgent at `~/Library/LaunchAgents/com.onewish.docker-ops-agent.plist` runs every 5 minutes:

- Checks if Docker daemon is running
- Restarts stopped containers
- Cleans caches when disk > 85%
- Logs to `~/Library/Logs/onewish-ops-agent.log`

```bash
# Check if LaunchAgent is loaded
launchctl list | grep com.onewish.docker-ops-agent

# Load the agent
launchctl load ~/Library/LaunchAgents/com.onewish.docker-ops-agent.plist

# Unload the agent
launchctl unload ~/Library/LaunchAgents/com.onewish.docker-ops-agent.plist

# View logs
tail -f ~/Library/Logs/onewish-ops-agent.log
```

### Manual Health Check

```bash
make health
# or
bash scripts/health-check.sh
```

## Security

### Secret Rotation

1. Update credentials in 1Password vault `DevStack-Production`
2. Run `make secrets` to re-inject into `.env`
3. Run `make restart` to apply new credentials

### Network Isolation

All services run on the `onewish-net` bridge network. Services are only accessible:
- Via mapped ports on localhost
- Via Traefik reverse proxy (subdomain routing)
- Between containers on the shared Docker network

### Checklist

- [ ] `.env` file is chmod 600 (read/write owner only)
- [ ] `.env` is listed in `.gitignore`
- [ ] `gitleaks` pre-commit hook installed
- [ ] No secrets in compose files (all via env vars)
- [ ] Docker socket mounted read-only where possible
