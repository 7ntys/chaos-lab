#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-010"
SCENARIO_NAME="Backend DB DSN misconfiguration"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="app"
SCENARIO_DESCRIPTION="Introduces config drift in backend DSN so API cannot connect to Postgres."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"
STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
BACKUP_FILE="${STATE_DIR}/docker-compose.yml.bak"
FLAG_FILE="${STATE_DIR}/active"

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
  mkdir -p "${STATE_DIR}"

  if [[ -f "${FLAG_FILE}" ]]; then
    echo "${SCENARIO_ID} already injected."
    exit 0
  fi

  cp "${COMPOSE_FILE}" "${BACKUP_FILE}"
  sed -i.bak 's|@db:5432/|@db:15432/|g' "${COMPOSE_FILE}"
  rm -f "${COMPOSE_FILE}.bak"

  if ! grep -Fq "@db:15432/" "${COMPOSE_FILE}"; then
    cp "${BACKUP_FILE}" "${COMPOSE_FILE}"
    echo "Failed to inject DSN drift." >&2
    exit 1
  fi

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps backend
  touch "${FLAG_FILE}"
}

heal() {
  if [[ -f "${BACKUP_FILE}" ]]; then
    cp "${BACKUP_FILE}" "${COMPOSE_FILE}"
  fi

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps backend
  rm -f "${FLAG_FILE}" "${BACKUP_FILE}"
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
