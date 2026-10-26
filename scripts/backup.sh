#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

mkdir -p backups
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
target="/backups/tastymap-${timestamp}.db"
host_target="backups/tastymap-${timestamp}.db"

docker compose exec -T pocketbase \
  sqlite3 /pb_data/data.db ".backup '${target}'"

test -s "$host_target"
find backups -type f -name 'tastymap-*.db' -mtime +14 -delete

printf 'Backup created: %s\n' "$host_target"
