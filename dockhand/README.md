# Dockhand

- Project: https://github.com/Finsys/dockhand
- Documentation: https://dockhand.pro/manual
- Image: `fnsys/dockhand:latest`

Dockhand is a Docker management UI for containers, Compose stacks, logs, terminals, files, images, and multiple Docker environments.

## Deployment

The template maps host port `12321` to Dockhand's internal HTTP port `3000`:

```sh
docker compose --env-file .env -f docker-compose.yml up -d
```

Use the WUD override when automatic updates are enabled:

```sh
docker compose --env-file .env -f docker-compose.yml -f docker-compose.wud.yml up -d
```

The template stores Dockhand data at `${VOLUMES_BASE}/${CONTAINER_NAME}` and mounts it at `/app/data`. SQLite is used by default. The optional `ENCRYPTION_KEY` should be supplied through the secret-management workflow when a stable external encryption key is required. Never commit the key.

## Security

The Docker socket is mounted read-write. This gives Dockhand effective host-administration authority, including the ability to control containers and access Docker-managed data. Treat Dockhand as a privileged infrastructure control plane.

Keep the service on a private LAN or VPN, or place it behind a trusted authenticating reverse proxy. Do not expose the published port directly to the public internet. A reverse proxy must support HTTP/1.1, WebSocket upgrades, and server-sent events.

Authentication is disabled on first launch. Complete the initial admin setup and enable authentication before using the service or exposing it beyond a trusted bootstrap path.

## Updates

The image intentionally uses the floating `latest` tag. The WUD override watches the image digest for that exact tag and uses the local Docker trigger to pull and recreate Dockhand automatically. Automatic updates can change a privileged management service without a repository review, so check WUD logs and Dockhand availability after updates.

## Stack ownership

Existing Compose stacks remain owned by Git and Ansible. Do not adopt, edit, or redeploy those stacks from Dockhand unless ownership is deliberately migrated first; otherwise UI changes can be overwritten by the next Ansible run.

## License

Dockhand is licensed under the Business Source License 1.1. Personal homelab use is permitted under the upstream terms. Review the upstream license before using Dockhand for commercial, hosted, or managed-service purposes.
