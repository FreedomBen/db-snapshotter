# Repository Guidelines

## Project Structure & Module Organization

This repository packages a Bash database snapshotter into a Docker image.
The main runtime entrypoint is `db-snapshot.sh`, which dumps PostgreSQL or
MySQL/MariaDB databases and uploads compressed snapshots to S3-compatible
storage. Docker packaging lives in `Dockerfile`. Helper commands are in
`scripts/`, including build, run, CI, push, and deploy wrappers. Kubernetes
examples live in `k8s/example/` and show Secret, Job, and CronJob usage.
GitHub Actions configuration is in `.github/workflows/`.

## Build, Test, and Development Commands

- `./scripts/build-dev.sh`: build `docker.io/freedomben/db-snapshotter-dev:latest`.
- `./scripts/run-dev.sh`: open an interactive shell inside the dev image.
- `./scripts/build-release.sh`: build release and `latest` image tags; set
  `RELEASE_VERSION` to override the default commit-derived tag.
- `make test`: run the bats test suite against `db-snapshot.sh`.
- `make lint`: run shellcheck on `db-snapshot.sh`.
- `make help`: show available make targets.
- `./scripts/run-ci.sh`: CI entrypoint; invokes `make test`.

Run scripts from the repository root. Docker must be available for image
builds and local container validation. `bats` (>=1.5) and `shellcheck` must be
on the PATH for the test and lint targets; `make bats-install` vendors
bats-core if a system install is unavailable.

## Coding Style & Naming Conventions

Write shell scripts for Bash and keep `#!/usr/bin/env bash`. Follow the
existing style: two-space indentation, opening braces on the next line for
functions, lowercase descriptive function names, quoted variables, and curly
brace interpolation such as `"${VAR}"`. Keep YAML manifests two-space
indented and quote environment variable values consistently.

## Testing Guidelines

Automated tests live under `tests/` and run with bats-core. They stub the
external binaries (`pg_dump`, `mysqldump`, `aws`, `curl`, `zstd`, `openssl`)
via a PATH-prepended `bin/` so the suite never contacts a real database or
S3 endpoint. `db-snapshot.sh` is sourced (its `main` is gated behind a
`BASH_SOURCE` check) so individual functions can be exercised in isolation.
Test fixtures live in `tests/test_helper.bash`; per-test paths are overridden
via `SNAPSHOT_DIR` and `PODINFO_DIR`.

Run the suite with `make test`. For behavior changes that depend on real
client/server protocol details (e.g. bumping the postgres client version),
also validate against a disposable database and non-production bucket. Add
tests alongside any change to dispatch, dump invocation, upload arguments,
encryption, or Slack notification branches.

## Commit & Pull Request Guidelines

Use clear commit subjects without `feat:` or `bug:` prefixes. Include a body
that explains what changed and why. Do not add Claude as a co-author. Pull
requests should include a short behavior summary, validation commands and
results, linked issues when relevant, and notes for changed environment
variables, Kubernetes manifests, or deployment behavior.

## Security & Configuration Tips

Do not commit real credentials. Pass sensitive runtime values through
Kubernetes Secrets or environment variables, not ConfigMaps. Treat database,
AWS, and Slack tokens as production secrets. Prefer non-production buckets,
namespaces, and Slack channels while testing changes.

## Agent-Specific Instructions

Do not read TODO files. Update documentation when code changes affect usage,
and add tests for code changes when test infrastructure exists. Do not create
or switch branches, run git commands, commit, or push unless explicitly asked.
