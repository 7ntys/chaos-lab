#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-001"
SCENARIO_NAME="Backend container stopped"
SCENARIO_DIFFICULTY="easy"
SCENARIO_LAYER="app"
SCENARIO_DESCRIPTION="Stops the Go backend container, frontend still serves but API fails."

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
  docker compose -f "${COMPOSE_FILE}" stop backend
}

heal() {
  docker compose -f "${COMPOSE_FILE}" start backend
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
