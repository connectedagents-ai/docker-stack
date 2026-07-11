.PHONY: up down restart health logs secrets ps clean pull shell-pg shell-redis

DOCKER := $(shell command -v docker 2>/dev/null || echo /Applications/OrbStack.app/Contents/MacOS/xbin/docker)

up:
	$(DOCKER) compose up -d

up-all: up
	@echo "✅ All services started"

down:
	$(DOCKER) compose down

restart:
	$(DOCKER) compose restart

health:
	@$(DOCKER) ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs:
	$(DOCKER) compose logs -f $(SERVICE)

ps:
	$(DOCKER) compose ps

secrets:
	bash scripts/inject-secrets.sh

clean:
	$(DOCKER) system prune -f

pull:
	$(DOCKER) compose pull

shell-pg:
	$(DOCKER) exec -it onewish-postgres psql -U onewish -d n8n

shell-redis:
	$(DOCKER) exec -it onewish-redis redis-cli
