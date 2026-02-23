#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-002"
SCENARIO_NAME="Postgres container stopped"
SCENARIO_DIFFICULTY="easy"
SCENARIO_LAYER="db"
SCENARIO_DESCRIPTION="Stops Postgres so backend starts returning database errors."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"

meta() {
  cat <<EOF
id=${SCENARIO_ID}
name=${SCENARIO_NAME}
difficulty=${SCENARIO_DIFFICULTY}
layer=${SCENARIO_LAYER}
description=${SCENARIO_DESCRIPTION}
EOF
}

inject() {
  docker compose -f "${COMPOSE_FILE}" stop db
}

heal() {
  docker compose -f "${COMPOSE_FILE}" start db
}

case "${1:-}" in
  inject) inject ;;
  heal) heal ;;
  meta) meta ;;
  *)
    echo "Usage: $0 {inject|heal|meta}" >&2
    exit 1
    ;;
esac

