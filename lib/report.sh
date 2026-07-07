#!/usr/bin/env bash
set -Eeuo pipefail

REPORT_DIR="${REPORT_DIR:-/var/log/debian13-hardening/reports}"
REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/hardening-report-${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}.md}"

REPORT_MODULES=()
REPORT_MODIFIED_FILES=()
REPORT_BACKUPS=()
REPORT_FIREWALL_RULES=()
REPORT_DISABLED_SERVICES=()
REPORT_RECOMMENDATIONS=()
REPORT_ROLLBACK_COMMANDS=()

init_report() {
  mkdir -p "$REPORT_DIR"
  chmod 0750 "$REPORT_DIR"
}

_report_add_unique() {
  local array_name="$1"
  local value="$2"
  local current
  local -n report_array="$array_name"
  for current in "${report_array[@]+"${report_array[@]}"}"; do
    if [[ "$current" == "$value" ]]; then
      return 0
    fi
  done
  report_array+=("$value")
}

report_add_module() {
  _report_add_unique REPORT_MODULES "$1"
}

report_add_modified_file() {
  _report_add_unique REPORT_MODIFIED_FILES "$1"
}

report_add_backup() {
  _report_add_unique REPORT_BACKUPS "$1"
}

report_add_firewall_rule() {
  _report_add_unique REPORT_FIREWALL_RULES "$1"
}

report_add_disabled_service() {
  _report_add_unique REPORT_DISABLED_SERVICES "$1"
}

report_add_recommendation() {
  _report_add_unique REPORT_RECOMMENDATIONS "$1"
}

report_add_rollback_command() {
  _report_add_unique REPORT_ROLLBACK_COMMANDS "$1"
}

_markdown_list() {
  local item
  local wrote="false"
  if (($# == 0)); then
    printf -- '- None recorded\n'
    return 0
  fi
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    printf -- '- %s\n' "$item"
    wrote="true"
  done
  if [[ "$wrote" != "true" ]]; then
    printf -- '- None recorded\n'
  fi
}

generate_report() {
  local hostname debian_version public_ip provider
  hostname="$(hostname -f 2>/dev/null || hostname)"
  debian_version="$(get_debian_version 2>/dev/null || printf 'Unknown')"
  public_ip="$(get_public_ip 2>/dev/null || printf 'Unavailable')"
  provider="$(detect_cloud_provider 2>/dev/null || printf 'Unknown')"

  {
    printf '# Debian 13 Web Hardening Report\n\n'
    printf '- Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf '- Hostname: %s\n' "$hostname"
    printf '- Public IP: %s\n' "$public_ip"
    printf '- Cloud provider: %s\n' "$provider"
    printf '- Debian version: %s\n' "$debian_version"
    printf '- Log file: %s\n' "$LOG_FILE"
    printf '- Backup directory: %s\n\n' "${BACKUP_DIR:-Not initialized}"

    printf '## Modules executed\n\n'
    _markdown_list "${REPORT_MODULES[@]+"${REPORT_MODULES[@]}"}"
    printf '\n## Files modified\n\n'
    _markdown_list "${REPORT_MODIFIED_FILES[@]+"${REPORT_MODIFIED_FILES[@]}"}"
    printf '\n## Backups created\n\n'
    _markdown_list "${REPORT_BACKUPS[@]+"${REPORT_BACKUPS[@]}"}"
    printf '\n## Firewall rules applied\n\n'
    _markdown_list "${REPORT_FIREWALL_RULES[@]+"${REPORT_FIREWALL_RULES[@]}"}"
    printf '\n## Services disabled\n\n'
    _markdown_list "${REPORT_DISABLED_SERVICES[@]+"${REPORT_DISABLED_SERVICES[@]}"}"
    printf '\n## Remaining recommendations\n\n'
    _markdown_list "${REPORT_RECOMMENDATIONS[@]+"${REPORT_RECOMMENDATIONS[@]}"}"
    printf '\n## Rollback commands\n\n'
    _markdown_list "${REPORT_ROLLBACK_COMMANDS[@]+"${REPORT_ROLLBACK_COMMANDS[@]}"}"
  } > "$REPORT_FILE"

  chmod 0640 "$REPORT_FILE"
  log_success "Security report written to ${REPORT_FILE}"
}
