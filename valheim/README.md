# Valheim dedicated server

This template runs the maintained
[`community-valheim-tools/valheim-server`](https://github.com/community-valheim-tools/valheim-server-docker)
image. It supports automatic server updates, scheduled world backups, optional
ValheimPlus or BepInEx, crossplay, status monitoring, and Supervisor.

## Persistent data

The container stores all durable data outside the container:

| Host path | Container path | Contents |
| --- | --- | --- |
| `${APP_DATA_PATH}/valheim-server/config` | `/config` | Worlds, admin lists, backups, and mod configuration |
| `${APP_DATA_PATH}/valheim-server/data` | `/opt/valheim` | Downloaded dedicated-server files |

Recreating or updating the container does not delete these directories. Never
remove the config directory without a verified backup.

## Ports

| Host setting | Container port | Protocol | Purpose |
| --- | --- | --- | --- |
| `GAME_PORT` | 2456 | UDP | Game traffic |
| `QUERY_PORT` | 2457 | UDP | Steam query traffic |
| `RPC_PORT` | 2458 | UDP | Crossplay or mod RPC traffic |
| `STATUS_PORT` | 80 | TCP | Optional public-server status endpoint |
| `SUPERVISOR_PORT` | 9001 | TCP | Optional authenticated Supervisor UI/API |

The status and Supervisor ports are absent from the base Compose file. Add
`docker-compose.status.yml` or `docker-compose.supervisor.yml` only when the
matching service is enabled. Do not expose Supervisor without a strong
password and network-level access controls.

## Standalone setup

Copy `.env.example` to `.env` and `valheim.env.example` to `valheim.env`, then
replace `CHANGE_ME` with a password of at least five characters. Validate and
start the base service:

```bash
docker compose --env-file .env config
docker compose --env-file .env up -d --wait
```

Add an optional overlay with an additional `-f` argument. For example:

```bash
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.status.yml \
  up -d --wait
```

The password-bearing `valheim.env` should have mode `0600`.

## Yuna migration

The Ansible declaration intentionally retains both the old container identity
and app-data directory:

```yaml
container_name: valheim_lloesche1
app_dir_name: valheim_lloesche1
volumes_base: /mnt/user/appdata
```

The maintained image is a drop-in successor to the lloesche image. It mounts
the existing world from:

```text
/mnt/user/appdata/valheim_lloesche1/valheim-server/config/worlds_local
```

The new role is commented out until the authoritative world has been confirmed.
Before enabling it on Yuna:

1. Check which Valheim container is running and which app-data directory holds
   the current `.db` and `.fwl` files.
2. Stop if the active world is under a LinuxGSM directory instead of
   `valheim_lloesche1`; that requires a separate copy migration.
3. Stop the active Valheim container gracefully.
4. Back up the complete config directory, not only `worlds_local`.
5. Confirm that the backup contains matching `.db` and `.fwl` world files.
6. Verify that the configured ValheimPlus release supports the installed game
   version and that clients use the same compatible mod version.
7. After backup verification, use the dedicated Yuna Valheim playbook described below.

Example backup on Yuna:

```bash
cd /mnt/user/appdata/valheim_lloesche1
backup="/mnt/user/backups/valheim/valheim-config-$(date +%F_%H-%M-%S).tar.gz"
mkdir -p "$(dirname "$backup")"
tar -czf "$backup" valheim-server/config
tar -tzf "$backup" | grep -E 'worlds_local/.+\.(db|fwl)$'
```

After backing up the existing configuration, verify the backup and set
`valheim_world1_config.migration_backup_confirmed` to `true`. Do not enable the flag before
the backup has been verified.

The dedicated playbook checks that the expected world `.db` and `.fwl` files exist and are
regular files before running the role, preventing deployment from initializing the wrong world.

Deploy after the preflight succeeds:

```bash
cd /path/to/infra-homelab
./runscripts/run-playbook.sh yuna valheim
```

The first startup can take several minutes while SteamCMD updates the server.
Confirm container health, inspect logs, join the expected world, verify admin
access, and test ValheimPlus behavior. Run the playbook a second time and
confirm it does not recreate an unchanged container.

Do not remove the old `valheim_lloesche` or LinuxGSM repository files until the
world has been verified in-game and a post-migration backup exists.

## Updates and backups

The container checks for Valheim updates using `UPDATE_CRON` and, by default,
updates only while idle. `RESTART_CRON` controls scheduled restarts. World
backups are written under `/config/backups` according to `BACKUPS_CRON`.

Before changing the image tag or mod version, create an additional off-host
backup. Container backups protect against gameplay mistakes but do not protect
against disk or host failure.

To create a manual container backup:

```bash
docker exec valheim_lloesche1 supervisorctl restart valheim-backup
```

## Mods and crossplay

ValheimPlus and BepInEx are mutually exclusive in the Ansible role. Existing
ValheimPlus configuration under `/config/valheimplus` is preserved and is not
rewritten during migration. ValheimPlus generally requires compatible client
mods.

Crossplay remains disabled while ValheimPlus is enabled. Enabling crossplay
switches matchmaking to PlayFab and can be incompatible with mods.

## Restore and rollback

For a world restore, stop the container before replacing files in
`/config/worlds_local`. Preserve the failed state separately, restore matching
`.db` and `.fwl` files from one backup, repair ownership if needed, and then
start the container.

If the new image fails before modifying the world, stop it and restore the old
Compose deployment against the unchanged app-data directory. If the game has
upgraded the world format, restore the complete pre-migration config archive
before starting the old image. Keep the pre-migration archive until successful
gameplay and a new backup have both been verified.

## Validation

Run the repository regression test:

```bash
node tests/template-test.mjs
```

On a host with Docker, also render every enabled overlay with
`docker compose config` before deployment.