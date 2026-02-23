#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-014"
SCENARIO_NAME="I/O saturation on /var/tmp"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="os"
SCENARIO_DESCRIPTION="Runs synchronous write loops to increase iowait and degrade app responsiveness."

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

read_state_pids() {
  local key
  local value
  local pid

  [[ -f "${STATE_FILE}" ]] || return 0

  while IFS='=' read -r key value; do
    case "${key}" in
      PID)
        [[ -n "${value}" ]] && echo "${value}"
        ;;
      PIDS)
        for pid in ${value}; do
          [[ -n "${pid}" ]] && echo "${pid}"
        done
        ;;
    esac
  done < "${STATE_FILE}"
}

inject() {
  mkdir -p "${STATE_DIR}"

  if [[ -f "${STATE_FILE}" ]]; then
    local existing_pid
    while IFS= read -r existing_pid; do
      if kill -0 "${existing_pid}" 2>/dev/null; then
        echo "${SCENARIO_ID} already injected."
        exit 0
      fi
    done < <(read_state_pids)
    rm -f "${STATE_FILE}"
  fi

  local cores
  local workers
  local i
  local worker_file
  local pids=()

  cores="$(nproc 2>/dev/null || echo 2)"
  workers=$(( cores / 2 ))
  if (( workers < 1 )); then
    workers=1
  fi
  if (( workers > 3 )); then
    workers=3
  fi

  for i in $(seq 1 "${workers}"); do
    worker_file="/var/tmp/chaos-${SCENARIO_ID}-${i}.dat"
    bash -c "while :; do dd if=/dev/zero of='${worker_file}' bs=4M count=32 oflag=dsync status=none; sync; rm -f '${worker_file}'; done" \
      >/dev/null 2>&1 &
    pids+=( "$!" )
  done

  {
    for pid in "${pids[@]}"; do
      echo "PID=${pid}"
    done
    echo "WORKERS=${workers}"
  } > "${STATE_FILE}"
}

heal() {
  if [[ -f "${STATE_FILE}" ]]; then
    while IFS= read -r pid; do
      kill "${pid}" 2>/dev/null || true
    done < <(read_state_pids)
  fi

  rm -f /var/tmp/chaos-"${SCENARIO_ID}"-*.dat
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

