#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────
# OneWishOS Docker Stack — Full Startup Script
# ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SKIP_SECRETS=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --skip-secrets) SKIP_SECRETS=true ;;
        *) echo "⚠️  Unknown flag: $arg"; exit 1 ;;
    esac
done

cd "$PROJECT_DIR"

# ── Colors ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}🚀 OneWishOS Docker Stack — Starting Up${NC}"
echo "────────────────────────────────────────────"

# ── Step 1: Check Docker daemon ──
echo -e "\n${CYAN}[1/5]${NC} Checking Docker daemon..."

if docker info &>/dev/null; then
    echo -e "  ${GREEN}✅ Docker is running${NC}"
else
    echo -e "  ${YELLOW}⏳ Docker not running. Starting Docker.app...${NC}"
    open -a Docker

    WAIT_SECS=0
    MAX_WAIT=90
    while ! docker info &>/dev/null; do
        if [ "$WAIT_SECS" -ge "$MAX_WAIT" ]; then
            echo -e "  ${RED}❌ Docker failed to start within ${MAX_WAIT}s. Aborting.${NC}"
            exit 1
        fi
        sleep 3
        WAIT_SECS=$((WAIT_SECS + 3))
        echo -e "  ${YELLOW}⏳ Waiting for Docker... (${WAIT_SECS}s / ${MAX_WAIT}s)${NC}"
    done
    echo -e "  ${GREEN}✅ Docker is now running (took ~${WAIT_SECS}s)${NC}"
fi

# ── Step 2: Inject secrets ──
echo -e "\n${CYAN}[2/5]${NC} Secret injection..."

if [ "$SKIP_SECRETS" = true ]; then
    echo -e "  ${YELLOW}⏭️  Skipping secrets (--skip-secrets flag)${NC}"
else
    bash "$SCRIPT_DIR/inject-secrets.sh"
fi

# ── Step 3: Pull latest images ──
echo -e "\n${CYAN}[3/5]${NC} Pulling latest images..."
docker compose pull

# ── Step 4: Start services ──
echo -e "\n${CYAN}[4/5]${NC} Starting services..."
docker compose up -d

# ── Step 5: Health check ──
echo -e "\n${CYAN}[5/5]${NC} Waiting 15s for services to initialize..."
sleep 15

echo -e "\n${BOLD}Running health checks...${NC}"
bash "$SCRIPT_DIR/health-check.sh" || true

# ── Print Service URLs ──
echo ""
echo -e "${BOLD}🌐 Service URLs${NC}"
echo "────────────────────────────────────────────"
echo -e "  ${CYAN}Traefik Dashboard${NC}  → http://localhost:8080"
echo -e "  ${CYAN}Portainer${NC}          → http://localhost:9000"
echo -e "  ${CYAN}Postgres${NC}           → localhost:5432"
echo -e "  ${CYAN}Redis${NC}              → localhost:6379"
echo -e "  ${CYAN}Qdrant Dashboard${NC}   → http://localhost:6333/dashboard"
echo ""
echo -e "${GREEN}${BOLD}✅ OneWishOS Docker Stack is up and running!${NC}"
