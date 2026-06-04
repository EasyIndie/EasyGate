COMPOSE=docker compose

.PHONY: bootstrap test up down demo config logs ps

bootstrap:
	./scripts/bootstrap.sh

test:
	./scripts/test.sh

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

demo:
	$(COMPOSE) --profile demo up -d

config:
	$(COMPOSE) --env-file .env config

logs:
	$(COMPOSE) logs -f traefik cloudflared

ps:
	$(COMPOSE) ps
