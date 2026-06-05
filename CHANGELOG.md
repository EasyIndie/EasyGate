# Changelog

All notable changes to EasyGate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Native (non-Docker) deployment mode with Traefik binary and file provider.
- Standalone CLI (`easygate`) for unified management of both Docker and native modes.
- Cross-platform PowerShell scripts for Windows support.
- Behavior test suite with mocked binaries (no real Cloudflare account needed).
- Local acceptance tests for Docker and native routing verification.
- CI matrix covering ubuntu, macos, and windows.
- Dependabot configuration for GitHub Actions and Docker image updates.
- Comprehensive documentation (12 docs covering deployment, cleanup, testing, etc.).

### Security
- Pinned cloudflared Docker image to `2025.2.1` (was `:latest`).
- Added SHA256 checksum verification for Traefik binary downloads.
- Added `read_only: true`, `cap_drop: ALL`, and resource limits to all Docker services.
- Added signal trap handling in native deploy to prevent orphan processes.
- Added input validation for ports, domain names, and tunnel names.

### Changed
- Extracted shared shell functions into `scripts/lib.sh` to eliminate code duplication.
- Added `--connect-timeout` to all `curl` download calls.
- CI jobs now have `timeout-minutes: 15` and a weekly scheduled cron run.

## [0.1.0] - 2026-06-05

### Added
- Initial public release.
- Docker Compose deployment with Traefik v3.1 + cloudflared.
- Cloudflare Tunnel integration for zero-public-port HTTPS ingress.
- Demo services (api + test-api) with `traefik/whoami`.
- File provider for non-Docker (LAN / host-port) services.
- Standalone one-liner installer (`curl | bash`).
- Makefile with 19 targets for all operations.
- Cross-platform Bash + PowerShell parity.
- Static tests, behavior tests, and local acceptance tests.
- GitHub Actions CI and Release workflows.
