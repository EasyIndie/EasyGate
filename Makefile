COMPOSE=docker compose
LOCAL_COMPOSE=docker compose -f docker-compose.local.yml --env-file .env --profile demo

.PHONY: deploy deploy-native uninstall test behavior-test local-acceptance local-acceptance-native local-up local-down local-logs up down cleanup cleanup-native purge purge-native demo config logs ps

deploy:
	./scripts/deploy.sh

deploy-native:
	./scripts/deploy-native.sh

uninstall:
	./scripts/uninstall.sh

test:
	./scripts/test.sh

behavior-test:
	./scripts/behavior-test.sh

local-acceptance:
	./scripts/local-acceptance.sh

local-acceptance-native:
	./scripts/local-acceptance-native.sh

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

cleanup-native:
	./scripts/cleanup-native.sh

purge:
	./scripts/cleanup.sh --purge

purge-native:
	./scripts/cleanup-native.sh --purge

demo:
	$(COMPOSE) --profile demo up -d

config:
	$(COMPOSE) --env-file .env config

logs:
	$(COMPOSE) logs -f traefik cloudflared

ps:
	$(COMPOSE) ps
