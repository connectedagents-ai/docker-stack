#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────
# OneWishOS Docker Stack — Health Check
# ─────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="✅"
FAIL="❌"
ALL_HEALTHY=true

declare -A RESULTS

# ── Helper: check container is running ──
container_running() {
    local name="$1"
    docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null | grep -q "true"
}

# ── Check Traefik ──
check_traefik() {
    if ! container_running "onewish-traefik"; then
        RESULTS[Traefik]="$FAIL Container not running"
        ALL_HEALTHY=false
        return
    fi
    if curl -sf http://localhost:8080/ping &>/dev/null; then
        RESULTS[Traefik]="$PASS Healthy"
    else
        RESULTS[Traefik]="$FAIL Ping failed"
        ALL_HEALTHY=false
    fi
}

# ── Check Portainer ──
check_portainer() {
    if ! container_running "onewish-portainer"; then
        RESULTS[Portainer]="$FAIL Container not running"
        ALL_HEALTHY=false
        return
    fi
    if curl -sf http://localhost:9000/api/system/status &>/dev/null; then
        RESULTS[Portainer]="$PASS Healthy"
    else
        RESULTS[Portainer]="$FAIL API unreachable"
        ALL_HEALTHY=false
    fi
}

# ── Check Postgres ──
check_postgres() {
    if ! container_running "onewish-postgres"; then
        RESULTS[Postgres]="$FAIL Container not running"
        ALL_HEALTHY=false
        return
    fi
    if docker exec onewish-postgres pg_isready &>/dev/null; then
        RESULTS[Postgres]="$PASS Healthy"
    else
        RESULTS[Postgres]="$FAIL pg_isready failed"
        ALL_HEALTHY=false
    fi
}

# ── Check Redis ──
check_redis() {
    if ! container_running "onewish-redis"; then
        RESULTS[Redis]="$FAIL Container not running"
        ALL_HEALTHY=false
        return
    fi
    if docker exec onewish-redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        RESULTS[Redis]="$PASS Healthy"
    else
        RESULTS[Redis]="$FAIL PING failed"
        ALL_HEALTHY=false
    fi
}

# ── Check Qdrant ──
check_qdrant() {
    if ! container_running "onewish-qdrant"; then
        RESULTS[Qdrant]="$FAIL Container not running"
        ALL_HEALTHY=false
        return
    fi
    if curl -sf http://localhost:6333/healthz &>/dev/null; then
        RESULTS[Qdrant]="$PASS Healthy"
    else
        RESULTS[Qdrant]="$FAIL Healthz failed"
        ALL_HEALTHY=false
    fi
}

# ── Run all checks ──
echo -e "${BOLD}🏥 OneWishOS Health Check${NC}"
echo "────────────────────────────────────────────"

check_traefik
check_portainer
check_postgres
check_redis
check_qdrant

# ── Print summary table ──
echo ""
printf "  ${BOLD}%-15s %-30s${NC}\n" "SERVICE" "STATUS"
echo "  ─────────────────────────────────────────"

for service in Traefik Portainer Postgres Redis Qdrant; do
    printf "  %-15s %b\n" "$service" "${RESULTS[$service]}"
done

echo ""

if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}${BOLD}✅ All services are healthy!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}❌ Some services are unhealthy. Check above for details.${NC}"
    exit 1
fi
