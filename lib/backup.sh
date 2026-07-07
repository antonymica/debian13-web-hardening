#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/debian13-hardening}"
BACKUP_DIR="${BACKUP_DIR:-${BACKUP_ROOT}/${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}}"
BACKUP_MANIFEST="${BACKUP_MANIFEST:-${BACKUP_DIR}/backup-manifest.txt}"
INITIAL_BACKUP_DIR="${INITIAL_BACKUP_DIR:-${BACKUP_DIR}/initial-config}"
INITIAL_BACKUP_MANIFEST="${INITIAL_BACKUP_MANIFEST:-${INITIAL_BACKUP_DIR}/initial-config-manifest.txt}"
MISSING_BACKUP_MARKER="__DEBIAN13_HARDENING_MISSING__"

init_backup() {
  ensure_dir "$BACKUP_DIR" 0700
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    touch "$BACKUP_MANIFEST"
    chmod 0600 "$BACKUP_MANIFEST"
  fi
  report_add_rollback_command "sudo ./harden.sh --rollback"
}

record_missing_path() {
  local path="$1"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] record initially missing path ${path}"
    return 0
  fi
  printf '%s|%s\n' "$path" "$MISSING_BACKUP_MARKER" >> "$BACKUP_MANIFEST"
}

backup_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    log_info "No backup needed for missing file ${path}"
    record_missing_path "$path"
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

initial_config_backup() {
  if [[ "${INITIAL_BACKUP_ENABLED:-true}" != "true" ]]; then
    log_warn "Initial configuration backup is disabled by configuration"
    report_add_recommendation "Initial configuration backup was disabled for this run."
    return 0
  fi

  log_section "Initial configuration backup"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] initial backup would be created under ${INITIAL_BACKUP_DIR}"
    log_info "[dry-run] dry-run mode does not create /var/backups entries"
    local path
    for path in "${INITIAL_BACKUP_PATHS[@]+"${INITIAL_BACKUP_PATHS[@]}"}"; do
      [[ -n "$path" ]] && log_info "[dry-run] initial backup would include ${path}"
    done
    return 0
  fi

  mkdir -p "${INITIAL_BACKUP_DIR}/filesystem"
  chmod 0700 "$INITIAL_BACKUP_DIR" "${INITIAL_BACKUP_DIR}/filesystem"
  touch "$INITIAL_BACKUP_MANIFEST"
  chmod 0600 "$INITIAL_BACKUP_MANIFEST"

  local path rel dest dest_parent
  for path in "${INITIAL_BACKUP_PATHS[@]+"${INITIAL_BACKUP_PATHS[@]}"}"; do
    [[ -n "$path" ]] || continue
    if [[ "$path" != /* ]]; then
      log_warn "Skipping non-absolute initial backup path: ${path}"
      continue
    fi

    if [[ ! -e "$path" ]]; then
      log_info "Initial path not present: ${path}"
      printf '%s|%s\n' "$path" "$MISSING_BACKUP_MARKER" >> "$INITIAL_BACKUP_MANIFEST"
      printf '%s|%s\n' "$path" "$MISSING_BACKUP_MARKER" >> "$BACKUP_MANIFEST"
      continue
    fi

    rel="${path#/}"
    dest="${INITIAL_BACKUP_DIR}/filesystem/${rel}"
    dest_parent="$(dirname "$dest")"
    mkdir -p "$dest_parent"
    cp -a "$path" "$dest"
    printf '%s|%s\n' "$path" "$dest" >> "$INITIAL_BACKUP_MANIFEST"
    printf '%s|%s\n' "$path" "$dest" >> "$BACKUP_MANIFEST"
    log_backup "Initial ${path} saved to ${dest}"
    report_add_backup "Initial ${path} -> ${dest}"
  done

  {
    printf 'timestamp=%s\n' "${HARDENING_TIMESTAMP:-unknown}"
    printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'profile=%s\n' "${PROFILE:-unknown}"
    printf 'dry_run=%s\n' "${DRY_RUN:-false}"
  } > "${INITIAL_BACKUP_DIR}/metadata.txt"
  chmod 0600 "${INITIAL_BACKUP_DIR}/metadata.txt"

  log_success "Initial configuration backup completed: ${INITIAL_BACKUP_DIR}"
  report_add_rollback_command "sudo ./harden.sh --rollback # restore from ${BACKUP_DIR}"
}
