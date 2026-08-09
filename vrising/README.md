# V Rising Dedicated Server

Runs the official Windows V Rising dedicated server on an x86-64 Linux or
Unraid host through Wine:

```text
Unraid -> Docker -> Wine -> VRisingServer.exe
```

The template uses
[`ghcr.io/ich777/steamcmd:vrising`](https://github.com/ich777/docker-steamcmd-server/tree/vrising).
V Rising has no native Linux dedicated-server binary. SteamCMD downloads App ID
`1829350` anonymously and checks for game updates whenever the container starts.

The current ich777 container image was published on December 19, 2024. That date
applies to its Wine and startup-script layer, not to the V Rising server files.
Those files live in the persistent `serverfiles` directory and SteamCMD updates
them from the current default branch on every container start.

## Persistent layout

With the defaults, runtime files are stored outside the repository:

```text
/mnt/user/appdata/vrising/
|-- steamcmd/
|-- serverfiles/
|   |-- logs/
|   `-- save-data/
|       |-- Saves/
|       `-- Settings/
`-- backups/
```

This layout survives container recreation and keeps saves easy to migrate to a
future AMP, Pterodactyl, or Pelican installation.

## Prerequisites

- x86-64 Docker host with Docker Compose v2
- CPU with AVX support
- Unraid appdata storage, preferably on SSD/cache
- Two unused UDP ports
- OPNsense access when friends connect from the internet

No Steam account, Windows VM, privileged mode, GPU, or RCON port is required for
the default deployment.

## Setup

Copy and edit the environment file:

```bash
cd vrising
cp .env.example .env
nano .env
```

At minimum, replace `SERVER_PASSWORD=CHANGE_ME`. The `.env` file is local
configuration and must not be committed. Keep values containing spaces or shell
characters single-quoted so both Docker Compose and the maintenance scripts can
read them.

Choose a `SUBNET` that does not overlap the LAN, VPNs, or existing Docker
networks. Leave it empty to use `10.42.0.0/24`.

Then run:

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

The first start downloads SteamCMD, the Windows server, and initializes Wine.
It can take several minutes. Follow progress with:

```bash
docker compose logs -f vrising
docker compose ps
```

## Normal operation

```bash
docker compose up -d
docker compose stop --timeout 120
docker compose restart --timeout 120
docker compose logs --tail=200 vrising
docker compose config
```

Use a graceful Compose stop rather than killing Wine. Stunlock recommends
restarting the dedicated server daily. On Unraid, add this command to the User
Scripts plugin and schedule it for a quiet hour:

```bash
cd /path/to/infra-docker-templates/vrising && docker compose restart --timeout 120
```

Every restart also makes SteamCMD check for a game-server update.

## Configuration

The default is a password-protected, listed, secure PvE server for ten concurrent
players:

- `StandardPvE`
- server FPS 30
- empty-server FPS 5
- 30 autosaves at 120-second intervals
- Steam and EOS listings enabled
- EOS IP hiding enabled
- RCON and BepInEx disabled

`MAX_CONNECTED_USERS` controls total concurrent server capacity. It does not
control clan membership. The Ansible role accepts 1 through 128 concurrent
players. The default `ClanSize` is four members and is stored in
`ServerGameSettings.json`.

Host settings in `.env` are passed using V Rising's official `VR_*`
environment overrides. V Rising applies process environment overrides after
the generated JSON, so changing the corresponding value only in
`ServerHostSettings.json` will not override `.env`.

The generated files are:

```text
/mnt/user/appdata/vrising/serverfiles/save-data/Settings/ServerHostSettings.json
/mnt/user/appdata/vrising/serverfiles/save-data/Settings/ServerGameSettings.json
```

The image's `SERVER_NAME` and `WORLD_NAME` values are also supplied on the
command line because its startup script consumes them directly.

### Optional V Rising 1.1 host settings

The following official environment overrides are available but left commented
in `.env.example`, so V Rising keeps its shipped defaults until you opt in:

```bash
VR_DIFFICULTY_PRESET=Difficulty_Normal
VR_AUTOSAVESMARTKEEP='10:1:1,30:0:1,60:0:1,120:0:1,360:0:1,1440:0:1,52560000:99:0'
VR_LAN_MODE=false
VR_RESET_DAYS_INTERVAL=0
VR_DAY_OF_RESET=Any
VR_SAFE_RECONNECT_TIME=300
VR_SAFE_RECONNECT_SLOTS=10
```

Difficulty presets are `Difficulty_Easy`, `Difficulty_Normal`, and
`Difficulty_Brutal`. `VR_RESET_DAYS_INTERVAL=0` disables scheduled world
resets; `VR_DAY_OF_RESET` accepts `Any` or a weekday name. Reconnect time is in
seconds, and reconnect slots reserve capacity for recently disconnected
players.

`VR_AUTOSAVESMARTKEEP` uses comma-separated `minutes:newest:oldest` buckets.
`AUTO_SAVE_COUNT` is still applied after those buckets are evaluated. Keep
normal off-host backups even when smart retention is enabled.

### Custom gameplay settings

`GAME_SETTINGS_PRESET=StandardPvE` loads the game-shipped preset. To use a
custom `ServerGameSettings.json`:

1. Gracefully stop the container.
2. Set `GAME_SETTINGS_PRESET=` in `.env`. An explicit empty value is required;
	a named preset takes precedence over the JSON file.
3. Edit the generated `ServerGameSettings.json`. For example, set the top-level
	gameplay settings below:

	```json
	"ClanSize": 20,
	"TeleportBoundItems": false,
	"BatBoundItems": false,
	"BatBoundShards": false
	```

	The documented current range is 1 through 50. The exact server build should
	be verified before relying on the upper boundary. The three travel settings
	are independent:

	- `TeleportBoundItems=false` allows Waygates while carrying normally bound
	  resource items such as wood, stone, and ore.
	- `BatBoundItems=false` allows Bat Form while carrying normally bound resource
	  items.
	- `BatBoundShards=false` allows Bat Form while carrying Soul Shards.

	The Ansible role exposes positive vault settings for these native flags:

	```yaml
	game_settings_preset: ""
	game_mode_type: PvE
	teleport_with_items: true
	bat_form_with_items: true
	bat_form_with_soul_shards: true
	```

	A configured `true` value maps to the corresponding native `false` value
	because the native keys describe whether the item remains bound. Each setting
	is optional and independent. Omitting one leaves that native JSON key
	unchanged. These settings cover the game's native bound-item categories; they
	do not guarantee that every possible item or every other teleport restriction
	can be bypassed.

	Changing these settings requires a server restart. Items that were created
	before the change may retain their existing bound status, so test both existing
	and newly acquired items after applying the configuration.

	#### Ansible-managed PvE settings

	The Ansible role exposes the following optional settings in the world vault.
	They are merged into `ServerGameSettings.json` only when configured. Omitted
	keys keep their current server values.

	| Vault key | Native JSON key | Range or meaning |
	| --- | --- | --- |
	| `game_mode_type` | `GameModeType` | `PvE` disables player-versus-player combat; `PvP` enables it. |
	| `blood_bound_equipment` | `BloodBoundEquipment` | Boolean. Keep equipped armor and weapons on death. |
	| `death_container_permission` | `DeathContainerPermission` | `0` Anyone, `1` ClanMembers, `2` OnlySelf. |
	| `material_yield_modifier_global` | `MaterialYieldModifier_Global` | `0.25` through `3.0`. Resource yield multiplier. |
	| `drop_table_modifier_general` | `DropTableModifier_General` | `0.25` through `3.0`. General loot multiplier. |
	| `blood_essence_yield_modifier` | `BloodEssenceYieldModifier` | `0.25` through `3.0`. Blood Essence yield multiplier. |
	| `craft_rate_modifier` | `CraftRateModifier` | `0.25` through `6.0`. Crafting speed multiplier. |
	| `refinement_rate_modifier` | `RefinementRateModifier` | `0.25` through `6.0`. Refinement speed multiplier. |
	| `servant_convert_rate_modifier` | `ServantConvertRateModifier` | `0.25` through `6.0`. Servant conversion speed multiplier. |
	| `repair_cost_modifier` | `RepairCostModifier` | `0.0` through `3.0`. Repair cost multiplier. |
	| `durability_drain_modifier` | `DurabilityDrainModifier` | `0.0` through `3.0`. Normal durability drain multiplier. |
	| `castle_relocation_enabled` | `CastleRelocationEnabled` | Boolean. Enable Castle Relocation. |
	| `castle_blood_essence_drain_modifier` | `CastleBloodEssenceDrainModifier` | `0.0` through `3.0`. Castle upkeep multiplier. |
	| `castle_decay_rate_modifier` | `CastleDecayRateModifier` | `0.0` through `3.0`. Unpowered castle decay multiplier. |
	| `inactivity_kill_enabled` | `InactivityKillEnabled` | Boolean. Enable automatic inactive-player removal. |
	| `war_event_game_settings.interval` | `WarEventGameSettings.Interval` | `1` Minimum (30m), `2` VeryShort (1h), `3` Short (1h30m), `4` Medium (2h), `5` Long (4h), `6` VeryLong (8h), `7` Extensive (12h), `8` Maximum (24h). |
	| `war_event_game_settings.major_duration` | `WarEventGameSettings.MajorDuration` | `0` Minimum (15m), `1` VeryShort (20m), `2` Short (25m), `3` Medium (30m), `4` Long (35m), `5` VeryLong (45m), `6` Extensive (1h), `7` Maximum (2h). |
	| `war_event_game_settings.minor_duration` | `WarEventGameSettings.MinorDuration` | Uses the same duration enum as `major_duration`. |

	The Yuna profile sets `game_mode_type: PvE` explicitly so a stale PvP value
	in the existing custom settings file cannot survive the recursive merge. The
	role applies the changed JSON while the server is stopped and restarts it
	before verifying the persisted value.

	For the selected shorter-day profile, configure:

	```yaml
	game_time_modifiers:
	  day_start_hour: 10
	  day_start_minute: 0
	  day_end_hour: 16
	  day_end_minute: 0
	```

	This changes daylight to `10:00-16:00`, leaving an 18-hour in-game night.
	`DayDurationInSeconds` is intentionally unchanged, as are existing Blood Moon
	fields and other unknown `GameTimeModifiers` children. The role merges these
	nested values recursively and restarts the server only when the resulting JSON
	differs. Custom gameplay settings require `game_settings_preset: ""`.

	The Yuna profile keeps Rift Incursions frequent and extends their active time:

	```yaml
	war_event_game_settings:
	  interval: 1
	  major_duration: 5
	  minor_duration: 3
	```

	This selects a 30-minute interval, 45-minute major events, and 30-minute minor
	events. These values are enum indexes, not literal minute counts. Other
	`WarEventGameSettings` children are preserved by the recursive merge.

	The Yuna profile uses `DeathContainerPermission: 2`, so only the owner can loot
	the death container. `BloodBoundEquipment: true` separately keeps equipped gear
	on death. The requested `0.1` durability and castle modifiers are substantial
	reductions: equipment loses durability slowly, powered castles consume little
	Blood Essence, and unpowered castles decay slowly.
4. Start the container.

The clan-size setting is separate from `MAX_CONNECTED_USERS`. A clan may be
configured larger than the simultaneous player cap, but not all members could
join at once.

Do not edit defaults below
`VRisingServer_Data/StreamingAssets/Settings`; SteamCMD updates can overwrite
them.

Administrators can be added one Steam ID per line to:

```text
serverfiles/save-data/Settings/adminlist.txt
```

See [Server administration](#server-administration) for the automated and manual
options.

## Server administration

Admins can use the in-game console for commands such as `kick`, `banuser`,
`bancharacter`, `banned`, and `unban`. Getting admin has two parts: listing your
Steam ID on the server, then authenticating in-game.

### 1. Find your steamID64

You need the 17-digit steamID64 (starts with `7656119...`), not your display
name or vanity URL. Look it up from your profile URL or a resolver such as
steamid.io / steamdb.info.

### 2. List admins

Two options:

**Automated (recommended), driven by `.env`:**

Set `ADMIN_STEAM_IDS` in `.env` (space-, comma-, or newline-separated):

```bash
ADMIN_STEAM_IDS='76561198000000000 76561198000000001'
```

On every container start, the mounted hook (`scripts/adminlist-hook.sh`, mapped
to the image's `/opt/custom/user.sh`) regenerates
`serverfiles/save-data/Settings/adminlist.txt` from this value. V Rising
hot-reloads that file, so to apply a change you can simply restart the container:

```bash
docker compose restart --timeout 120
```

Invalid entries (anything that is not 17 digits) are skipped with a log message.
Because the file is rewritten from `.env` on start, do not also edit
`adminlist.txt` by hand when using this option: your edits are overwritten.

On a completely fresh installation, the hook first lets SteamCMD install the
server and lets ich777 copy the shipped JSON settings. `setup.sh` then performs
one controlled restart to generate `adminlist.txt`. This avoids creating the
persistent `Settings` directory too early.

**Manual, with `ADMIN_STEAM_IDS` empty:**

When `ADMIN_STEAM_IDS` is empty, the hook does nothing and you maintain the file
yourself, one Steam ID per line:

```text
serverfiles/save-data/Settings/adminlist.txt
```

This file also hot-reloads, so no restart is required after editing it directly.

### 3. Authenticate in-game

Enable the console in the game's options, press `` ~ `` to open it, and run
`adminauth`. You are then an admin for that session.

`MAX_CONNECTED_ADMINS` reserves slots so listed admins can join even when the
server is full. Bans made in-game are written to
`serverfiles/save-data/Settings/banlist.txt`, which the hook never modifies.

## Private RCON

RCON is disabled by default. To enable the documented V Rising administration
channel, set a unique password in `.env`:

```bash
RCON_ENABLED=true
RCON_HOST_ADDRESS=127.0.0.1
RCON_BIND_ADDRESS=0.0.0.0
RCON_PORT=25575
RCON_PASSWORD='replace-with-a-unique-password'
```

The maintenance scripts automatically add `docker-compose.rcon.yml` whenever
`RCON_ENABLED=true`. For a manual Compose command, include the override:

```bash
docker compose -f docker-compose.yml -f docker-compose.rcon.yml up -d
```

The default publishes TCP `25575` only on host loopback. A client running on the
Docker host can connect to `127.0.0.1:25575`. If a trusted machine on the private
LAN needs access, set `RCON_HOST_ADDRESS` to the Docker host's private LAN
address and restrict access with the firewall. Never forward or publish RCON on
WAN.

V Rising documents commands including `help`, `announce`, `announcerestart`,
`shutdown`, `cancelshutdown`, `name`, `description`, `password`, `version`, and
`time`. Use a Source RCON-compatible client such as `mcrcon`. The server's
undocumented HTTP API is intentionally not enabled by this template.

## Networking and OPNsense

The defaults are:

| Purpose | Docker mapping | Protocol |
| --- | --- | --- |
| Game traffic | `9876:9876` | UDP |
| Query/server listing | `9877:9877` | UDP |

In OPNsense, create WAN port forwards for UDP `9876` and UDP `9877` to the
Unraid host's LAN address. Allow the associated firewall rules. Do not create a
WAN TCP rule and do not forward RCON.

All of these must match:

1. `.env` (`GAME_PORT` and `QUERY_PORT`)
2. Docker port mappings
3. OPNsense NAT/firewall rules

`HIDE_IP_ADDRESS=true` prevents the address from being advertised in the EOS
listing and lets EOS clients use relay connectivity. It does not replace valid
Docker networking or every required firewall rule.

Friends can find the server by its configured name or use V Rising's direct
connect with the public address and game port. Test from outside the LAN;
ordinary web-based TCP port checkers cannot validate UDP game ports reliably.

## Backups

Create a consistent backup:

```bash
./scripts/backup.sh
```

The script locks maintenance operations, gracefully stops a running server,
archives `save-data`, validates the archive, retains the newest
`BACKUP_RETENTION` archives, and restores the previous running state.

For a daily Unraid User Scripts schedule:

```bash
cd /path/to/infra-docker-templates/vrising && ./scripts/backup.sh
```

Backups are stored under `/mnt/user/appdata/vrising/backups` by default. Include
that directory in off-host or Unraid appdata backups as well.

## Restore

List available backups and restore one explicitly:

```bash
ls -lh /mnt/user/appdata/vrising/backups
./scripts/restore.sh /mnt/user/appdata/vrising/backups/vrising-YYYYMMDD-HHMMSS.tar.gz
```

Restore validates archive contents, asks for confirmation, stops the server,
creates a pre-restore archive, retains the replaced directory as
`save-data.before-restore-TIMESTAMP`, fixes ownership, and starts the server.
Use `--yes` only for deliberate non-interactive recovery.

## Controlled updates

Run:

```bash
./scripts/update.sh
```

This creates a backup, stops the server, retains the current container image
under a local `vrising-rollback` tag, pulls the image, recreates the container,
lets SteamCMD update the game, and waits for health.

If pulling the image fails, the script restarts the untouched original
container. If the replacement cannot start or become healthy, it retags the
saved image as the configured ich777 image, recreates the server with pulls
disabled, and checks health again. The update still exits with an error after a
successful recovery so the failed update remains visible. If automatic recovery
also fails, the script prints the exact manual image-recovery commands.

Container-image rollback does not undo game files already updated by SteamCMD.
V Rising does not provide a general public command for downloading arbitrary
old server builds. Keep backups before major releases and restore saves only
into a compatible server version.

### Optional update monitoring

Apply one optional override at deployment:

```bash
docker compose -f docker-compose.yml -f docker-compose.wud.yml up -d
```

WUD watches digest changes for the exact mutable `vrising` tag and remains
notification-only. Use the backup-first update script for controlled updates
to this stateful server.

## Troubleshooting

### Container remains `starting`

The health check allows 20 minutes for first installation. Inspect:

```bash
docker compose ps
docker compose logs --tail=300 vrising
```

Look for SteamCMD download errors, Wine initialization failures, or
`VRisingServer.exe` exiting.

### Permission denied

Unraid normally uses UID `99` and GID `100`. Confirm those values in `.env` and
ownership below `/mnt/user/appdata/vrising`. Re-running `setup.sh` repairs the
top-level persistent directory ownership.

### Server cannot be found

- Confirm the container is healthy.
- Confirm both configured ports are UDP.
- Confirm `.env`, Compose output, and OPNsense use the same ports.
- Confirm the ISP does not use CGNAT.
- Test from a connection outside the home LAN.

### Settings appear ignored

Check whether `.env` supplies an official `VR_*` override through Compose:

```bash
docker compose config
docker inspect vrising --format '{{range .Config.Env}}{{println .}}{{end}}'
```

For gameplay JSON changes, ensure `GAME_SETTINGS_PRESET` is empty.

## Sources

- [Official V Rising 1.1.x PC dedicated-server instructions](https://github.com/StunlockStudios/vrising-dedicated-server-instructions/blob/master/1.1.x-pc/INSTRUCTIONS.md)
- [Official V Rising 1.1.1 server game settings](https://cdn.stunlock.com/docs/vrising/VRising_Server_Game_Settings_1.1.1.pdf)
- [V Rising clan-size setting reference](https://squadnox.com/guides/v-rising-maximum-clan-size)
- [ich777 V Rising image source](https://github.com/ich777/docker-steamcmd-server/tree/vrising)
- [ich777 Unraid template](https://github.com/ich777/docker-templates/blob/master/ich777/V-Rising.xml)
