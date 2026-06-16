#!/usr/bin/env bash
# 单一数据源：所有外部依赖的版本号在此定义。
# lib.sh 直接 source 此文件；easygate 在 repo 上下文中也 source 此文件。
# 升级依赖时只需修改此文件一处，再运行 make test 验证一致性。
#
# 独立安装的 easygate（standalone）会嵌入这些值作为 fallback 默认值。
# Release 工作流（release.yml）会在构建时用 sed 将这些值注入 dist/easygate。

# cloudflared Docker 镜像标签
CLOUDFLARED_VERSION="2026.6.0"

# Traefik Docker 镜像标签（大版本，如 v3.1）
TRAEFIK_IMAGE_TAG="v3.1"

# Traefik 二进制版本（原生模式下载用，具体补丁版本）
TRAEFIK_VERSION="3.1.7"

# whoami demo 服务镜像标签
TRAEFIK_WHOAMI_TAG="v1.10"
