#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-007"
SCENARIO_NAME="DNS blackhole"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="network"
SCENARIO_DESCRIPTION="Blocks DNS (TCP/UDP 53) for host and containers with iptables."

meta() {
  cat <<EOF
id=${SCENARIO_ID}
name=${SCENARIO_NAME}
difficulty=${SCENARIO_DIFFICULTY}
layer=${SCENARIO_LAYER}
description=${SCENARIO_DESCRIPTION}
EOF
}

add_rule_if_missing() {
  local chain="$1"
  local proto="$2"
  if ! iptables -C "${chain}" -p "${proto}" --dport 53 -m comment --comment "${SCENARIO_ID}" -j REJECT 2>/dev/null; then
    iptables -I "${chain}" 1 -p "${proto}" --dport 53 -m comment --comment "${SCENARIO_ID}" -j REJECT
  fi
}

delete_rules_for_chain() {
  local chain="$1"
  if iptables -S "${chain}" 2>/dev/null | grep -Fq "${SCENARIO_ID}"; then
    while IFS= read -r rule; do
      delete_rule="${rule/-A /-D }"
      # shellcheck disable=SC2086
      iptables ${delete_rule}
    done < <(iptables -S "${chain}" | grep "${SCENARIO_ID}")
  fi
}

inject() {
  add_rule_if_missing OUTPUT udp
  add_rule_if_missing OUTPUT tcp
  add_rule_if_missing FORWARD udp
  add_rule_if_missing FORWARD tcp
}

heal() {
  delete_rules_for_chain OUTPUT
  delete_rules_for_chain FORWARD
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

