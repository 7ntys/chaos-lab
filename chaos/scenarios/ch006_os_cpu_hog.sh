#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-006"
SCENARIO_NAME="CPU saturation with busy loops"
SCENARIO_DIFFICULTY="easy"
SCENARIO_LAYER="os"
SCENARIO_DESCRIPTION="Launches multiple CPU hog loops to increase load and latency."

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

  if [[ -f "${STATE_FILE}" ]]; then
    echo "${SCENARIO_ID} already injected."
    exit 0
  fi

  local cores
  local workers
  local pids=()
  cores="$(nproc 2>/dev/null || echo 2)"
  workers=$(( cores / 2 ))

  if (( workers < 2 )); then
    workers=2
  fi
  if (( workers > 6 )); then
    workers=6
  fi

  for _ in $(seq 1 "${workers}"); do
    bash -c 'while :; do :; done' >/dev/null 2>&1 &
    pids+=( "$!" )
  done

  {
    for pid in "${pids[@]}"; do
      echo "PID=${pid}"
    done
    echo "WORKERS=${workers}"
  } > "${STATE_FILE}"
}

read_state_pids() {
  local key
  local value
  local pid

  if [[ ! -f "${STATE_FILE}" ]]; then
    return 0
  fi

  while IFS='=' read -r key value; do
    case "${key}" in
      PID)
        [[ -n "${value}" ]] && echo "${value}"
        ;;
      PIDS)
        # Backward compatibility with old state format: PIDS="1 2 3"
        for pid in ${value}; do
          [[ -n "${pid}" ]] && echo "${pid}"
        done
        ;;
    esac
  done < "${STATE_FILE}"
}

heal() {
  if [[ -f "${STATE_FILE}" ]]; then
    while IFS= read -r pid; do
      kill "${pid}" 2>/dev/null || true
    done < <(read_state_pids)
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
