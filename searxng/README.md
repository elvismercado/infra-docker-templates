- https://docs.searxng.org/admin/installation-docker.html
- https://github.com/searxng/searxng/tree/master/container

## Setup

1. Ensure the config directory exists at your `VOLUMES_BASE/CONTAINER_NAME` path
2. Place `settings.yml`, `limiter.toml`, and `favicons.toml` in the config directory
3. Set `SEARXNG_SECRET` in `.env` to a random string — this overrides `server.secret_key` in `settings.yml`
4. Validate the rendered configuration with `docker compose config --quiet`
5. Start the containers with `docker compose up -d --wait`

## Notes

- The valkey URL is set via the `SEARXNG_VALKEY_URL` compose env var using `CONTAINER_NAME_VALKEY` — no hardcoded URL in `settings.yml`
- `settings.yml` uses the `valkey:` config key (renamed from `redis:` upstream) with `url: false` — the compose env var provides the actual URL
- SearXNG runs as uid 977 internally; `FORCE_OWNERSHIP=true` (default) fixes volume permissions automatically
- Config file updates are detected: if the upstream template is newer, a `.new` file is placed alongside for manual merge
- SearXNG uses `/healthz`; startup waits for Valkey to answer `PING` before SearXNG starts.
- Service names, volume names, and `/etc/searxng` and `/var/cache/searxng` mounts are stable to preserve existing deployments.

## Updates and rollback

- `SEARXNG_VERSION` defaults to `latest`; `VALKEY_VERSION` defaults to the current upstream `9-alpine` line. Tag overrides are supported via `.env`.
- Pull images explicitly with `docker compose pull` before `docker compose up -d --wait`. Merely using the `latest` tag does not refresh an existing local image.
- When What's Up Docker (WUD) is enabled via `docker-compose.wud.yml`, both `searxng` and `valkey` monitor digest updates with `wud.watch.digest=true` and notify / auto-update via `smtp.gmail,docker.local`. The static `wud.tag.include: '^$$'` regex policy excludes all alternative candidate tags, ensuring that `searxng` and `valkey` only receive same-tag digest updates without unintentional tag jumps or regex mismatch vulnerabilities.
- Review upstream SearXNG container changes before deploying a new image.
- To roll back or pin a version, set `SEARXNG_VERSION` or `VALKEY_VERSION` in `.env` to a known dated image tag, run `docker compose pull`, and recreate the stack. The static tag filter prevents WUD from proposing other tags, preserving your pinned versions while continuing to track same-tag digest updates. Persistent configuration and cache data remain in the existing mounts.
- When deployed by `infra-homelab`, publish this template repository first because the Ansible role consumes its remote `main` branch. The SLIME deployment entry point is `playbooks/hosts/slime/slime-searxng.yml` (or `slime.yml`), requiring protected `searxng_secret` supplied via Ansible vault.

## Engine metrics

- `/stats` shows engine scores, result counts, response times, and reliability.
- `/stats/errors` returns engine error details as JSON.
- `/metrics` exposes OpenMetrics data when `general.open_metrics` in `settings.yml` contains a password. Use any HTTP Basic Auth username and that value as the password.
- Metrics contain aggregated engine names, counts, timings, and reliability. They do not contain search queries, result URLs, client IPs, or user identifiers.
- Metrics are held in process memory and reset when SearXNG restarts. Scrape `/metrics` periodically for historical analysis.
- Application logs can contain search terms in outgoing engine URLs and should be protected separately.
