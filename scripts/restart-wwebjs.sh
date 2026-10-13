#!/usr/bin/env bash
#
# Full restart for wwebjs-api: stop container, kill orphan Chromium,
# clear browser Singleton locks, then start again.
#
# Intended for cron on a Linux server. Example crontab (daily 04:00):
#   0 4 * * * /path/ke/wwebjs-api/scripts/restart-wwebjs.sh >/dev/null 2>&1
#
# Override defaults via environment if needed:
#   PROJECT_DIR=/opt/wwebjs-api LOG_FILE=/var/log/restart-wwebjs.log \
#     /path/ke/wwebjs-api/scripts/restart-wwebjs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CONTAINER_NAME="${CONTAINER_NAME:-wwebjs-api}"
SESSIONS_DIR="${SESSIONS_DIR:-${PROJECT_DIR}/sessions}"
LOG_FILE="${LOG_FILE:-${PROJECT_DIR}/logs/restart-wwebjs.log}"
LOCK_FILE="${LOCK_FILE:-${PROJECT_DIR}/logs/restart-wwebjs.lock}"
STOP_WAIT_SECONDS="${STOP_WAIT_SECONDS:-5}"

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    log "ERROR: neither 'docker compose' nor 'docker-compose' is available"
    exit 1
  fi
}

kill_chromium() {
  # Exit codes from pkill: 0=matched, 1=no process — both OK
  pkill -9 -f chromium || true
  pkill -9 -f '/chrome( |$)' || true
  pkill -9 -f 'chrome-headless' || true
}

clear_singleton_locks() {
  if [[ ! -d "${SESSIONS_DIR}" ]]; then
    log "Sessions dir missing (${SESSIONS_DIR}); skipping lock cleanup"
    return 0
  fi

  local count=0
  while IFS= read -r -d '' file; do
    rm -f "${file}"
    count=$((count + 1))
  done < <(find "${SESSIONS_DIR}" \( \
    -name 'SingletonLock' -o \
    -name 'SingletonCookie' -o \
    -name 'SingletonSocket' \
  \) -print0 2>/dev/null || true)

  log "Removed ${count} Singleton lock file(s)"
}

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  log "Another restart is already running; exiting"
  exit 0
fi

log "=== restart-wwebjs start (project=${PROJECT_DIR}) ==="

cd "${PROJECT_DIR}"

log "Stopping compose services..."
compose stop
log "Waiting ${STOP_WAIT_SECONDS}s after stop..."
sleep "${STOP_WAIT_SECONDS}"

log "Killing orphan Chromium/Chrome processes..."
kill_chromium
sleep 1
# Second pass in case children respawned briefly
kill_chromium

clear_singleton_locks

log "Starting compose services..."
compose up -d

if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  log "Container ${CONTAINER_NAME} is running"
else
  log "WARN: container ${CONTAINER_NAME} not found in docker ps (check compose logs)"
fi

log "=== restart-wwebjs done ==="
