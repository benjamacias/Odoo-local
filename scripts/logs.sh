#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$PROJECT_DIR"

FOLLOW=1
if [ "${1:-}" = "--no-follow" ]; then
  FOLLOW=0
  shift
fi

if [ "$#" -eq 0 ]; then
  set -- odoo
fi

if [ "$FOLLOW" -eq 1 ]; then
  docker compose logs -f "$@"
else
  docker compose logs "$@"
fi
