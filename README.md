# Docker container templates

- Made to be as generic as possible
- Defaults are based on Docker running in an Unraid or Ubuntu Server environment
- Templates are usually deployed through automation (e.g. Ansible)

## Conventions

- Each service lives in its own directory with `docker-compose.yml` and optional `.env.example`
- Optional WUD integrations use `docker-compose.wud.yml` override files
- All services use `restart: always`
- Environment variables use `${VAR:-default}` pattern
- Every service has a `com.service` label

### Networking

Every service defines an explicit Docker network with a configurable subnet via `${SUBNET:-10.42.0.0/24}` — even single-container stacks. This is intentional:

- Docker auto-assigns subnets from a default pool (`172.17.0.0/16`, `172.18.0.0/16`, etc.) which can clash with the host network, existing Docker networks, LAN subnets, or VPN tunnels
- On Unraid and Ubuntu Server, these conflicts can cause routing issues or break container connectivity
- By defining the subnet explicitly per stack, each deployment controls its own address space via `.env`
