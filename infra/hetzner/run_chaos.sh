#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/hetzner/terraform"
CHAOS_DIR="${ROOT_DIR}/chaos"
SCENARIO_DIR="${CHAOS_DIR}/scenarios"
TICKET_TEMPLATE_DIR="${CHAOS_DIR}/tickets"
TICKET_DIR="${ROOT_DIR}/.chaos-tickets"

SSH_USER="${SSH_USER:-root}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_rsa}"
SSH_PORT="${SSH_PORT:-22}"
TARGET_HOST="${TARGET_HOST:-}"
REMOTE_CHAOS_DIR="${REMOTE_CHAOS_DIR:-/opt/chaos-lab}"

ACTION="${1:-run}"
ARG="${2:-}"

SCENARIO_ID=""
SCENARIO_NAME=""
SCENARIO_DIFFICULTY=""
SCENARIO_LAYER=""
SCENARIO_DESCRIPTION=""
USER_TICKET_TEMPLATE=""
USER_TICKET_FILE=""

usage() {
  cat <<EOF
Usage:
  $0 run [SCENARIO_ID]
  $0 list
  $0 heal [last|TICKET_ID]
  $0 heal-all

Examples:
  $0 run
  $0 run CH-004
  $0 list
  $0 heal last
  $0 heal-all
EOF
}

require_scenarios_dir() {
  if [[ ! -d "${SCENARIO_DIR}" ]]; then
    echo "Scenario directory not found: ${SCENARIO_DIR}" >&2
    exit 1
  fi
}

collect_scenarios() {
  require_scenarios_dir
  SCENARIO_FILES=()
  while IFS= read -r script; do
    SCENARIO_FILES+=( "${script}" )
  done < <(find "${SCENARIO_DIR}" -maxdepth 1 -type f -name '*.sh' | sort)

  if [[ "${#SCENARIO_FILES[@]}" -eq 0 ]]; then
    echo "No scenario scripts found in ${SCENARIO_DIR}" >&2
    exit 1
  fi
}

load_metadata() {
  local script="$1"
  SCENARIO_ID=""
  SCENARIO_NAME=""
  SCENARIO_DIFFICULTY=""
  SCENARIO_LAYER=""
  SCENARIO_DESCRIPTION=""

  while IFS='=' read -r key value; do
    case "${key}" in
      id) SCENARIO_ID="${value}" ;;
      name) SCENARIO_NAME="${value}" ;;
      difficulty) SCENARIO_DIFFICULTY="${value}" ;;
      layer) SCENARIO_LAYER="${value}" ;;
      description) SCENARIO_DESCRIPTION="${value}" ;;
    esac
  done < <(bash "${script}" meta)

  if [[ -z "${SCENARIO_ID}" || -z "${SCENARIO_NAME}" || -z "${SCENARIO_DIFFICULTY}" ]]; then
    echo "Invalid metadata in scenario: ${script}" >&2
    exit 1
  fi
}

select_scenario_script() {
  local requested_id="$1"
  local selected=""

  collect_scenarios
  if [[ -n "${requested_id}" ]]; then
    for script in "${SCENARIO_FILES[@]}"; do
      load_metadata "${script}"
      if [[ "${SCENARIO_ID}" == "${requested_id}" ]]; then
        selected="${script}"
        break
      fi
    done
  else
    selected="${SCENARIO_FILES[$((RANDOM % ${#SCENARIO_FILES[@]}))]}"
  fi

  if [[ -z "${selected}" ]]; then
    echo "Could not find scenario with ID '${requested_id}'." >&2
    exit 1
  fi

  echo "${selected}"
}

build_ssh_options() {
  SSH_OPTS=(
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
  )

  if [[ -n "${SSH_PRIVATE_KEY_PATH}" ]]; then
    if [[ ! -f "${SSH_PRIVATE_KEY_PATH}" ]]; then
      echo "SSH key not found: ${SSH_PRIVATE_KEY_PATH}" >&2
      exit 1
    fi
    SSH_OPTS+=( -i "${SSH_PRIVATE_KEY_PATH}" )
  fi
}

resolve_target_host() {
  if [[ -n "${TARGET_HOST}" ]]; then
    return
  fi

  TARGET_HOST="$(terraform -chdir="${TF_DIR}" output -raw server_ipv4)"
  if [[ -z "${TARGET_HOST}" ]]; then
    echo "Could not determine target host. Set TARGET_HOST or run terraform apply." >&2
    exit 1
  fi
}

