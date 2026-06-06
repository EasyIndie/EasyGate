# Contributing to EasyGate

Thanks for your interest in contributing!

## Getting started

1. Fork the repository and clone it locally.
2. Read through the [README.md](README.md) to understand the project architecture.
3. Run `make test` to ensure your environment is ready.

## Development workflow

```bash
# Run static checks
make test

# Run behavior tests (no real Cloudflare account needed)
make behavior-test

# Run local routing acceptance tests
make local-acceptance
make local-acceptance-native
```

### Code style

- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html).
  Use `set -euo pipefail`, double-quote variables, prefer `[[` over `[`.
- **Shared utilities**: Place common functions in `scripts/lib.sh`.
  The standalone CLI (`scripts/easygate`) intentionally duplicates some
  functions — it must remain self-contained for installation.
- **PowerShell**: Keep parity with the Bash scripts. Every Bash script
  should have a corresponding `.ps1` version.
- **Commit messages**: Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`, `chore:`.

### Before submitting a PR

- [ ] `make test` passes.
- [ ] `make behavior-test` passes.
- [ ] Both Bash and PowerShell versions are updated for any script changes.
- [ ] Documentation is updated if behaviour changes.

## Project structure

```
scripts/
  lib.sh              ← Shared shell utilities
  easygate            ← Standalone CLI (self-contained)
  easygate.ps1        ← Windows PowerShell CLI
  deploy.sh/.ps1      ← Docker Compose deployment
  deploy-native.sh/.ps1 ← Native (non-Docker) deployment
  cleanup.sh/.ps1     ← Docker Compose cleanup
  cleanup-native.sh/.ps1 ← Native cleanup
  install.sh/.ps1     ← One-liner installer
  test.sh/.ps1        ← Static checks
  behavior-test.sh/.ps1 ← Mock-based behaviour tests
  local-acceptance.sh/.ps1 ← Docker routing tests
  local-acceptance-native.sh/.ps1 ← Native routing tests
docs/                 ← Detailed documentation
.github/workflows/    ← CI and Release pipelines
```

## Release process

Maintainers: push a `v*` tag (e.g. `v0.2.0`) to trigger the release workflow.
Release notes are auto-generated from commit history by GitHub.
