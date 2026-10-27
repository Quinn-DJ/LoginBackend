# TastyMap LoginBackend

Self-hosted authentication and store-sync backend for TastyMap.

The service runs PocketBase behind Caddy. PocketBase owns login tokens and the
`places` collection; Caddy terminates HTTPS and exposes only `/api/*`.

## Repository Layout

```text
.
├── Caddyfile
├── Dockerfile
├── compose.yaml
├── docs/API.md
├── pb_migrations/
├── pb_hooks/
└── scripts/
```

## Requirements

- Linux server with Docker Engine and the Docker Compose plugin.
- A DNS record pointing the chosen API hostname to the server.
- Inbound TCP 80 available for certificate issuance and HTTP-to-HTTPS redirect.
- Inbound TCP 8443 available for HTTPS API traffic.
- A 32-character random value for PocketBase settings encryption.

No Apple Developer Program membership is required for this backend.

## First Deployment

1. Copy the environment template and set the production values:

   ```bash
   cp .env.example .env
   openssl rand -hex 16
   ```

   Put the generated key in `PB_ENCRYPTION_KEY` and the real hostname in
   `TASTYMAP_DOMAIN`. Keep `TASTYMAP_HTTPS_PORT=8443` unless port 443 is free
   and the Compose port mapping is changed.

2. Create writable data directories. PocketBase runs as UID/GID `10001`.

   ```bash
   mkdir -p data backups
   sudo chown -R 10001:10001 data backups
   ```

3. Build and start the services:

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

4. Verify HTTPS and the health endpoint:

   ```bash
   curl --fail "https://${TASTYMAP_DOMAIN}:${TASTYMAP_HTTPS_PORT}/api/health"
   ```

   Caddy only exposes `/api/*`. The PocketBase admin UI is bound to
   `127.0.0.1:8090` on the server and must be used through an SSH tunnel:

   ```bash
   ssh -L 8090:127.0.0.1:8090 user@your-server
   ```

   Then open `http://127.0.0.1:8090/_/` locally.

5. Create a PocketBase superuser:

   ```bash
   read -r -s -p "PocketBase admin password: " ADMIN_PASSWORD
   printf '\n'
   docker compose exec pocketbase \
     pocketbase superuser upsert admin@example.com "$ADMIN_PASSWORD" \
     --dir=/pb_data --encryptionEnv=PB_ENCRYPTION_KEY
   unset ADMIN_PASSWORD
   ```

6. Create the TastyMap app account. Run this on a trusted workstation:

   ```bash
   read -r -s -p "PocketBase admin password: " PB_ADMIN_PASSWORD
   printf '\n'
   read -r -s -p "TastyMap user password: " USER_PASSWORD
   printf '\n'
   BASE_URL="https://${TASTYMAP_DOMAIN}:${TASTYMAP_HTTPS_PORT}" \
   PB_ADMIN_EMAIL="admin@example.com" \
   PB_ADMIN_PASSWORD="$PB_ADMIN_PASSWORD" \
   USER_EMAIL="you@example.com" \
   USER_PASSWORD="$USER_PASSWORD" \
   USER_NAME="Your Name" \
   ./scripts/create-user.sh
   unset PB_ADMIN_PASSWORD USER_PASSWORD
   ```

   Public account creation remains disabled. New users must be provisioned by
   an administrator.

## Local API Tests

The integration test uses a temporary PocketBase data directory and does not
touch production data.

```bash
chmod +x scripts/test-api.sh
POCKETBASE_BIN=/private/tmp/tastymap-pocketbase-0.40.6/pocketbase \
  ./scripts/test-api.sh
```

The test verifies login, record ownership, anonymous rejection, soft deletion,
and the disabled hard-delete rule.

## Backups

Create a live SQLite backup:

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

Backups are written to `backups/` and retained for 14 days. Copy them to a
separate machine or object store. A backup stored only on the same server does
not protect against disk or server loss.

To restore:

1. Stop PocketBase:

   ```bash
   docker compose stop pocketbase
   ```

2. Move the current database aside and copy the selected backup to
   `data/data.db`.
3. Remove stale `data/data.db-wal` and `data/data.db-shm` files.
4. Set ownership back to UID/GID `10001`.
5. Start PocketBase and verify `/api/health`, login, and a known place record.

## Security Boundaries

- Caddy is the only service exposed publicly.
- PocketBase is bound to server loopback and an internal Docker network.
- Public registration and hard deletion are disabled.
- Every place is protected by an owner relation and API rules.
- Tokens and user passwords are handled by PocketBase; plaintext passwords are
  never stored by this repository.
- The PocketBase admin UI is not proxied publicly.

Keep backups encrypted when they leave the server. Rotate the admin password
and `PB_ENCRYPTION_KEY` only through a documented restore procedure, because the
encryption key is required to decrypt PocketBase settings.