wait_for_ssh() {
  local ready=0
  local attempt
  for attempt in $(seq 1 24); do
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "echo chaos-ssh-ready" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 5
  done

  if [[ "${ready}" -ne 1 ]]; then
    echo "SSH is not reachable on ${TARGET_HOST}:${SSH_PORT}" >&2
    exit 1
  fi
}

sync_chaos_dir_to_remote() {
  COPYFILE_DISABLE=1 tar \
    --format=ustar \
    --exclude='.DS_Store' \
    -C "${CHAOS_DIR}" \
    -czf - . \
    | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "mkdir -p '${REMOTE_CHAOS_DIR}' && tar -xzf - -C '${REMOTE_CHAOS_DIR}'"
}

run_remote_scenario_action() {
  local script_basename="$1"
  local action="$2"
  local remote_script="${REMOTE_CHAOS_DIR}/scenarios/${script_basename}"

  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "chmod +x '${remote_script}' && bash '${remote_script}' '${action}'"
}

persist_ticket() {
  local ticket_id="$1"
  local scenario_file="$2"

  mkdir -p "${TICKET_DIR}"
  cat > "${TICKET_DIR}/${ticket_id}.env" <<EOF
TICKET_ID=${ticket_id}
TARGET_HOST=${TARGET_HOST}
SCENARIO_FILE=${scenario_file}
SCENARIO_ID=${SCENARIO_ID}
SCENARIO_NAME=${SCENARIO_NAME}
SCENARIO_DIFFICULTY=${SCENARIO_DIFFICULTY}
SCENARIO_LAYER=${SCENARIO_LAYER}
USER_TICKET_FILE=${USER_TICKET_FILE}
CREATED_AT_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

load_user_ticket_template() {
  local template_file="${TICKET_TEMPLATE_DIR}/${SCENARIO_ID}.txt"

  if [[ -f "${template_file}" ]]; then
    USER_TICKET_TEMPLATE="$(cat "${template_file}")"
    return
  fi

  USER_TICKET_TEMPLATE="$(
    printf '%s\n' \
      "Bonjour equipe SRE," \
      "" \
      "Nous observons une degradation sur le service Chaos Cafe:" \
      "- comportement: lenteurs et erreurs intermittentes" \
      "- impact: clients web en echec partiel" \
      "- fenetre: incident en cours" \
      "" \
      "Merci d'investiguer et de restaurer le service."
  )"
}

write_user_ticket_file() {
  local ticket_id="$1"

  mkdir -p "${TICKET_DIR}"
  USER_TICKET_FILE="${TICKET_DIR}/${ticket_id}.ticket.txt"
  cat > "${USER_TICKET_FILE}" <<EOF
Ticket ID: ${ticket_id}
Service: chaos-cafe
Date UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Scenario ID: ${SCENARIO_ID}
Difficulty: ${SCENARIO_DIFFICULTY}
Layer: ${SCENARIO_LAYER}

Message utilisateur:
${USER_TICKET_TEMPLATE}
EOF
}

pick_ticket_file() {
  local ticket_ref="$1"
  local ticket_file=""

  mkdir -p "${TICKET_DIR}"
  if [[ "${ticket_ref}" == "last" || -z "${ticket_ref}" ]]; then
    ticket_file="$(ls -1t "${TICKET_DIR}"/*.env 2>/dev/null | head -n1 || true)"
  elif [[ -f "${ticket_ref}" ]]; then
    ticket_file="${ticket_ref}"
  elif [[ -f "${TICKET_DIR}/${ticket_ref}" ]]; then
    ticket_file="${TICKET_DIR}/${ticket_ref}"
  elif [[ -f "${TICKET_DIR}/${ticket_ref}.env" ]]; then
    ticket_file="${TICKET_DIR}/${ticket_ref}.env"
  fi

  if [[ -z "${ticket_file}" ]]; then
    echo "No ticket found for '${ticket_ref}'." >&2
    exit 1
  fi

  echo "${ticket_file}"
}

read_ticket_value() {
  local ticket_file="$1"
  local key="$2"
  local line

  line="$(grep -E "^${key}=" "${ticket_file}" | head -n1 || true)"
  if [[ -z "${line}" ]]; then
    echo ""
    return 1
  fi

  echo "${line#*=}"
}

archive_ticket_file() {
  local ticket_file="$1"
  local archived_ticket_file

  if [[ ! -f "${ticket_file}" ]]; then
    return
  fi

  case "${ticket_file}" in
    *.env)
      archived_ticket_file="${ticket_file%.env}.healed.env"
      mv "${ticket_file}" "${archived_ticket_file}"
      echo "Ticket archived: ${archived_ticket_file}"
      ;;
  esac
}

