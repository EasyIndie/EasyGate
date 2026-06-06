LOCAL_COMPOSE=docker compose -f docker-compose.local.yml --env-file .env --profile demo

.PHONY: help install deploy deploy-native uninstall \
        test behavior-test lint \
        local-acceptance local-acceptance-native \
        local-up local-down local-logs \
        network-create

# ── Help ──────────────────────────────────────────────────────────────

help:
	@echo "EasyGate — 轻量家庭 NAT 入口网关"
	@echo ""
	@echo "开发："
	@echo "  make install           安装 CLI 到 ~/.easygate"
	@echo "  make deploy            从源码部署 (Docker Compose)"
	@echo "  make deploy-native     从源码部署 (原生模式)"
	@echo "  make uninstall         卸载 CLI"
	@echo ""
	@echo "测试："
	@echo "  make test              静态检查 + 行为测试"
	@echo "  make behavior-test     仅行为测试 (mock)"
	@echo "  make lint              ShellCheck"
	@echo "  make local-acceptance      本地 Docker 路由验收"
	@echo "  make local-acceptance-native  本地原生路由验收"
	@echo "  make local-up / local-down / local-logs  验收栈管理"
	@echo ""
	@echo "服务管理 (安装后使用 easygate CLI):"
	@echo "  easygate start / stop / restart"
	@echo "  easygate demo start / stop / restart"
	@echo "  easygate ps / logs / purge / uninstall"
	@echo ""

# ── Install ───────────────────────────────────────────────────────────

install:
	EASYGATE_LOCAL_CLI="$(CURDIR)/scripts/easygate" ./scripts/install.sh

deploy:
	./scripts/deploy.sh

deploy-native:
	./scripts/deploy-native.sh

uninstall:
	./scripts/uninstall.sh

# ── Test ──────────────────────────────────────────────────────────────

test:
	./scripts/test.sh

behavior-test:
	./scripts/behavior-test.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/*.sh; \
	else \
		echo "shellcheck 未安装。安装方法: brew install shellcheck / apt install shellcheck"; \
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
		echo "已存在"; \
	else \
		docker network create easygate-proxy && echo "已创建"; \
	fi
