# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`db-snapshotter` is a single-purpose container that dumps a PostgreSQL or MySQL database and uploads the zstd-compressed dump to S3-compatible object storage. It is designed to run as a Kubernetes `Job` or `CronJob`. All logic lives in one bash script (`db-snapshot.sh`); the rest of the repo is packaging and deployment scaffolding.

## Architecture (one paragraph)

`db-snapshot.sh` is the container entrypoint. `main()` calls `verify_credentials`, `mkdir /snapshot`, then dispatches to `backup-postgres` or `backup-mysql` based on the first letter of `DB_TYPE` (`p*` → postgres, `m*` → mysql — note the regex, not exact match). Each backup function: runs `pg_dump`/`mysqldump` → `zstd -T0 -19`s the file → `aws s3 cp --endpoint-url="${AWS_ENDPOINT_URL}"` to `s3://${BUCKET_NAME}/${PREFIX}/<file>`. Slack notifications fire on success/failure via helpers (`info`, `warn`, `slack_error`, `slack_success`) when `SLACK_API_TOKEN` is set. Error messages reference `/etc/podinfo/podname` and `/etc/podinfo/namespace`, so Kubernetes manifests must mount the [Downward API podinfo volume](https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/) for the `kubectl logs` hint in Slack alerts to be accurate.

Config split: non-secret values (`DB_TYPE`, `DB_PORT`, `DB_HOSTNAME` (host only — actually a secret in examples), `BUCKET_NAME`, `AWS_ENDPOINT_URL`, `TARGET_DATABASE`, `PREFIX`, `SERVICE_NAME`, `SLACK_CHANNEL_*`) go into a `ConfigMap`; secrets (`DB_USERNAME`, `DB_PASSWORD`, `DB_HOSTNAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SLACK_API_TOKEN`) go into a `Secret`. Both are loaded via `envFrom` on the Pod. See `k8s/example/` for canonical manifests.

The Docker image is `almalinux:10.1` + the `postgresql` (16.x) and `mariadb` (10.11) client packages + the AWS CLI v2 installed from the official zip. Built and pushed to `docker.io/freedomben/db-snapshotter`.

## Common commands

| Task | Command |
|---|---|
| Build the release image (tags both `:${RELEASE_VERSION}` and `:latest`; defaults to `git rev-parse HEAD`) | `./scripts/build-release.sh` |
| Push the release image | `./scripts/push-release.sh` |
| Build dev image (`db-snapshotter-dev:latest`) | `./scripts/build-dev.sh` |
| Run dev image with an interactive bash shell (for poking at the toolchain) | `./scripts/run-dev.sh` |
| "CI test" — currently a no-op stub (`echo 'Skip tests for now'`) | `./scripts/run-ci.sh` |

There is no test suite, no linter, no Makefile. If you add lint/tests, wire them through `scripts/run-ci.sh` so the (currently commented-out) `test` job in `.github/workflows/build-test-deploy.yml` can pick them up.

## CI / release flow

`.github/workflows/build-test-deploy.yml` on push to `main`: authenticates to a DigitalOcean container registry (`DOCKER_CONFIG` secret), then runs `build-release.sh` + `push-release.sh`. The `test`, `deploy-staging`, and `deploy-prod` jobs are commented out — they reference `K8S_TOKEN_DEV` / `K8S_TOKEN_PROD` / `SLACK_TOKEN` secrets and a non-existent `scripts/deploy-release.sh` flow. Treat them as a roadmap, not a working pipeline. The repo contains `scripts/deploy-release.sh` referenced by those commented jobs — verify it works before un-commenting.

## Editing the snapshot script

- The `DB_TYPE` dispatch matches by **first letter only** (`[[ "$DB_TYPE" =~ ^[m] ]]`). `mongodb` or `mssql` would silently route to MySQL. If you add a new DB engine, change the dispatch.
- Output filename format: `${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S')-{pgsql,mysql}.sql` then `.zst` after compression. Backup consumers depend on this pattern.
- The script `cd /snapshot` before dumping; the image creates that directory at build time and `chown`s it to the `docker` user (UID 1000) the container runs as.
- `zstd -T0 -19 --rm` is used for compression (multi-threaded, level 19, removes the source `.sql` on success). Output is `.sql.zst`. The image installs `zstd` directly; `gzip` is no longer used.

## Notes for changes

