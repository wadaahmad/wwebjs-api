#!/usr/bin/env bash
#
# Periodically terminate inactive WhatsApp sessions so they stop
# consuming disk/CPU/RAM. Use when you do not fully control session lifecycle.
#
# Corresponds to README: run /session/terminateInactive on a schedule.
#
# Example crontab (every hour):
#   0 * * * * /path/ke/wwebjs-api/scripts/terminate-inactive-sessions.sh >/dev/null 2>&1
#
# Optional env overrides:
#   BASE_URL=http://127.0.0.1:3000
#   BASE_PATH=                # e.g. /api/v1/whatsapp if set in .env
#   API_KEY=...               # or load from project .env
#   LOG_FILE=...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
BASE_PATH="${BASE_PATH:-}"
API_KEY="${API_KEY:-}"
LOG_FILE="${LOG_FILE:-${PROJECT_DIR}/logs/terminate-inactive-sessions.log}"
LOCK_FILE="${LOCK_FILE:-${PROJECT_DIR}/logs/terminate-inactive-sessions.lock}"
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Load API_KEY / BASE_PATH from .env if not already set
if [[ -f "${ENV_FILE}" ]]; then
  if [[ -z "${API_KEY}" ]]; then
    API_KEY="$(grep -E '^[[:space:]]*API_KEY=' "${ENV_FILE}" | tail -n1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true)"
  fi
  if [[ -z "${BASE_PATH}" ]]; then
    BASE_PATH="$(grep -E '^[[:space:]]*BASE_PATH=' "${ENV_FILE}" | tail -n1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true)"
  fi
fi

# Normalize BASE_PATH: empty or leading slash, no trailing slash
BASE_PATH="${BASE_PATH%/}"
if [[ -n "${BASE_PATH}" && "${BASE_PATH}" != /* ]]; then
  BASE_PATH="/${BASE_PATH}"
fi

URL="${BASE_URL%/}${BASE_PATH}/session/terminateInactive"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  log "Another terminate-inactive run is in progress; exiting"
  exit 0
fi

log "Calling ${URL}"

CURL_ARGS=(-sS -f -X GET --max-time "${CURL_TIMEOUT}" -H "Accept: application/json")
if [[ -n "${API_KEY}" ]]; then
  CURL_ARGS+=(-H "x-api-key: ${API_KEY}")
fi

if ! RESPONSE="$(curl "${CURL_ARGS[@]}" "${URL}")"; then
  log "ERROR: request failed (curl exit $?)"
  exit 1
fi

log "OK: ${RESPONSE}"
