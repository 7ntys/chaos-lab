#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-015"
SCENARIO_NAME="Backend file descriptor exhaustion"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="os"
SCENARIO_DESCRIPTION="Lowers backend process nofile limit to trigger EMFILE and intermittent failures."

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

get_backend_host_pid() {
  local container_id
  container_id="$(docker compose -f "${COMPOSE_FILE}" ps -q backend)"
  if [[ -z "${container_id}" ]]; then
    echo ""
    return 1
  fi

  docker inspect -f '{{.State.Pid}}' "${container_id}"
}

read_state_value() {
  local key="$1"
  local line

  [[ -f "${STATE_FILE}" ]] || return 1
  line="$(grep -E "^${key}=" "${STATE_FILE}" | head -n1 || true)"
  [[ -n "${line}" ]] || return 1
  echo "${line#*=}"
}

inject() {
  mkdir -p "${STATE_DIR}"

  if ! command -v prlimit >/dev/null 2>&1; then
    echo "prlimit command not found (install util-linux)." >&2
    exit 1
  fi

  local backend_pid
  backend_pid="$(get_backend_host_pid || true)"
  if [[ -z "${backend_pid}" || "${backend_pid}" == "0" ]]; then
    echo "Could not determine backend process PID." >&2
    exit 1
  fi

  if [[ -f "${STATE_FILE}" ]]; then
    local current_soft
    current_soft="$(awk '/Max open files/ {print $4}' "/proc/${backend_pid}/limits")"
    if [[ "${current_soft}" == "64" ]]; then
      echo "${SCENARIO_ID} already injected."
      exit 0
    fi
    rm -f "${STATE_FILE}"
  fi

  local old_soft
  local old_hard
  old_soft="$(awk '/Max open files/ {print $4}' "/proc/${backend_pid}/limits")"
  old_hard="$(awk '/Max open files/ {print $5}' "/proc/${backend_pid}/limits")"

  if [[ -z "${old_soft}" || -z "${old_hard}" ]]; then
    echo "Could not read current nofile limits for PID ${backend_pid}." >&2
    exit 1
  fi

  cat > "${STATE_FILE}" <<EOF
BACKEND_PID=${backend_pid}
OLD_SOFT=${old_soft}
OLD_HARD=${old_hard}
EOF

  prlimit --pid "${backend_pid}" --nofile=64:64
}

heal() {
  local old_soft
  local old_hard
  local backend_pid

  old_soft="$(read_state_value "OLD_SOFT" || true)"
  old_hard="$(read_state_value "OLD_HARD" || true)"

  if [[ -z "${old_soft}" ]]; then
    old_soft="1048576"
  fi
  if [[ -z "${old_hard}" ]]; then
    old_hard="${old_soft}"
  fi

  backend_pid="$(get_backend_host_pid || true)"
  if [[ -n "${backend_pid}" && "${backend_pid}" != "0" ]]; then
    prlimit --pid "${backend_pid}" --nofile="${old_soft}:${old_hard}" || true
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
