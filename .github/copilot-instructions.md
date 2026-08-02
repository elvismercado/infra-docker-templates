## Workflow
- When asked to research/analyze/plan: produce analysis and plan only, do not implement
- Wait for explicit "start implementation" before making file changes
- Present plans with relevant files, steps, decisions, and verification criteria
- When asked about a specific tool or project's behavior, research the actual source code first — never give generic/common-pattern answers as a substitute
- Prefer upstream source code (GitHub repos, install scripts) over documentation pages — docs can lag behind the codebase
- Before adding a configuration variable from upstream, verify it actually takes effect in our setup — trace how the variable flows (who reads it, where it's applied). Don't add env vars that are only consumed by scripts we don't run.

## Repo Conventions
- This is a Docker Compose template repository for a homelab (Unraid server)
- Each service lives in its own directory with `docker-compose.yml` and optional `.env.example`
- Optional integrations use `docker-compose.wud.yml` override files where supported.
- The `media/` stack is modular: services defined in subdirectory YAML files (e.g., `requests/seerr.yml`) and included via `extends:` in the main `docker-compose.yml`
- Media stack uses `CONTAINER_NAME_PREFIX` (not `CONTAINER_NAME`) for container naming: `${CONTAINER_NAME_PREFIX:-media}-servicename`
- Keep WUD labels in `docker-compose.wud.yml` override files rather than inline in the main compose.
- All services use `restart: always` (not `unless-stopped`)
- Environment variables use `${VAR:-default}` pattern throughout — no hardcoded values in environment blocks, even for compose-internal references like service names or ports
- When making hardcoded values configurable via env vars, default to the upstream/official default — document recommended overrides for the user's setup in `.env.example`
- Every service has a `com.service` label
- Coolify is an exception: it uses official CDN compose files (`docker-compose.yml` + `docker-compose.prod.yml`) downloaded at setup time, plus a `docker-compose.custom.yml` override for repo conventions (labels, hostname, TZ, postgres host-path volume). It does NOT have a standalone `docker-compose.yml` — see `coolify/setup.sh`.
- Coolify has a companion `teardown.sh` that reverses setup.sh (stops containers, removes network/symlink/SSH keys). Data is preserved by default; pass `--remove-data` to delete.
- Coolify custom override (`docker-compose.custom.yml`) is backed up with a timestamp and overwritten from the repo on each setup.sh run — not preserved across runs.
- Coolify SSH key lifecycle: `setup.sh` generates `id.root@host.docker.internal` on first install only. After first boot, Coolify imports the key into its database and manages keys as `ssh_key@<uuid>` files — setup.sh must not regenerate keys once Coolify is managing them (check for `ssh_key@*` files).
- Coolify SSH mux sockets (`ssh/mux/`) become stale after container restarts — setup.sh cleans them during the stop step.
- Coolify upstream references: `scripts/install.sh` and `scripts/upgrade.sh` on the `v4.x` branch at `github.com/coollabsio/coolify`. CDN files at `cdn.coollabs.io/coolify/`. Always check these when debugging Coolify-specific behavior.
- Coolify volume strategy: CDN bind mounts (e.g., `/data/coolify/ssh`) resolve through the symlink that setup.sh creates (`/data/coolify` → VOLUMES_BASE path). Only Docker named volumes (postgres, redis) need `!override` in `docker-compose.custom.yml` to use host paths instead.
- Scripts must not modify host system files (e.g., `/etc/docker/daemon.json`, systemd units). All configuration happens through `.env` files, compose files, and override files. On Unraid, Docker daemon settings are managed through the Unraid UI.
- When a template uses external config files (e.g., Coolify's CDN `.env`), the `.env.example` should clearly separate setup-time variables from runtime variables with section headers and comments indicating where each goes

## Docker Compose Structure
- Network: `default` with `${SUBNET:-10.42.0.0/24}`, no static IPs
  - Every service defines an explicit network with a configurable subnet — even single-container stacks
  - Prevents Docker from auto-assigning subnets that clash with the host (Unraid, Ubuntu Server), existing Docker networks, LAN, or VPN tunnels
  - The network block is for subnet control, not necessarily container-to-container communication
- YAML anchors for shared config: `x-base-env: &base-env` (TZ, UID, GID)
- Header comment: project URL and name (e.g., `# https://github.com/... \n# Project Name`)
- Container name/hostname: `${CONTAINER_NAME:-servicename}`
- Volumes base: `${VOLUMES_BASE:-/tmp}/${CONTAINER_NAME:-servicename}/...`
- When a service spawns containers via Docker socket (e.g., CI runners), those containers default to Docker's bridge network — NOT the compose network. Use the service's config to set the network to the compose network name, and consider an entrypoint wrapper if the network name is dynamic (derived from env vars)
- When a service reads config from a file but needs values derived from compose env vars, use an entrypoint wrapper script that templates placeholders (e.g., `sed`) before exec-ing the original entrypoint — mount both the config template and wrapper as `:ro`

## Override Files
- WUD: `docker-compose.wud.yml` — header comment describing update strategy
  - Standard labels: `wud.watch=true`, `wud.tag.include=^\d+\.\d+\.\d+$$`
  - Auto-update minor/patch: `wud.trigger.include=smtp.gmail,docker.local:minor`
  - Auto-update all versions (infrastructure/trusted images): `wud.trigger.include=smtp.gmail,docker.local`
  - Notify only (pinned/critical images): `wud.trigger.include=smtp.gmail`
  - WUD self-watch uses `docker.local` without threshold (all versions)

## Security
- No PII in the repository: no real domains, hostnames, passwords, API keys, or internal IPs
- Use `${VARIABLE}` references or generic placeholders (example.com, 10.0.0.x)
