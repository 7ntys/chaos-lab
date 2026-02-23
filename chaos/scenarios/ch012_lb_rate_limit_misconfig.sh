#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-012"
SCENARIO_NAME="Load balancer rate-limit misconfiguration"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="lb"
SCENARIO_DESCRIPTION="Injects a strict limit_req on /api to create intermittent 503 under normal bursts."

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

  local tmp_with_zone
  local tmp_final
  tmp_with_zone="$(mktemp)"
  tmp_final="$(mktemp)"

  awk 'NR==1{print "limit_req_zone $binary_remote_addr zone=chaos_api_limit:10m rate=1r/s;"} {print}' \
    "${NGINX_CONF}" > "${tmp_with_zone}"

  awk '
    { print }
    $0 ~ /location \/api\/ \{/ {
      print "    limit_req zone=chaos_api_limit burst=1 nodelay;"
      print "    add_header X-Chaos-Scenario \"CH-012\" always;"
    }
  ' "${tmp_with_zone}" > "${tmp_final}"

  mv "${tmp_final}" "${NGINX_CONF}"
  rm -f "${tmp_with_zone}"

  if ! grep -Fq "chaos_api_limit" "${NGINX_CONF}"; then
    cp "${BACKUP_FILE}" "${NGINX_CONF}"
    echo "Failed to inject Nginx rate limit misconfiguration." >&2
    exit 1
  fi

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps lb
  touch "${FLAG_FILE}"
}

heal() {
  if [[ -f "${BACKUP_FILE}" ]]; then
    cp "${BACKUP_FILE}" "${NGINX_CONF}"
  fi

  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps lb
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

