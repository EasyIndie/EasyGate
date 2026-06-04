COMPOSE=docker compose

.PHONY: test up down cleanup purge demo config logs ps

test:
	./scripts/test.sh

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
