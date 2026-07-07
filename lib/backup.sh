#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/debian13-hardening}"
BACKUP_DIR="${BACKUP_DIR:-${BACKUP_ROOT}/${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}}"
BACKUP_MANIFEST="${BACKUP_MANIFEST:-${BACKUP_DIR}/backup-manifest.txt}"

init_backup() {
  ensure_dir "$BACKUP_DIR" 0750
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    touch "$BACKUP_MANIFEST"
    chmod 0640 "$BACKUP_MANIFEST"
  fi
  report_add_rollback_command "sudo ./harden.sh --rollback"
}

backup_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    log_info "No backup needed for missing file ${path}"
    return 0
  fi

  local rel backup_path backup_parent
  rel="${path#/}"
  backup_path="${BACKUP_DIR}/${rel}.bak"
  backup_parent="$(dirname "$backup_path")"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] backup ${path} -> ${backup_path}"
    report_add_backup "${path} -> ${backup_path}"
    return 0
  fi

  mkdir -p "$backup_parent"
  cp -a "$path" "$backup_path"
  printf '%s|%s\n' "$path" "$backup_path" >> "$BACKUP_MANIFEST"
  log_backup "${path} saved to ${backup_path}"
  report_add_backup "${path} -> ${backup_path}"
}

