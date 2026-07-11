# OneWish Docker Stack — Runbook

## Quick Start
```bash
cd ~/dev/docker-stack
make up        # Start all services
make health    # Check status
make logs      # Tail logs
```

## Architecture
| Layer | Services | Compose Section |
|-------|----------|-----------------|
| Core | Traefik, Portainer, Postgres (pgvector), Redis, Qdrant | CORE INFRASTRUCTURE |
| Agents | n8n (OneWish:5678), n8n (IntelligenceOS:5679) | AGENTS |
| Monitoring | Grafana (3003), Prometheus (9090), Dozzle (8888) | MONITORING |
| Graph | Neo4j (7474/7687), Neo4j-IntelligenceOS (7475/7688) | GRAPH DATABASE |
| MCP | Filesystem, Memory, Sequential | MCP SERVERS |
| Apps | gforce-web (3000), gforce-router (9000) | APPLICATION |

## Secret Management
Secrets injected from 1Password vault `DevStack-Production`:
```bash
make secrets   # Re-inject all secrets
```

## Troubleshooting

### Container won't start — "not a directory" error
Docker created a bind-mount target as a directory instead of a file.
```bash
rm -rf <path> && touch <path>  # or write actual content
docker start <container>
```

### Health check shows "unhealthy"
Check which HTTP client is available in the image:
```bash
docker exec <container> which curl wget 2>/dev/null
```
Fix the healthcheck to use the available tool.

### Disk full
```bash
docker system prune -f
make clean
```

## Runtime
- **Engine**: OrbStack (not Docker Desktop)
- **Start runtime**: `open -a OrbStack`
- **Socket**: `~/.orbstack/run/docker.sock`
