# Portainer CE

This template follows Portainer's official long-term support channel with
`portainer/portainer-ce:lts`.

## Compose deployment

Create `.env` from `.env.example`, select a unique `SUBNET`, then start the
base service:

```sh
docker compose -f docker-compose.yml up -d
```

Optional overlays can be added to the same command:

```sh
# Edge Agent tunnel on port 8000
docker compose -f docker-compose.yml -f docker-compose.edgecompute.yml up -d

# Legacy HTTP UI on port 9000
docker compose -f docker-compose.yml -f docker-compose.legacy.yml up -d

# WUD notifications and automatic LTS digest updates
docker compose -f docker-compose.yml -f docker-compose.wud.yml up -d
```

The WUD overlay follows digest changes to the floating `lts` tag. It does not
follow the `sts` channel.

## Direct Docker deployment

Using a named volume:

```sh
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts
```

Using an Unraid appdata bind mount:

```sh
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /mnt/user/appdata/portainer:/data portainer/portainer-ce:lts
```

## Access and ports

Open `https://localhost:9443` and replace `localhost` with the host address when
accessing Portainer remotely.

- `9443/tcp`: HTTPS UI and API
- `8000/tcp`: optional Edge Agent tunnel
- `9000/tcp`: optional legacy HTTP UI

## Updating

Take a Portainer configuration backup before updating. Portainer upgrades its
database when the new image starts, so keep the existing `/data` volume or bind
mount and retain the backup for rollback.

For a manual Compose update:

```sh
docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml up -d
```

Include the same optional overlay files used by the running deployment. When
using Portainer Agents, keep every Agent on the same version as the server.
