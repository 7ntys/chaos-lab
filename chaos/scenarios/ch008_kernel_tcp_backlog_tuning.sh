#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-008"
SCENARIO_NAME="Kernel TCP backlog reduced"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="kernel"
SCENARIO_DESCRIPTION="Lowers somaxconn and tcp_max_syn_backlog, causing degraded connection handling under load."

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

  local old_somaxconn
  local old_syn_backlog
  old_somaxconn="$(sysctl -n net.core.somaxconn)"
  old_syn_backlog="$(sysctl -n net.ipv4.tcp_max_syn_backlog)"

  cat > "${STATE_FILE}" <<EOF
OLD_SOMAXCONN=${old_somaxconn}
OLD_SYN_BACKLOG=${old_syn_backlog}
EOF

  sysctl -w net.core.somaxconn=16 >/dev/null
  sysctl -w net.ipv4.tcp_max_syn_backlog=32 >/dev/null
}

heal() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "No state file found for ${SCENARIO_ID}, cannot safely restore." >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  sysctl -w "net.core.somaxconn=${OLD_SOMAXCONN}" >/dev/null
  sysctl -w "net.ipv4.tcp_max_syn_backlog=${OLD_SYN_BACKLOG}" >/dev/null
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