run_action() {
  local requested_id="$1"
  local scenario_script
  local scenario_file
  local ticket_id

  scenario_script="$(select_scenario_script "${requested_id}")"
  scenario_file="$(basename "${scenario_script}")"
  load_metadata "${scenario_script}"

  resolve_target_host
  build_ssh_options
  wait_for_ssh
  sync_chaos_dir_to_remote

  ticket_id="$(date -u +"%Y%m%dT%H%M%SZ")-${SCENARIO_ID}"
  load_user_ticket_template
  write_user_ticket_file "${ticket_id}"
  persist_ticket "${ticket_id}" "${scenario_file}"

  echo "Launching chaos scenario on ${TARGET_HOST}"
  echo "ID: ${SCENARIO_ID}"
  echo "Difficulty: ${SCENARIO_DIFFICULTY}"
  echo "Scenario: ${SCENARIO_NAME}"
  echo "Layer: ${SCENARIO_LAYER}"
  echo "Ticket: ${ticket_id}"

  run_remote_scenario_action "${scenario_file}" inject

  echo
  echo "User ticket"
  echo "-----------"
  cat "${USER_TICKET_FILE}"
  echo "-----------"
  echo "Saved to: ${USER_TICKET_FILE}"
  echo "Status: launched"
}

list_action() {
  collect_scenarios
  printf "%-8s %-8s %-10s %s\n" "ID" "LEVEL" "LAYER" "NAME"
  for script in "${SCENARIO_FILES[@]}"; do
    load_metadata "${script}"
    printf "%-8s %-8s %-10s %s\n" "${SCENARIO_ID}" "${SCENARIO_DIFFICULTY}" "${SCENARIO_LAYER}" "${SCENARIO_NAME}"
  done
}

heal_action() {
  local ticket_file
  local scenario_script
  local scenario_file
  local ticket_ref
  local ticket_target_host
  local ticket_id

  ticket_ref="${1:-last}"
  ticket_file="$(pick_ticket_file "${ticket_ref}")"
  scenario_file="$(read_ticket_value "${ticket_file}" "SCENARIO_FILE")"
  ticket_target_host="$(read_ticket_value "${ticket_file}" "TARGET_HOST")"
  ticket_id="$(read_ticket_value "${ticket_file}" "TICKET_ID")"

  if [[ -z "${scenario_file}" ]]; then
    echo "Ticket missing SCENARIO_FILE: ${ticket_file}" >&2
    exit 1
  fi

  if [[ -z "${ticket_target_host}" ]]; then
    echo "Ticket missing TARGET_HOST: ${ticket_file}" >&2
    exit 1
  fi

  TARGET_HOST="${ticket_target_host}"
  scenario_script="${SCENARIO_DIR}/${scenario_file}"
  if [[ ! -f "${scenario_script}" ]]; then
    echo "Scenario file from ticket not found: ${scenario_script}" >&2
    exit 1
  fi

  load_metadata "${scenario_script}"
  build_ssh_options
  wait_for_ssh
  sync_chaos_dir_to_remote

  echo "Healing chaos scenario on ${TARGET_HOST}"
  echo "ID: ${SCENARIO_ID}"
  echo "Difficulty: ${SCENARIO_DIFFICULTY}"
  echo "Scenario: ${SCENARIO_NAME}"
  if [[ -n "${ticket_id}" ]]; then
    echo "Ticket: ${ticket_id}"
  else
    echo "Ticket: $(basename "${ticket_file}" .env)"
  fi

  run_remote_scenario_action "${scenario_file}" heal

  echo "Status: healed"
  archive_ticket_file "${ticket_file}"
}

heal_all_action() {
  local ticket_files=()
  local ticket_file
  local failed=0

  mkdir -p "${TICKET_DIR}"
  while IFS= read -r ticket_file; do
    ticket_files+=( "${ticket_file}" )
  done < <(ls -1t "${TICKET_DIR}"/*.env 2>/dev/null || true)

  if [[ "${#ticket_files[@]}" -eq 0 ]]; then
    echo "No ticket found to heal."
    exit 1
  fi

  for ticket_file in "${ticket_files[@]}"; do
    echo
    echo "-----"
    if ! heal_action "${ticket_file}"; then
      failed=1
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    echo
    echo "Some scenarios failed to heal. Check logs above." >&2
    exit 1
  fi
}

case "${ACTION}" in
  run) run_action "${ARG}" ;;
  list) list_action ;;
  heal) heal_action "${ARG:-last}" ;;
  heal-all) heal_all_action ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 1
    ;;
esac
