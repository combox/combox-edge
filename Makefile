PROJECT_NAME ?= combox-edge
COMPOSE ?= docker compose --env-file .env -f docker-compose.yml

ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: up down restart ps logs logs-nginx logs-postgres logs-valkey logs-minio config pull reload-nginx validate-strings

up:
	@if [ "$(ADMIN_UI)" = "pgweb" ]; then docker rm -f combox-pgadmin >/dev/null 2>&1 || true; fi
	@if [ "$(ADMIN_UI)" = "pgadmin" ]; then docker rm -f combox-pgweb >/dev/null 2>&1 || true; fi
	$(COMPOSE) up -d --remove-orphans

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) down
	$(COMPOSE) up -d

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=120

logs-nginx:
	$(COMPOSE) logs -f --tail=120 nginx

logs-postgres:
	$(COMPOSE) logs -f --tail=120 postgres

logs-valkey:
	$(COMPOSE) logs -f --tail=120 valkey

logs-minio:
	$(COMPOSE) logs -f --tail=120 minio

config:
	$(COMPOSE) config

pull:
	$(COMPOSE) pull

reload-nginx:
	$(COMPOSE) exec nginx nginx -s reload

validate-strings:
	python scripts/validate_strings.py
