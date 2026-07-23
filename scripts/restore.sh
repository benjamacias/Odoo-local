#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$PROJECT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "No se encontro $ENV_FILE. Crea uno con: cp .env.example .env" >&2
  exit 1
fi

case "$ENV_FILE" in
  /*) ENV_PATH="$ENV_FILE" ;;
  *) ENV_PATH="./$ENV_FILE" ;;
esac

set -a
. "$ENV_PATH"
set +a

BACKUP_FILE="${1:-}"
DB_NAME="${2:-${ODOO_DB:-}}"

if [ -z "$BACKUP_FILE" ] || [ -z "$DB_NAME" ]; then
  echo "Uso: $0 <archivo_backup.sql> [nombre_base_odoo]" >&2
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "No existe el archivo de backup: $BACKUP_FILE" >&2
  exit 1
fi

docker compose stop odoo

docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db \
  dropdb -h localhost -U "${POSTGRES_USER}" --if-exists "$DB_NAME"

docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db \
  createdb -h localhost -U "${POSTGRES_USER}" "$DB_NAME"

docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db \
  psql -h localhost -U "${POSTGRES_USER}" "$DB_NAME" < "$BACKUP_FILE"

docker compose up -d odoo

echo "Restore completado en la base: $DB_NAME"
