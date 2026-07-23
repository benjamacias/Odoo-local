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

DB_NAME="${1:-${ODOO_DB:-}}"
if [ -z "$DB_NAME" ]; then
  echo "Uso: $0 <nombre_base_odoo>" >&2
  exit 1
fi

mkdir -p backups
STAMP=$(date +"%Y%m%d-%H%M%S")
OUT_FILE="backups/${DB_NAME}-${STAMP}.sql"
TMP_FILE="${OUT_FILE}.tmp"
trap 'rm -f "$TMP_FILE"' EXIT

docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db \
  pg_dump -h localhost -U "${POSTGRES_USER}" "$DB_NAME" > "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
trap - EXIT

echo "Backup creado: $OUT_FILE"
