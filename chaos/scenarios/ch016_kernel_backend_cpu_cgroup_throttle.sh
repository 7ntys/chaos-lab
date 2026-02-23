#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="CH-016"
SCENARIO_NAME="Backend CPU cgroup throttling"
SCENARIO_DIFFICULTY="hard"
SCENARIO_LAYER="kernel"
SCENARIO_DESCRIPTION="Applies strict cgroup CPU quota on backend container to trigger latency under load."

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

read_state_value() {
  local key="$1"
  local line

  [[ -f "${STATE_FILE}" ]] || return 1
  line="$(grep -E "^${key}=" "${STATE_FILE}" | head -n1 || true)"
  [[ -n "${line}" ]] || return 1
  echo "${line#*=}"
}

get_backend_container_id() {
  docker compose -f "${COMPOSE_FILE}" ps -q backend
}

inject() {
  mkdir -p "${STATE_DIR}"

  local container_id
  container_id="$(get_backend_container_id)"
  if [[ -z "${container_id}" ]]; then
    echo "Could not determine backend container id." >&2
    exit 1
  fi

  if [[ -f "${STATE_FILE}" ]]; then
    local current_cpu_period
    local current_cpu_quota
    current_cpu_period="$(docker inspect -f '{{.HostConfig.CpuPeriod}}' "${container_id}")"
    current_cpu_quota="$(docker inspect -f '{{.HostConfig.CpuQuota}}' "${container_id}")"
    if [[ "${current_cpu_period}" == "100000" && "${current_cpu_quota}" == "20000" ]]; then
      echo "${SCENARIO_ID} already injected."
      exit 0
    fi
    rm -f "${STATE_FILE}"
  fi

  local old_cpu_period
  local old_cpu_quota
  old_cpu_period="$(docker inspect -f '{{.HostConfig.CpuPeriod}}' "${container_id}")"
  old_cpu_quota="$(docker inspect -f '{{.HostConfig.CpuQuota}}' "${container_id}")"

  cat > "${STATE_FILE}" <<EOF
OLD_CPU_PERIOD=${old_cpu_period}
OLD_CPU_QUOTA=${old_cpu_quota}
EOF

  docker update --cpu-period 100000 --cpu-quota 20000 "${container_id}" >/dev/null
}

heal() {
  local container_id
  local old_cpu_period
  local old_cpu_quota

  container_id="$(get_backend_container_id || true)"
  if [[ -z "${container_id}" ]]; then
    rm -f "${STATE_FILE}"
    exit 0
  fi

  old_cpu_period="$(read_state_value "OLD_CPU_PERIOD" || true)"
  old_cpu_quota="$(read_state_value "OLD_CPU_QUOTA" || true)"

  if [[ -z "${old_cpu_period}" ]]; then
    old_cpu_period="0"
  fi
  if [[ -z "${old_cpu_quota}" ]]; then
    old_cpu_quota="0"
  fi

  if [[ "${old_cpu_quota}" == "0" ]]; then
    docker update --cpu-quota 0 "${container_id}" >/dev/null || true
  else
    if [[ -z "${old_cpu_period}" || "${old_cpu_period}" == "0" ]]; then
      old_cpu_period="100000"
    fi
    docker update --cpu-period "${old_cpu_period}" --cpu-quota "${old_cpu_quota}" "${container_id}" >/dev/null || true
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
