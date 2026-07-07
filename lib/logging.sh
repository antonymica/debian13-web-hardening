#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="${LOG_DIR:-/var/log/debian13-hardening}"
HARDENING_TIMESTAMP="${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/hardening-${HARDENING_TIMESTAMP}.log}"
DEBUG="${DEBUG:-false}"

init_logging() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    mkdir -p "$LOG_DIR"
  else
    mkdir -p "$LOG_DIR"
    chmod 0750 "$LOG_DIR"
  fi
  touch "$LOG_FILE"
  chmod 0640 "$LOG_FILE"
}

_log_line() {
  local level="$1"
  local color="$2"
  shift 2
  local message="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[${ts}] [${level}] ${message}"
  printf '%s%s%s\n' "$color" "$line" "${COLOR_RESET:-}"
  printf '%s\n' "$line" >> "$LOG_FILE"
  if [[ "${WEB_REPORT_LIVE_ENABLED:-true}" == "true" && "${PUBLISHING_WEB_STATUS:-false}" != "true" ]] \
    && declare -F publish_web_status >/dev/null 2>&1; then
    publish_web_status "$level" "$message" "${WEB_REPORT_RUNNING:-true}" || true
  fi
}

log_info() {
  _log_line "INFO" "${COLOR_BLUE:-}" "$@"
}

log_success() {
  _log_line "SUCCESS" "${COLOR_GREEN:-}" "$@"
}

log_warn() {
  _log_line "WARN" "${COLOR_YELLOW:-}" "$@"
}

log_error() {
  _log_line "ERROR" "${COLOR_RED:-}" "$@"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    _log_line "DEBUG" "${COLOR_MAGENTA:-}" "$@"
  fi
}

log_section() {
  local message="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[${ts}] [SECTION] ${message}"
  printf '\n%s%s%s\n' "${COLOR_BOLD:-}${COLOR_CYAN:-}" "$line" "${COLOR_RESET:-}"
  printf '\n%s\n' "$line" >> "$LOG_FILE"
}

log_backup() {
  _log_line "BACKUP" "${COLOR_CYAN:-}" "$@"
}
