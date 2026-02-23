#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-005"
SCENARIO_NAME="Disk pressure in /var/tmp"
SCENARIO_DIFFICULTY="medium"
SCENARIO_LAYER="os"
SCENARIO_DESCRIPTION="Creates a large file to reduce free disk space and trigger write failures."

STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
STATE_FILE="${STATE_DIR}/state.env"
TARGET_FILE="/var/tmp/chaos-${SCENARIO_ID}.fill"

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

  if [[ -f "${TARGET_FILE}" ]]; then
    echo "${SCENARIO_ID} already injected."
    exit 0
  fi

  local free_mb
  local fill_mb
  free_mb="$(df -Pm /var/tmp | awk 'NR==2 {print $4}')"
  if [[ -z "${free_mb}" || "${free_mb}" -lt 768 ]]; then
    echo "Not enough free disk space for safe injection." >&2
    exit 1
  fi

  fill_mb=$(( free_mb / 3 ))
  if (( fill_mb < 256 )); then
    fill_mb=256
  fi
  if (( fill_mb > 2048 )); then
    fill_mb=2048
  fi

  if ! fallocate -l "${fill_mb}M" "${TARGET_FILE}" 2>/dev/null; then
    dd if=/dev/zero of="${TARGET_FILE}" bs=1M count="${fill_mb}" status=none
  fi

  cat > "${STATE_FILE}" <<EOF
TARGET_FILE=${TARGET_FILE}
SIZE_MB=${fill_mb}
EOF
}

heal() {
  if [[ -f "${TARGET_FILE}" ]]; then
    rm -f "${TARGET_FILE}"
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

