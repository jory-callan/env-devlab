# stacks — Local Development Service Stacks

Docker Compose service stacks for local development. One directory per
stack, English comments, credentials in each stack's `.env` (tracked in
git), all images version-pinned.

## Conventions

- Every stack has a `.env` with `ROOT_DIR` as the bind-mount root path
  (`ROOT_DIR=.` keeps data inside the stack dir).
- All stacks join the external bridge network `net-shared` so containers
  resolve each other by name. Create it once per host:

  ```bash
  bash stacks/create-network.sh
  ```

- Passwords are read from `.env` as `${VAR}` with `Admin123` fallback.

## Stacks

| Stack | Image | Ports | Notes |
|---|---|---|---|
| mysql-5.7 | mysql:5.7 | 3306 | legacy |
| mysql-8.4 | mysql:8.4 | 3306 | LTS |
| postgresql-15 | postgres:15.5-alpine3.17 | 5432 | `conf/postgresql.conf` is a reference profile, not mounted |
| redis | redis:6.2-alpine | 6378 | |
| valkey | valkey/valkey:9.1.2-alpine | host mode | |
| dragonflydb | dragonflydb/dragonfly:v1.40.1 | 6377 | |
| minio | quay.io/minio/aistor/minio:RELEASE.2026-09-19T17-05-25Z | 9000 console, 9001 S3 | community image was withdrawn; this is MinIO's official successor |
| nginx | nginx:1.28.0 | 80, 443 | `anotherconfig/` is an alternative config set, not mounted |
| acme.sh | neilpang/acme.sh:3.1.6 | host mode | |
| questdb | questdb/questdb:9.4.0 | 8812, 9000, 9003, 9009 | |
| mirrorproxy | kudang/mirrorproxy:1.4.2 | 3000 | |
| monitor | VictoriaLogs + Fluent Bit + Grafana + VictoriaMetrics | 9428, 8428, 2020, 3000 | see `monitor/README.md` |

Some stacks share host ports by design (e.g. both MySQL versions map
3306); run only one at a time or edit the mapping.

## Quick start

```bash
bash stacks/create-network.sh          # once per host
cd stacks/mysql-8.4 && docker compose up -d
cd stacks/monitor && bash tools/start-all.sh
```
