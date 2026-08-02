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
4. For direct HTTP, set `PANEL_HTTP_PORT` to the same port used in `APP_URL`.
   The Panel image configures its internal Caddy listener from `APP_URL`, and
   this template publishes that same port on the host.
5. Select Panel and Wings subnets that do not overlap the LAN, VPNs, or other
   Docker networks.
6. Create the Panel bind mounts for the image's `www-data` user:

   ```bash
   mkdir -p /mnt/user/appdata/pelican/panel/{data,logs,plugins}
   chown -R 82:82 /mnt/user/appdata/pelican/panel
   chmod -R 0770 /mnt/user/appdata/pelican/panel
   ```

The MariaDB image initializes ownership of its own data directory. Wings game
files use `UID` and `GID`, which default to Unraid's `99:100` in `.env.example`.
Keep `BEHIND_PROXY` disabled for direct LAN access. A future reverse-proxy
deployment needs its own listener, trust, and TLS configuration.

## Bootstrap

Wings cannot start until the Panel has generated a node configuration. Keep
`COMPOSE_PROFILES` empty for the first pass:

```bash
docker compose up -d
```

### First Panel installation

Pelican beta35 does not redirect a new installation from the login page to the
installer. Append `/installer` to `APP_URL`; opening only `APP_URL` shows the
login page before an administrator exists.

Keep `.env` available while completing the wizard. Use these values:

| Step | Field | Value |
| --- | --- | --- |
| Requirements | Checks | Continue only when every check passes |
| Environment | App Name | `Pelican` (or another display name) |
| Environment | App URL | The exact `APP_URL` value, without `/installer` |
| Environment | Admin User | A new email, username, and unique password stored in a password manager |
| Database | Driver | `MariaDB` |
| Database | Host | `database` |
| Database | Port | `3306` |
| Database | Database | The `DB_NAME` value |
| Database | Username | The `DB_USER` value |
| Database | Password | The `DB_PASSWORD` value |
| Eggs | Selection | Select none during first installation |
| Cache | Driver | `Redis` |
| Cache | Host | `cache` |
| Cache | Port | `6379` |
| Cache | Username | Leave blank |
| Cache | Password | Leave blank |
| Queue | Driver | `Redis` |
| Session | Driver | `Redis` |

The service names `database` and `cache` resolve only inside the Compose
network. Do not substitute `localhost`, the Docker host address, or
`DB_ROOT_PASSWORD`. Redis has no authentication in this isolated template.
Eggs are optional; add only the required game eggs after the first
administrator login works.

Click **Finish** once and wait for migrations and administrator creation. If
the page appears idle, inspect progress in another terminal with
`docker logs --follow pelican_panel` instead of repeatedly submitting the
form. Installation is complete only after the admin UI opens and the new
administrator can log out and log back in with the saved email and password.

#### Recover an incomplete beta35 installation

Do not delete the containers, Panel data, or MariaDB data. Beta35 writes
`APP_INSTALLED=true` before it runs migrations and creates the administrator.
A failure after that write can send the browser to login without creating a
usable account.

The commands below use the default `CONTAINER_NAME=pelican`. Adjust
`pelican_panel` if the container prefix was changed.

```bash
docker exec pelican_panel grep '^APP_INSTALLED=' /pelican-data/.env
docker exec pelican_panel php artisan migrate:status
docker logs --tail 200 pelican_panel
docker exec pelican_panel sh -lc 'log=$(ls -1t /var/www/html/storage/logs/laravel-*.log 2>/dev/null | head -n 1); if [ -n "$log" ]; then tail -n 200 "$log"; else echo "No Laravel log found"; fi'
```

- If `APP_INSTALLED=false`, reopen `APP_URL/installer` and use the table above.
- If `APP_INSTALLED=true` and every migration is complete, create a separate
   recovery administrator interactively:

   ```bash
   docker exec -it pelican_panel php artisan p:user:make
   ```

   Answer yes when asked whether the user is an administrator. Use a fresh
   email and username, and enter the password at the hidden prompt so it is not
   stored in shell history. Log in with this account, then inspect the original
   account under **Admin > Users**.
- If migrations are incomplete, find and correct the first error in the output
   above. Then finish the installer migration and verify its status before
   creating the recovery administrator:

   ```bash
   docker exec pelican_panel php artisan migrate --force --seed
   docker exec pelican_panel php artisan migrate:status
   ```

Do not manually change `APP_INSTALLED` back to `false` or rerun the full
installer against a partially initialized database.

### Configure the node and Wings

Continue only after the first administrator can log out and back in. Add a node
for this host, using the configured Wings API and SFTP ports.

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