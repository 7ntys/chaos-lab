#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-004"
SCENARIO_NAME="Backend to DB traffic blocked"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="network"
SCENARIO_DESCRIPTION="Injects an iptables DROP rule in DOCKER-USER for db:5432."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"
STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
STATE_FILE="${STATE_DIR}/state.env"

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

  if ! iptables -L DOCKER-USER >/dev/null 2>&1; then
    echo "DOCKER-USER chain not found. Ensure Docker is running." >&2
    exit 1
  fi

  local db_container_id
  local db_ip
  db_container_id="$(docker compose -f "${COMPOSE_FILE}" ps -q db)"
  if [[ -z "${db_container_id}" ]]; then
    echo "Could not determine db container id." >&2
    exit 1
  fi

  db_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${db_container_id}")"
  if [[ -z "${db_ip}" ]]; then
    echo "Could not determine db container IP." >&2
    exit 1
  fi

  cat > "${STATE_FILE}" <<EOF
DB_IP=${db_ip}
EOF

  if ! iptables -C DOCKER-USER -d "${db_ip}" -p tcp --dport 5432 -m comment --comment "${SCENARIO_ID}" -j DROP 2>/dev/null; then
    iptables -I DOCKER-USER 1 -d "${db_ip}" -p tcp --dport 5432 -m comment --comment "${SCENARIO_ID}" -j DROP
  fi
}

heal() {
  if iptables -S DOCKER-USER 2>/dev/null | grep -Fq "${SCENARIO_ID}"; then
    while IFS= read -r rule; do
      delete_rule="${rule/-A /-D }"
      # shellcheck disable=SC2086
      iptables ${delete_rule}
    done < <(iptables -S DOCKER-USER | grep "${SCENARIO_ID}")
  fi

  rm -f "${STATE_FILE}"
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

