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

- `/api/private/*` -> `${BACKEND_UPSTREAM}`
- `/api/public/*` -> `${BACKEND_UPSTREAM}`
- `/ws/*` -> `${BACKEND_UPSTREAM}`
- `/` -> `${APP_UPSTREAM}`
- `/site/` -> `${SITE_UPSTREAM}`
- `/tools/minio/` -> MinIO Console (VPN only)
- `/tools/db/` -> PostgreSQL admin UI (VPN only)
- `/tools/logs/` -> Logs UI (VPN only)
- `/tools/wireguard/` -> WireGuard UI (VPN only + 2FA)
- `/healthz` -> static 200 `ok`

Headers:

- `X-Client-Locale` is derived from `Accept-Language` (fallback `EDGE_DEFAULT_LOCALE`).

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

### Connect external backend and app to edge

1. Start edge core:

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

[![MIT](.github/assets/mit-badge.png)](./LICENSE)

## Author

[Ernela](https://github.com/Ernous) - Developer;
[D7TUN6](https://github.com/D7TUN6) - Idea, Developer