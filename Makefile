# OneWishOS Docker Stack — Makefile
# Last Updated: 2026-07-06
#
# Usage: make <target>
# Run `make help` to see all available targets.

COMPOSE := docker compose
SERVICE ?=

.PHONY: help up down restart health secrets logs clean up-all pull ps shell-pg shell-redis

help: ## Show this help message
	@echo ""
	@echo "  🐳  OneWishOS Docker Stack"
	@echo "  ─────────────────────────────────────"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

up: ## Start all services (docker compose up -d)
	$(COMPOSE) up -d

down: ## Stop all services (docker compose down)
	$(COMPOSE) down

restart: ## Restart all services (down + up)
	$(MAKE) down
	$(MAKE) up

health: ## Run health check on all services
	@bash scripts/health-check.sh

secrets: ## Inject secrets from 1Password into .env
	@bash scripts/inject-secrets.sh

logs: ## Tail logs (optionally filter: make logs SERVICE=postgres)
ifdef SERVICE
	$(COMPOSE) logs -f $(SERVICE)
else
	$(COMPOSE) logs -f
endif

clean: ## Prune Docker system + dangling volumes
	docker system prune -f
	docker volume prune -f

up-all: ## Full startup: inject secrets → start services
	$(MAKE) secrets
	$(MAKE) up

pull: ## Pull latest images for all services
	$(COMPOSE) pull

ps: ## Show running containers
	$(COMPOSE) ps

shell-pg: ## Open psql shell in Postgres container
	docker exec -it onewish-postgres psql -U onewish

shell-redis: ## Open redis-cli shell in Redis container
	docker exec -it onewish-redis redis-cli
