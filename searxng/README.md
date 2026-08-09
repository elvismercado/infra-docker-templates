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

- `SEARXNG_VERSION` defaults to `latest`; `VALKEY_VERSION` defaults to the current upstream `9-alpine` line.
- Pull images explicitly with `docker compose pull` before `docker compose up -d --wait`. Merely using the `latest` tag does not refresh an existing local image.
- Review upstream SearXNG container changes before deploying a new image.
- To roll back, set `SEARXNG_VERSION` to a known dated image tag, run `docker compose pull`, and recreate the stack. Persistent configuration and cache data remain in the existing mounts.
- When deployed by `infra-homelab`, publish this template repository first because the Ansible role consumes its remote `main` branch.

## Engine metrics

- `/stats` shows engine scores, result counts, response times, and reliability.
- `/stats/errors` returns engine error details as JSON.
- `/metrics` exposes OpenMetrics data when `general.open_metrics` in `settings.yml` contains a password. Use any HTTP Basic Auth username and that value as the password.
- Metrics contain aggregated engine names, counts, timings, and reliability. They do not contain search queries, result URLs, client IPs, or user identifiers.
- Metrics are held in process memory and reset when SearXNG restarts. Scrape `/metrics` periodically for historical analysis.
- Application logs can contain search terms in outgoing engine URLs and should be protected separately.
