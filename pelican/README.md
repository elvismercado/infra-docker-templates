# Pelican

Docker-only Pelican deployment for an Unraid or Ubuntu Server host. The stack
uses the official Pelican Panel and Wings images with MariaDB and Redis. It does
not install Pelican packages or services directly on the host.

For the YUNA Ansible deployment, see the
[Pelican role runbook](https://github.com/elvismercado/infra-homelab/tree/main/roles/pelican).

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

## Readiness states

These states are separate:

1. **Container healthy:** MariaDB accepts connections, Redis responds to PING,
   or Panel's Caddy and PHP-FPM processes respond. Panel's Compose healthcheck
   is intentionally liveness-only so a new installation can reach `/installer`.
2. **Panel installed:** `APP_INSTALLED=true`, all Laravel migrations have run,
   required physical tables exist, a Root Admin relationship exists, and that
   administrator can log in and log out successfully.
3. **Node online:** Wings has started, can authenticate with Panel, and the
   node reports online in **Admin > Nodes**.

Do not treat the first state as proof of either of the other two. When the
`wings` profile is enabled, the Ansible role checks the second state before it
starts Wings. The node still needs to be verified in Panel because a running
container or open TCP port does not prove authenticated registration.

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
docker exec pelican_panel supervisorctl -c /etc/supervisord.conf status
docker logs --tail 200 pelican_panel
docker exec pelican_panel sh -lc 'log=$(ls -1t /var/www/html/storage/logs/laravel-*.log 2>/dev/null | head -n 1); if [ -n "$log" ]; then tail -n 200 "$log"; else echo "No Laravel log found"; fi'
```

- If `APP_INSTALLED=false`, reopen `APP_URL/installer` and use the table above.
- If `APP_INSTALLED=true` and every migration is marked `Ran`, verify that the
   physical core and permission tables still exist. At minimum, check `users`,
   `nodes`, `eggs`, `egg_variables`, `database_hosts`, `databases`, `schedules`,
   `user_ssh_keys`, and every table named by Pelican's
   `permission.table_names` configuration. Migration status reflects the
   migration ledger; it does not prove those tables exist.
- If all required tables exist but no usable Root Admin remains, create a
   separate recovery administrator interactively:

   ```bash
   docker exec -it pelican_panel php artisan p:user:make
   ```

   Answer yes when asked whether the user is an administrator. Use a fresh
   email and username, and enter the password at the hidden prompt so it is not
   stored in shell history. Log in with this account, then inspect the original
   account under **Admin > Users**.
- If migrations are genuinely pending, first create and restore-test a logical
   MariaDB backup. Find and correct the first error in the output above, then
   finish the migrations once and verify both status and physical tables before
   creating the recovery administrator:

   ```bash
   docker exec pelican_panel php artisan migrate --force --seed
   docker exec pelican_panel php artisan migrate:status
   ```
- If required tables are absent while their migrations are marked `Ran`, do
   not rerun migrations or edit the migration ledger. Restore a known-good
   backup, repair an isolated database clone, or rebuild disposable state after
   taking verified backups.

Do not manually change `APP_INSTALLED` back to `false` or rerun the full
installer against a partially initialized database.

### Start over with empty persistent state

This is destructive and is not performed by Ansible. Removing containers,
networks, or the Compose project does not reset the installation because Panel
and MariaDB use bind-mounted data under `${VOLUMES_BASE}/${CONTAINER_NAME}`.

Use this procedure only when the existing installation is disposable:

1. Export a logical MariaDB backup and copy any Panel configuration or plugin
   data that must be retained.
2. Stop the stack with `docker compose --profile wings down`.
3. Confirm that no game-server data under
   `${VOLUMES_BASE}/${CONTAINER_NAME}/wings/volumes` must be retained.
4. After an explicit operator confirmation, empty the `database`,
   `panel/data`, `panel/logs`, `panel/plugins`, and `wings/config` directories.
   Preserve `wings/volumes` unless all game-server data is intentionally being
   discarded.
5. Set `COMPOSE_PROFILES` empty and follow the first-pass bootstrap above.

Do not run this procedure to repair a partial install until its database has
been backed up and recovery has been ruled out.

### Configure the node and Wings

Continue only after the first administrator can log out and back in. Add a node
for this host, using the configured Wings API and SFTP ports.

In **Admin > Nodes**, create the first node with these values:

| Field | Value |
| --- | --- |
| Name | A descriptive name for this host |
| FQDN / IP address | The host address reachable by the Panel |
| Connection | `HTTP` for direct HTTP, or the configured HTTPS option |
| Port / daemon connection | The host-side `WINGS_API_PORT` value |
| SFTP port | The host-side `WINGS_SFTP_PORT` value |
| SFTP alias | Leave blank unless a separate display name is required |
| Daemon base directory | The expanded `${VOLUMES_BASE}/${CONTAINER_NAME}/wings` path |
| Use for deployments | Yes |
| Maintenance mode | Disabled |
| Memory, disk, and CPU | Unlimited initially |
| Upload limit | `256` or the default |

For the YUNA Ansible deployment, use `192.168.40.2`, `HTTP`, port `8089`,
SFTP port `2022`, and `/mnt/user/appdata/pelican/wings`. Do not use
the Panel HTTP port for the node connection port. The node connection port is
the host-published Wings port; the Compose mapping forwards it to Wings'
internal API listener.

The daemon base is Wings' `system.root_directory`. Game-server files live in
its `system.data` child, `/mnt/user/appdata/pelican/wings/volumes`; do not enter
that child as the node's daemon base.

Do not wait for the node to show as online before continuing. With the Wings
profile disabled, nothing is listening on the configured API port yet, so an
offline or unreachable node is expected. Creating the node and copying its
generated configuration is the prerequisite for enabling the Wings profile.

After Wings starts, the Panel must reach the host-side Wings API port, and
Wings must reach the Panel URL in its generated `remote` value. If the node
remains offline after startup, check the Wings logs and the host firewall or
port-forwarding rules.

Save the complete generated node YAML from the node's **Configuration File**
tab as:

```text
/mnt/user/appdata/pelican/wings/config/config.yml
```

When Ansible manages this deployment, store the same complete document in the
encrypted vault as a YAML literal block under `pelican_config.wings_config`.
The `|` makes the value a multiline string that the role parses before writing
`config.yml`. Do not paste the generated fields as a nested mapping under
`wings_config`, wrap the document in quotes, or include Markdown code fences:

```yaml
pelican_config:
   wings_enabled: true
   wings_config: |
      <paste the complete Panel-generated YAML here, preserving its indentation>
```

The placeholder is illustrative only. Include every generated section and
credential in the actual encrypted vault value.

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

When Ansible manages this deployment, the Pelican role applies the YUNA
storage and game-network settings before enabling the profile.

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
