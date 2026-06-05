COMPOSE=./scripts/compose.sh
LOCAL_COMPOSE=docker compose -f docker-compose.local.yml --env-file .env --profile demo

.PHONY: help install deploy deploy-native uninstall test behavior-test local-acceptance local-acceptance-native local-up local-down local-logs up down cleanup cleanup-native purge purge-native demo config logs ps native-logs lint network-create

# ── Default target ────────────────────────────────────────────────────

help:
	@echo "EasyGate — 轻量家庭 NAT 入口网关"
	@echo ""
	@echo "部署："
	@echo "  make deploy               Docker Compose 模式部署"
	@echo "  make deploy-native        原生模式部署"
	@echo "  make install              安装独立 CLI"
	@echo "  make uninstall            卸载"
	@echo ""
	@echo "管理："
	@echo "  make up / down            启动 / 停止 Compose 栈"
	@echo "  make ps / logs / config   容器状态 / 日志 / 配置"
	@echo "  make demo                 启动演示服务"
	@echo "  make cleanup / purge      清理（保留配置）/ 彻底清理"
	@echo "  make cleanup-native / purge-native  同上（原生模式）"
	@echo ""
	@echo "开发："
	@echo "  make test                 静态检查"
	@echo "  make behavior-test        行为测试（mock）"
	@echo "  make lint                 运行 ShellCheck"
	@echo "  make local-acceptance     本地 Docker 路由验收"
	@echo "  make local-acceptance-native  本地原生路由验收"
	@echo "  make local-up / local-down / local-logs  本地验收栈管理"
	@echo "  make network-create       创建 easygate-proxy Docker 网络"
	@echo ""

# ── Deployment ────────────────────────────────────────────────────────

install:
	EASYGATE_LOCAL_CLI="$(CURDIR)/scripts/easygate" ./scripts/install.sh

deploy:
	./scripts/deploy.sh

deploy-native:
	./scripts/deploy-native.sh

uninstall:
	./scripts/uninstall.sh

# ── Management ────────────────────────────────────────────────────────

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

native-logs:
	@if [ -f "$${EASYGATE_HOME:-$$HOME/.local/share/easygate}/logs/native-traefik.log" ]; then \
		tail -f "$${EASYGATE_HOME:-$$HOME/.local/share/easygate}/logs/native-traefik.log" "$${EASYGATE_HOME:-$$HOME/.local/share/easygate}/logs/native-cloudflared.log"; \
	else \
		echo "原生模式日志不存在，请先执行 make deploy-native"; \
	fi

ps:
	$(COMPOSE) ps

# ── Development ───────────────────────────────────────────────────────

test:
	./scripts/test.sh

behavior-test:
	./scripts/behavior-test.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/*.sh; \
	else \
		echo "shellcheck 未安装。安装方法：brew install shellcheck / apt install shellcheck"; \
		exit 1; \
	fi

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

network-create:
	@if docker network inspect easygate-proxy >/dev/null 2>&1; then \
		echo "Docker 网络 easygate-proxy 已存在"; \
	else \
		docker network create easygate-proxy && echo "已创建 Docker 网络 easygate-proxy"; \
	fi
