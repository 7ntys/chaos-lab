#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-003"
SCENARIO_NAME="Load balancer bad upstream"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="lb"
SCENARIO_DESCRIPTION="Rewrites Nginx upstream port so /api and /healthz return 502."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"
NGINX_CONF="${NGINX_CONF:-/opt/chaos-cafe/lb/nginx.conf}"
STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
BACKUP_FILE="${STATE_DIR}/nginx.conf.bak"
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

  cp "${NGINX_CONF}" "${BACKUP_FILE}"
  sed -i.bak 's/backend:8080/backend:18080/g' "${NGINX_CONF}"
  rm -f "${NGINX_CONF}.bak"

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps lb
  touch "${FLAG_FILE}"
}

heal() {
  if [[ -f "${BACKUP_FILE}" ]]; then
    cp "${BACKUP_FILE}" "${NGINX_CONF}"
  fi

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps lb
  rm -f "${FLAG_FILE}"
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

