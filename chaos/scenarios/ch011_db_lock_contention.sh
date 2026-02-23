#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-011"
SCENARIO_NAME="Postgres table lock contention"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="db"
SCENARIO_DESCRIPTION="Holds an ACCESS EXCLUSIVE lock on menu_items to trigger API latency and timeouts."

COMPOSE_FILE="${COMPOSE_FILE:-/opt/chaos-cafe/docker-compose.yml}"
LOCK_SECONDS="${LOCK_SECONDS:-900}"
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

  if [[ -f "${STATE_FILE}" ]]; then
    local locker_pid
    locker_pid="$(read_state_value "LOCKER_PID" || true)"
    if [[ -n "${locker_pid}" ]] && kill -0 "${locker_pid}" 2>/dev/null; then
      echo "${SCENARIO_ID} already injected."
      exit 0
    fi
    rm -f "${STATE_FILE}"
  fi

  docker compose -f "${COMPOSE_FILE}" exec -T db \
    psql -U cafe -d cafe -v ON_ERROR_STOP=1 \
    -c "BEGIN; LOCK TABLE menu_items IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(${LOCK_SECONDS});" \
    >/dev/null 2>&1 &
  local locker_pid="$!"

  sleep 1
  if ! kill -0 "${locker_pid}" 2>/dev/null; then
    echo "Failed to start lock session on Postgres." >&2
    exit 1
  fi

  cat > "${STATE_FILE}" <<EOF
LOCKER_PID=${locker_pid}
LOCK_SECONDS=${LOCK_SECONDS}
EOF
}

heal() {
  local locker_pid
  locker_pid="$(read_state_value "LOCKER_PID" || true)"

  if [[ -n "${locker_pid}" ]]; then
    kill "${locker_pid}" 2>/dev/null || true
  fi

  docker compose -f "${COMPOSE_FILE}" exec -T db \
    psql -U cafe -d cafe -Atc \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='cafe' AND query LIKE '%LOCK TABLE menu_items IN ACCESS EXCLUSIVE MODE%' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true

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

