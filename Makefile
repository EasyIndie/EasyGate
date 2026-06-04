COMPOSE=docker compose
LOCAL_COMPOSE=docker compose -f docker-compose.local.yml --env-file .env

.PHONY: deploy uninstall test local-acceptance local-up local-down local-logs up down cleanup purge demo config logs ps

deploy:
	./scripts/deploy.sh

uninstall:
	./scripts/uninstall.sh

test:
	./scripts/test.sh

local-acceptance:
	./scripts/local-acceptance.sh

local-up:
	$(LOCAL_COMPOSE) up -d

local-down:
	$(LOCAL_COMPOSE) down

local-logs:
	$(LOCAL_COMPOSE) logs -f traefik demo-api demo-test-api

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

cleanup:
	./scripts/cleanup.sh

purge:
	./scripts/cleanup.sh --purge

demo:
	$(COMPOSE) --profile demo up -d

config:
	$(COMPOSE) --env-file .env config

logs:
	$(COMPOSE) logs -f traefik cloudflared

ps:
	$(COMPOSE) ps
