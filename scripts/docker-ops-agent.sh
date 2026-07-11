#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────
# OneWishOS Docker Ops Agent — Auto-Recovery
# Runs every 5 minutes via LaunchAgent
# ─────────────────────────────────────────────────

LOG_FILE="$HOME/Library/Logs/onewish-ops-agent.log"
COMPOSE_DIR="$HOME/dev/docker-stack"
DISK_THRESHOLD=85

EXPECTED_CONTAINERS=(
    "onewish-traefik"
    "onewish-portainer"
    "onewish-postgres"
    "onewish-redis"
    "onewish-qdrant"
)

# ── Logging helper ──
log() {
    local level="$1"
    shift
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [$level] $*" >> "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log "INFO" "──── Ops Agent run started ────"

# ── Step 1: Check if Docker daemon is running ──
if ! docker info &>/dev/null; then
    log "WARN" "Docker daemon is not running. Skipping this run."
    exit 0
fi

log "INFO" "Docker daemon is running."

# ── Step 2: Check disk usage ──
DISK_USAGE=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}')

if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    log "WARN" "Disk usage at ${DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%). Running cleanup..."

    # Clean npm cache
    if [ -d "$HOME/.npm" ]; then
        rm -rf "$HOME/.npm"
        log "INFO" "Cleaned ~/.npm"
    fi

    # Clean pip cache
    if [ -d "$HOME/.cache/pip" ]; then
        rm -rf "$HOME/.cache/pip"
        log "INFO" "Cleaned ~/.cache/pip"
    fi

    # Clean gradle caches
    if [ -d "$HOME/.gradle/caches" ]; then
        rm -rf "$HOME/.gradle/caches"
        log "INFO" "Cleaned ~/.gradle/caches"
    fi

    # Clean Homebrew cache
    if [ -d "$HOME/Library/Caches/Homebrew" ]; then
        rm -rf "$HOME/Library/Caches/Homebrew"
        log "INFO" "Cleaned ~/Library/Caches/Homebrew"
    fi

    # Docker system prune
    docker system prune -f &>/dev/null
    log "INFO" "Ran docker system prune -f"

    NEW_USAGE=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}')
    log "INFO" "Disk usage after cleanup: ${NEW_USAGE}%"
else
    log "INFO" "Disk usage at ${DISK_USAGE}% — within threshold."
fi

# ── Step 3: Check expected containers ──
RESTARTED=0

for container in "${EXPECTED_CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "not_found")

    if [ "$STATUS" = "true" ]; then
        log "INFO" "$container — running"
    elif [ "$STATUS" = "not_found" ]; then
        log "WARN" "$container — not found. Attempting compose restart..."
        cd "$COMPOSE_DIR" && docker compose up -d 2>/dev/null
        RESTARTED=$((RESTARTED + 1))
        log "INFO" "$container — issued docker compose up -d"
        break  # compose up will handle all missing containers
    else
        log "WARN" "$container — stopped (state: $STATUS). Restarting..."
        docker start "$container" &>/dev/null || true
        RESTARTED=$((RESTARTED + 1))
        log "INFO" "$container — restart attempted"
    fi
done

if [ "$RESTARTED" -gt 0 ]; then
    log "INFO" "Restarted $RESTARTED container(s) this run."
else
    log "INFO" "All containers running normally."
fi

log "INFO" "──── Ops Agent run completed ────"
