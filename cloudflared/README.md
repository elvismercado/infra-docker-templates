# Cloudflare Tunnel

- https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- https://dash.cloudflare.com/one (Zero Trust dashboard)

## Prerequisites

- Domain nameservers on Cloudflare (for auto DNS record creation)
- Cloudflared container running with a valid `TUNNEL_TOKEN`
- Both containers on the same Docker network

No port forwarding or public IP needed on the host.

```
                         Cloudflare Edge (HTTPS)
  Browser ──────────────────► example.com
                                  │
                            ┌─────▼──────┐
                            │  Cloudflare │
                            │   Network   │
                            └─────┬──────┘
                      Encrypted tunnel (QUIC/HTTP2)
                                  │
           ┌──────────────────────▼───────────────────────┐
           │  Docker Host                                 │
           │                                              │
           │  ┌──────────────┐    HTTP    ┌────────────┐  │
           │  │  cloudflared │──────────► │   myapp    │  │
           │  │  (tunnel)    │            │   :8080    │  │
           │  └──────────────┘            └────────────┘  │
           │          docker network (shared)              │
           └──────────────────────────────────────────────┘
```

## Routing a Domain to a Docker App

Cloudflared reaches apps via Docker's internal DNS — use the **container name** as hostname.

1. Zero Trust > **Networks** > **Connectors** > select tunnel > **Public Hostname** > **Add a public hostname**
2. Configure:
   - **Subdomain**: *(leave empty for root domain)*
   - **Domain**: `example.com`
   - **Type**: `HTTP`
   - **URL**: `containername:port` (e.g., `dashy:8080`)
3. Save — Cloudflare auto-creates a CNAME DNS record (requires domain nameservers on Cloudflare)

HTTPS is handled at Cloudflare's edge. The tunnel uses HTTP internally — no certs needed on the origin.

For HTTPS origins (self-signed certs), use **Type**: `HTTPS` and enable **No TLS Verify** under Additional application settings > TLS.

## Networking

### Same Compose Stack

If cloudflared and the app share a compose network, the container name resolves automatically:

```
┌─────────── docker network ────────────┐
│                                       │
│  cloudflared ──► myapp:8080           │
│       (DNS resolves container name)   │
│                                       │
└───────────────────────────────────────┘
```

Service URL in dashboard: `myapp:8080`

The app's `ports:` mapping is optional — only needed for direct host access, not for tunnel routing.

### Cross-Stack

```
┌── cloudflared network ──┐   ┌── app-network ──────────┐
│                         │   │                         │
│  cloudflared ───────────┼──►│  myapp:8080             │
│                         │   │                         │
└─────────────────────────┘   └─────────────────────────┘
         (member of both networks)
```

If the app is in a different compose stack, add its network as external to cloudflared:

```yaml
networks:
  default:
    name: ${CONTAINER_NAME:-cloudflared}
    ipam:
      config:
        - subnet: ${SUBNET:-10.42.0.0/24}
  app-network:
    external: true

services:
  cloudflared:
    networks:
      - default
      - app-network
```

## Metrics & Healthcheck

`TUNNEL_METRICS` defaults to `127.0.0.1:2000` inside the container. The Docker healthcheck uses `cloudflared tunnel --metrics ${TUNNEL_METRICS:-127.0.0.1:2000} ready` to verify active tunnel connectivity (`/ready` returns 200 when connected, 503 otherwise). If `TUNNEL_METRICS` is customized (e.g. `127.0.0.1:3000`), the healthcheck probe dynamically follows the configured endpoint.

To expose metrics externally (e.g., for Prometheus scraping):
1. Set `TUNNEL_METRICS=0.0.0.0:2000` in `.env` (or custom port `0.0.0.0:<port>`)
2. Uncomment `ports:` in `docker-compose.yml` (mapping `${METRICS_PORT:-2000}:2000` or `${METRICS_PORT:-<port>}:<port>`)

Available endpoints:
- `/ready` — 200 when tunnel is connected, 503 otherwise (use with external monitors like Uptime Kuma)
- `/metrics` — Prometheus-format metrics (scrape with Prometheus/Grafana)
