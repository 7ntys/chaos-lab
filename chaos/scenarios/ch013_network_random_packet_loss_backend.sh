#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-013"
SCENARIO_NAME="Random packet loss to backend"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="network"
SCENARIO_DESCRIPTION="Adds iptables random DROP rules for backend:8080 to create intermittent API failures."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"
STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
STATE_FILE="${STATE_DIR}/state.env"
LOSS_PROBABILITY="${LOSS_PROBABILITY:-0.30}"

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

  local backend_container_id
  local backend_ip
  backend_container_id="$(docker compose -f "${COMPOSE_FILE}" ps -q backend)"
  if [[ -z "${backend_container_id}" ]]; then
    echo "Could not determine backend container id." >&2
    exit 1
  fi

  backend_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${backend_container_id}")"
  if [[ -z "${backend_ip}" ]]; then
    echo "Could not determine backend container IP." >&2
    exit 1
  fi

  cat > "${STATE_FILE}" <<EOF
BACKEND_IP=${backend_ip}
LOSS_PROBABILITY=${LOSS_PROBABILITY}
EOF

  if ! iptables -C DOCKER-USER -d "${backend_ip}" -p tcp --dport 8080 \
    -m statistic --mode random --probability "${LOSS_PROBABILITY}" \
    -m comment --comment "${SCENARIO_ID}" -j DROP 2>/dev/null; then
    iptables -I DOCKER-USER 1 -d "${backend_ip}" -p tcp --dport 8080 \
      -m statistic --mode random --probability "${LOSS_PROBABILITY}" \
      -m comment --comment "${SCENARIO_ID}" -j DROP
  fi
}

heal() {
  if iptables -S DOCKER-USER 2>/dev/null | grep -Fq "${SCENARIO_ID}"; then
    while IFS= read -r rule; do
      local delete_rule
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

