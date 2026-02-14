# ComBox Edge

![banner](.github/assets/banner.png)

[English](./README.md) | [Русский](./README.ru.md)

Infrastructure edge stack for ComBox services. It provides a single HTTPS entrypoint, shared core services (DB/cache/object storage), and VPN + 2FA-protected admin tools.

## Powered by

[![nginx](https://img.shields.io/badge/nginx-009639?style=for-the-badge&logo=nginx&logoColor=white)](https://nginx.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Valkey](https://img.shields.io/badge/Valkey-DC382D?style=for-the-badge&logo=valkey&logoColor=white)](https://valkey.io)
[![MinIO](https://img.shields.io/badge/MinIO-C72E49?style=for-the-badge&logo=minio&logoColor=white)](https://min.io)
[![Authelia](https://img.shields.io/badge/Authelia-0A4E80?style=for-the-badge&logo=authelia&logoColor=white)](https://www.authelia.com)
[![WireGuard](https://img.shields.io/badge/WireGuard-881698?style=for-the-badge&logo=wireguard&logoColor=white)](https://www.wireguard.com)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)
[![Certbot](https://img.shields.io/badge/Certbot-002B36?style=for-the-badge&logo=certbot&logoColor=white)](https://certbot.eff.org)

## Architecture (high level)

```text
           Internet / LAN
                 |
                 v
            [ Nginx Edge ]  :443
              |      |
              |      +--> /tools/* (VPN allow-list + Authelia 2FA)
              |
              +--> /api/*, /ws/*, /, /site/
                       |
                       v
               Upstreams (Docker network)
            backend / app / site containers

      Core services (same docker stack):
      postgres, valkey, minio
```

## Routing

- `/api/private/*` -> backend upstream pool (`BACKEND_SERVERS`)
- `/api/public/*` -> backend upstream pool (`BACKEND_SERVERS`)
- `/ws/*` -> backend upstream pool (`BACKEND_SERVERS`)
- `/` -> app upstream pool (`APP_SERVERS`)
- `/site/` -> site upstream pool (`SITE_SERVERS`)
- `/tools/minio/` -> MinIO Console (VPN only)
- `/tools/db/` -> PostgreSQL admin UI (VPN only)
- `/tools/logs/` -> Logs UI (VPN only)
- `/tools/wireguard/` -> WireGuard UI (VPN only + 2FA)
- `/healthz` -> static 200 `ok`

Headers:

- `X-Client-Locale` is derived from `Accept-Language` (fallback `EDGE_DEFAULT_LOCALE`).

## Upstreams: multi-machine + mTLS

Edge supports load balancing across many upstream instances (including servers in different countries).

Configure upstream pools in `.env` as server lists:

- `BACKEND_SERVERS` (backend instances)
- `APP_SERVERS` (frontend/app instances)
- `SITE_SERVERS` (marketing/static site instances)

Example:

```bash
BACKEND_SERVERS=
  server backend-1.example.com:8443;
  server backend-2.example.com:8443;

APP_SERVERS=
  server app-1.example.com:443;
  server app-2.example.com:443;
```

### Load balancing + failover (passive)

Nginx uses `least_conn` for upstream selection and passive failover for HTTP requests.

- If an upstream returns `502/503/504` or times out, Nginx retries another upstream (`EDGE_UPSTREAM_TRIES`, `EDGE_UPSTREAM_TRIES_TIMEOUT`).
- WebSocket endpoint `/api/private/v1/ws` does not retry (by design).

### mTLS between edge and upstreams

Edge connects to upstreams over HTTPS and uses mutual TLS.

To bootstrap certificates locally, use the helper script:

```bash
./scripts/init-mtls.sh init
./scripts/init-mtls.sh issue-server <dns_name>
```

Required files on the edge host (mounted into `/etc/nginx/mtls` in container):

- `mtls/ca.crt` (CA that signs upstream server certs and edge client cert)
- `mtls/edge.crt` + `mtls/edge.key` (client cert/key presented by edge)

Env variables:

```bash
EDGE_UPSTREAM_TLS_VERIFY=on
EDGE_UPSTREAM_TLS_TRUSTED_CA=/etc/nginx/mtls/ca.crt
EDGE_UPSTREAM_TLS_CLIENT_CERT=/etc/nginx/mtls/edge.crt
EDGE_UPSTREAM_TLS_CLIENT_KEY=/etc/nginx/mtls/edge.key
```

Upstreams must:

- expose HTTPS
- present a server certificate signed by `ca.crt`
- require and verify the edge client certificate

## Multi-S3 (multiple buckets/providers)

ComBox uses an S3-compatible API for media/attachments (MinIO in local/dev).

To scale beyond a single storage:

- **Multiple providers**: run several S3-compatible backends (AWS S3, Cloudflare R2, Backblaze B2, MinIO, etc.) and treat them as independent targets.
- **Multiple buckets**: split by region, purpose, or lifecycle policy (e.g. `media-eu`, `media-us`, `avatars`, `uploads-temp`).
- **Routing strategy**: decide how objects are mapped to a target:
  - by user region/zone
  - by chat shard/tenant
  - by object type (avatar vs attachment)
  - by time (new uploads to a new bucket)
- **Durability**: enable provider-side replication where available, or implement asynchronous copy jobs.
- **Failover**: for reads, you can fall back to secondary replicas if primary is down; for writes, you typically fail fast or route to a designated secondary.

Implementation note:

- Store object metadata in PostgreSQL with at least: `storage_provider`, `bucket`, `key`, `region`.
- Build URLs either via a CDN domain per bucket/provider, or via signed URLs (recommended).

## Public status page (Gatus)

Edge runs a public status server using Gatus.

- UI: `https://${EDGE_STATUS_DOMAIN}`
- API: `https://${EDGE_STATUS_DOMAIN}/api/v1/endpoints/statuses`

Gatus is configured via `gatus/config.yaml`.

To add more checks (DB/S3/multiple providers), append endpoints in that YAML file.

### Backend deployment (VPS)

For `chat-backend`, enable TLS+mTLS via env vars:

```bash
TLS_ENABLED=true
TLS_CERT_FILE=/etc/combox/mtls/server.crt
TLS_KEY_FILE=/etc/combox/mtls/server.key
TLS_CLIENT_CA_FILE=/etc/combox/mtls/ca.crt
HTTP_ADDRESS=:8443
```

Place the certs on the VPS and mount them into the container (see `chat-backend/docker-compose.edge.yml`).

### App deployment (VPS)

For `chat-app`, `combox-app` stays HTTP (Vite) and `combox-app-mtls` (nginx) provides HTTPS+mTLS entrypoint.

Edge should point to the mTLS endpoint:

- `APP_SERVERS=server <app-host>:443;`

Make sure the VPS exposes only the mTLS endpoint publicly (or only to edge/VPN), and keeps the internal Vite port private.

## Repo layout

- Compose: `docker-compose.yml`
- Env: `.env` and `.env.example`
- Nginx template: `nginx/default.conf.template`
- Authelia templates: `authelia/*.template.yml`
- Valkey config: `valkey/valkey.conf`
- Postgres init scripts: `postgres/init/*.sql`
- MinIO init scripts: `minio/init/*.sh`
- Localized strings: `strings/*.json`

## Quick start

```bash
cp .env.example .env
# edit .env for ports/secrets/upstreams

docker compose --env-file .env -f docker-compose.yml up -d
```

Gateway mode defaults:

- `BACKEND_UPSTREAM=chat-backend:8080`
- `APP_UPSTREAM=chat-app:4173`

Backend and app are expected to run in separate compose stacks, connected to network `chat-edge-core`.

## Multi-machine deployment guide

### Step 1: Configure upstream pools

In `.env`, define the upstream pools:

```bash
BACKEND_SERVERS=
  server backend-1.example.com:8443;
  server backend-2.example.com:8443;

APP_SERVERS=
  server app-1.example.com:443;
  server app-2.example.com:443;
```

### Step 2: Configure mTLS

Create the required files on the edge host:

- `mtls/ca.crt` (CA that signs upstream server certs and edge client cert)
- `mtls/edge.crt` + `mtls/edge.key` (client cert/key presented by edge)

Set the env variables:

```bash
EDGE_UPSTREAM_TLS_VERIFY=on
EDGE_UPSTREAM_TLS_TRUSTED_CA=/etc/nginx/mtls/ca.crt
EDGE_UPSTREAM_TLS_CLIENT_CERT=/etc/nginx/mtls/edge.crt
EDGE_UPSTREAM_TLS_CLIENT_KEY=/etc/nginx/mtls/edge.key
```

### Step 3: Deploy backend and app

Deploy the backend and app on separate VPS instances, following the instructions above.

### Step 4: Connect to edge

Start the edge core:

```bash
make up
```

2. Start backend in edge network (no published ports):

```bash
cd ../chat-backend
make edge-up
```

3. Start app in edge network (no published ports):

```bash
cd ../chat-app
make edge-up
```

In this mode, backend/app accept traffic only from Docker network peers (edge nginx), not from direct host HTTP ports.

## Admin UI selection

Pick one in `.env`:

- `ADMIN_UI=pgweb`
- `COMPOSE_PROFILES=admin-pgweb`

or

- `ADMIN_UI=pgadmin`
- `COMPOSE_PROFILES=admin-pgadmin`

If you switch the admin UI, remove the previously running admin container once:

- switch to `pgweb`: `docker rm -f chat-pgadmin || true`
- switch to `pgadmin`: `docker rm -f chat-pgweb || true`

Or use `make up` (it cleans old admin container automatically).

## TLS (auto-renew)

- Edge exposes HTTP/HTTPS on `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT` (defaults `80/443`).
- `tls-init` creates a temporary self-signed cert for first boot.
- `certbot` requests and renews Let’s Encrypt certificates automatically.
- `nginx` watches cert files and reloads when certificates are updated.

For production issuance set in `.env`:

- `EDGE_TLS_DOMAIN=<your-domain>`
- `CERTBOT_EMAIL=<your-email>`
- `CERTBOT_STAGING=0`

## VPN access (WireGuard) and tools security

- WG UDP endpoint remains public: `${WG_PORT}` (default `51820/udp`).
- WG UI is available only via edge route with mandatory 2FA:
  - `https://<server-host>/tools/wireguard/`
- Direct host exposure of `wg-ui` TCP port is disabled.

Tools routes are protected by two layers:

- network allow-list (`VPN_CIDR` / `VPN_DOCKER_CIDR`)
- Authelia two-factor authentication (required)

Protected tools endpoints:

- `/tools/`
- `/tools/db/`
- `/tools/minio/`
- `/tools/logs/`
- `/tools/wireguard/`

### WireGuard password

Login password in `wg-easy` is configured by `WG_PASSWORD_HASH`.

Generate bcrypt hash:

```bash
docker run --rm ghcr.io/wg-easy/wg-easy:latest \
  node -e 'const b=require("bcryptjs"); console.log(b.hashSync("your_password",10));'
```

Put result into `.env` as `WG_PASSWORD_HASH=...` and escape `$` as `$$`.

### Authelia configuration

Configure Authelia secrets in `.env`:

- `EDGE_AUTHELIA_SESSION_DOMAIN`
- `EDGE_AUTHELIA_SESSION_SECRET`
- `EDGE_AUTHELIA_STORAGE_ENCRYPTION_KEY`
- `EDGE_AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET`

Configure Authelia admin user in `.env` (no manual YAML edit needed):

- `EDGE_AUTHELIA_ADMIN_USERNAME`
- `EDGE_AUTHELIA_ADMIN_DISPLAYNAME`
- `EDGE_AUTHELIA_ADMIN_EMAIL`
- `EDGE_AUTHELIA_ADMIN_PASSWORD_HASH` or `EDGE_AUTHELIA_ADMIN_PASSWORD`

Hash is preferred. Generate Argon2id hash:

```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'your_strong_password'
```

Put the generated digest into `.env` as `EDGE_AUTHELIA_ADMIN_PASSWORD_HASH=...`. If the hash contains `$`, escape each `$` as `$$` in `.env`.

Multi-account mode:

- Set `EDGE_AUTHELIA_USERS=admin,devops,...`
- For each user `name` define:
  - `EDGE_AUTHELIA_USER_<NAME>_EMAIL`
  - `EDGE_AUTHELIA_USER_<NAME>_DISPLAYNAME` (optional; default = username)
  - `EDGE_AUTHELIA_USER_<NAME>_PASSWORD_HASH` or `EDGE_AUTHELIA_USER_<NAME>_PASSWORD`

`<NAME>` is uppercase username with non-alphanumeric chars replaced by `_`.

### First 2FA enrollment

1. Open `https://<server-host>/tools/wireguard/`.
2. Login with your Authelia user.
3. Follow the prompt to register a TOTP app (Aegis/Authy/Google Authenticator).
4. After TOTP is enrolled, access to tools requires password + TOTP code.

## Nginx logging

- JSON access logs: `nginx_logs` volume -> `/var/log/nginx/access.log`
- Error logs: `nginx_logs` volume -> `/var/log/nginx/error.log`

Follow logs:

```bash
docker compose --env-file .env logs -f nginx
```

## Troubleshooting

- If a host port is busy, change it in `.env` (for example `VALKEY_PORT=6380`).
- `postgres/init` scripts run only on first DB initialization for a fresh volume.
- PostgreSQL web UI path is always `/tools/db/`, but container is selected by profile (`admin-pgweb` or `admin-pgadmin`).

## Notes

- Use only one compose file (`docker-compose.yml`) to avoid config drift.
- Keep user-facing labels/messages in `strings/` and avoid hardcoded text in edge scripts/templates.

## License

<a href="./LICENSE">
  <img src=".github/assets/mit-badge.png" width="70" alt="MIT License">
</a>


## Author

[Ernela](https://github.com/Ernous) - Developer;
[D7TUN6](https://github.com/D7TUN6) - Idea, Developer