#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/hetzner/terraform"
APP_DIR="${ROOT_DIR}/src"

SSH_USER="${SSH_USER:-root}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_rsa}"
SSH_PORT="${SSH_PORT:-22}"
TARGET_HOST="${TARGET_HOST:-}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Missing app folder: ${APP_DIR}" >&2
  exit 1
fi

if [[ -z "${TARGET_HOST}" ]]; then
  TARGET_HOST="$(terraform -chdir="${TF_DIR}" output -raw server_ipv4)"
fi

if [[ -z "${TARGET_HOST}" ]]; then
  echo "Could not determine target host (set TARGET_HOST or run terraform apply first)." >&2
  exit 1
fi

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

echo "Waiting for SSH on ${SSH_USER}@${TARGET_HOST}:${SSH_PORT}..."
ready=0
for attempt in $(seq 1 36); do
  if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "echo ssh-ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 5
done

if [[ "${ready}" -ne 1 ]]; then
  echo "SSH is not reachable on ${TARGET_HOST}." >&2
  exit 1
fi

echo "Installing Docker prerequisites on ${TARGET_HOST}..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --wait || true
fi

apt-get update -y
apt-get install -y ca-certificates curl

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
fi

systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker-compose-plugin
fi

mkdir -p /opt/chaos-cafe
REMOTE

echo "Copying app sources to ${TARGET_HOST}..."
COPYFILE_DISABLE=1 tar \
  --format=ustar \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='dist' \
  --exclude='.DS_Store' \
  -C "${APP_DIR}" \
  -czf - . \
  | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "rm -rf /opt/chaos-cafe/* && tar -xzf - -C /opt/chaos-cafe"

echo "Starting app stack on ${TARGET_HOST}..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" <<'REMOTE'
set -euo pipefail
cat > /opt/chaos-cafe/.env <<'ENV'
LB_PUBLISHED_PORT=80
ENV

cd /opt/chaos-cafe
docker compose up -d --build
docker compose ps
REMOTE

echo
echo "Deployment complete."
echo "App URL: http://${TARGET_HOST}"
echo "Health check: http://${TARGET_HOST}/healthz"