- Bumping the postgres/mysql client versions: AlmaLinux 10 ships `postgresql` (16.x) and `mariadb` (10.11) directly in AppStream — no DNF modules involved. To pin a different major, change the package name (e.g. `postgresql16` → `postgresql17` once available) or add a third-party repo. The client version must be `>=` the server version, or `pg_dump` will refuse to run against a newer server. Note that `mariadb` is used as the MySQL client; for strict MySQL 8.x compatibility, consider switching to the `mysql8.4` package.
- Kubernetes manifests in `k8s/example/` still use `apiVersion: batch/v1beta1` for the CronJob (commented marker says "use batch/v1 once on k8s 1.21"). Anyone deploying on modern clusters needs to switch to `batch/v1`.
- The `freedomben/db-snapshotter` Docker Hub image is the public artifact; the commented CI also pushes to a DigitalOcean private registry via the `DOCKER_CONFIG` secret.

---

# context-mode — MANDATORY routing rules

You have context-mode MCP tools available. These rules are NOT optional — they protect your context window from flooding. A single unrouted command can dump 56 KB into context and waste the entire session.

## BLOCKED commands — do NOT attempt these

### curl / wget — BLOCKED
Any Bash command containing `curl` or `wget` is intercepted and replaced with an error message. Do NOT retry.
Instead use:
- `ctx_fetch_and_index(url, source)` to fetch and index web pages
- `ctx_execute(language: "javascript", code: "const r = await fetch(...)")` to run HTTP calls in sandbox

### Inline HTTP — BLOCKED
Any Bash command containing `fetch('http`, `requests.get(`, `requests.post(`, `http.get(`, or `http.request(` is intercepted and replaced with an error message. Do NOT retry with Bash.
Instead use:
- `ctx_execute(language, code)` to run HTTP calls in sandbox — only stdout enters context

### WebFetch — BLOCKED
WebFetch calls are denied entirely. The URL is extracted and you are told to use `ctx_fetch_and_index` instead.
Instead use:
- `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` to query the indexed content

## REDIRECTED tools — use sandbox equivalents

### Bash (>20 lines output)
Bash is ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, `npm install`, `pip install`, and other short-output commands.
For everything else, use:
- `ctx_batch_execute(commands, queries)` — run multiple commands + search in ONE call
- `ctx_execute(language: "shell", code: "...")` — run in sandbox, only stdout enters context

### Read (for analysis)
If you are reading a file to **Edit** it → Read is correct (Edit needs content in context).
If you are reading to **analyze, explore, or summarize** → use `ctx_execute_file(path, language, code)` instead. Only your printed summary enters context. The raw file content stays in the sandbox.

### Grep (large results)
Grep results can flood context. Use `ctx_execute(language: "shell", code: "grep ...")` to run searches in sandbox. Only your printed summary enters context.

## Tool selection hierarchy

1. **GATHER**: `ctx_batch_execute(commands, queries)` — Primary tool. Runs all commands, auto-indexes output, returns search results. ONE call replaces 30+ individual calls.
2. **FOLLOW-UP**: `ctx_search(queries: ["q1", "q2", ...])` — Query indexed content. Pass ALL questions as array in ONE call.
3. **PROCESSING**: `ctx_execute(language, code)` | `ctx_execute_file(path, language, code)` — Sandbox execution. Only stdout enters context.
4. **WEB**: `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` — Fetch, chunk, index, query. Raw HTML never enters context.
5. **INDEX**: `ctx_index(content, source)` — Store content in FTS5 knowledge base for later search.

## Subagent routing

When spawning subagents (Agent/Task tool), the routing block is automatically injected into their prompt. Bash-type subagents are upgraded to general-purpose so they have access to MCP tools. You do NOT need to manually instruct subagents about context-mode.

## Output constraints

- Keep responses under 500 words.
- Write artifacts (code, configs, PRDs) to FILES — never return them as inline text. Return only: file path + 1-line description.
- When indexing content, use descriptive source labels so others can `ctx_search(source: "label")` later.

## ctx commands

| Command | Action |
|---------|--------|
| `ctx stats` | Call the `ctx_stats` MCP tool and display the full output verbatim |
| `ctx doctor` | Call the `ctx_doctor` MCP tool, run the returned shell command, display as checklist |
| `ctx upgrade` | Call the `ctx_upgrade` MCP tool, run the returned shell command, display as checklist |
