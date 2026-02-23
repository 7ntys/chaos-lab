#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-009"
SCENARIO_NAME="Kernel netem latency and packet loss"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="kernel"
SCENARIO_DESCRIPTION="Adds tc netem on docker0 to degrade container-to-container traffic."

STATE_DIR="/var/lib/chaos-lab/${SCENARIO_ID}"
STATE_FILE="${STATE_DIR}/state.env"
IFACE="${CHAOS_IFACE:-docker0}"

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

  if ! command -v tc >/dev/null 2>&1; then
    echo "tc command not found (install iproute2)." >&2
    exit 1
  fi

  if ! ip link show "${IFACE}" >/dev/null 2>&1; then
    echo "Interface ${IFACE} not found." >&2
    exit 1
  fi

  tc qdisc replace dev "${IFACE}" root netem delay 200ms 40ms loss 8%

  cat > "${STATE_FILE}" <<EOF
IFACE=${IFACE}
EOF
}

heal() {
  local iface
  iface="${IFACE}"
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    iface="${IFACE}"
  fi

  if ip link show "${iface}" >/dev/null 2>&1; then
    tc qdisc del dev "${iface}" root 2>/dev/null || true
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

