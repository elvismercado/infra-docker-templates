# Pelican

Docker-only Pelican deployment for an Unraid or Ubuntu Server host. The stack
uses the official Pelican Panel and Wings images with MariaDB and Redis. It does
not install Pelican packages or services directly on the host.

## Architecture

| Service | Purpose | Default host port |
| --- | --- | --- |
| `panel` | Web UI, API, scheduler, and queue | `8080/tcp` |
| `database` | MariaDB Panel database | Internal only |
| `cache` | Redis cache, sessions, and queue | Internal only |
| `wings` | Node API, SFTP, and game-container control | `8081/tcp`, `2022/tcp` |

Panel, MariaDB, and Redis use the isolated `pelican_panel` network. Wings uses
the separate `pelican_wings` management network. Wings creates and manages its
game-container network from `/etc/pelican/config.yml`; that network is not
defined by this Compose project.

## Before Starting

1. Copy `.env.example` to `.env`.
2. Replace both database passwords.
3. Set `APP_URL` to the LAN URL browsers and Wings will use.
4. Select Panel and Wings subnets that do not overlap the LAN, VPNs, or other
   Docker networks.
5. Create the Panel bind mounts for the image's `www-data` user:

   ```bash
   mkdir -p /mnt/user/appdata/pelican/panel/{data,logs,plugins}
   chown -R 82:82 /mnt/user/appdata/pelican/panel
   chmod -R 0770 /mnt/user/appdata/pelican/panel
   ```

The MariaDB image initializes ownership of its own data directory. Wings game
files use `UID` and `GID`, which default to Unraid's `99:100` in `.env.example`.

## Bootstrap

Wings cannot start until the Panel has generated a node configuration. Keep
`COMPOSE_PROFILES` empty for the first pass:

```bash
docker compose up -d
```

Open `APP_URL`, complete the installer, create the first administrator, and add
a node for this host. Use the configured Wings API and SFTP ports when defining
the node.

Save the generated node YAML as:

```text
/mnt/user/appdata/pelican/wings/config/config.yml
```

Before enabling Wings, change every generated `system` storage path used by
game containers to a location below:

```text
/mnt/user/appdata/pelican/wings
```

The source paths must be identical on the host and inside Wings. The host Docker
daemon resolves bind sources for sibling game containers, so a container-only
path such as `/var/lib/pelican` will not work with this template.

Set `COMPOSE_PROFILES=wings`, then start the complete stack:

```bash
docker compose --profile wings up -d
```

When Ansible manages this deployment, store the complete generated YAML in the
encrypted YUNA vault instead of writing it manually. The Pelican role applies
the YUNA storage and game-network settings before enabling the profile.

## WUD

Add the WUD overlay when notifications are enabled:

```bash
docker compose -f docker-compose.yml -f docker-compose.wud.yml --profile wings up -d
```

All four services are notify-only. Pelican remains beta, so do not automatically
upgrade Panel and Wings. Review both changelogs, take backups, upgrade Wings,
then upgrade Panel while keeping their documented compatibility in sync.

## Security

The Docker socket gives Wings near-root control of the host. Restrict Panel,
Wings API, and SFTP ports to trusted LAN clients at the host firewall or router.
Do not expose this HTTP pilot directly to the internet. Add a trusted reverse
proxy and TLS before any public access.

Treat `.env` and `wings/config/config.yml` as secrets. They contain database
credentials and node authentication tokens and must not be committed.

## Backup and Restore

Back up these paths:

- `panel/data`, `panel/logs`, and `panel/plugins`
- a logical MariaDB dump plus the `database` directory while stopped
- `wings/config` and the remaining Wings storage tree

Stop game servers before a Wings storage backup. Test restoration into empty
replacement directories before relying on it. To roll back an image update,
restore the database if its schema changed, pin the previous image tags in
`.env`, and recreate the affected services.