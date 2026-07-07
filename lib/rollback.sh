#!/usr/bin/env bash
set -Eeuo pipefail

rollback_interactive() {
  log_section "Rollback"
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    log_warn "No backup root found at ${BACKUP_ROOT}"
    return 0
  fi

  local backups=()
  local dir
  while IFS= read -r dir; do
    backups+=("$dir")
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)

  if ((${#backups[@]} == 0)); then
    log_warn "No backups available"
    return 0
  fi

  local i
  printf 'Available backups:\n'
  for i in "${!backups[@]}"; do
    printf '%s) %s\n' "$((i + 1))" "${backups[$i]}"
  done

  local choice
  read -r -p "Select backup to restore [1-${#backups[@]}] or 0 to cancel: " choice
  if [[ "$choice" == "0" || -z "$choice" ]]; then
    log_info "Rollback cancelled"
    return 0
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#backups[@]})); then
    log_error "Invalid rollback selection"
    return 1
  fi

  local selected manifest original backup
  selected="${backups[$((choice - 1))]}"
  manifest="${selected}/backup-manifest.txt"
  if [[ ! -r "$manifest" ]]; then
    log_error "Manifest not readable: ${manifest}"
    return 1
  fi

  if ! confirm "Restore files from ${selected}?"; then
    log_info "Rollback cancelled"
    return 0
  fi

  while IFS='|' read -r original backup; do
    [[ -n "$original" && -n "$backup" ]] || continue
    if [[ ! -e "$backup" ]]; then
      log_warn "Backup missing: ${backup}"
      continue
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[dry-run] restore ${backup} -> ${original}"
      continue
    fi
    mkdir -p "$(dirname "$original")"
    cp -a "$backup" "$original"
    log_success "Restored ${original}"
  done < "$manifest"

  report_add_module "rollback"
  report_add_recommendation "After rollback, validate affected services and reload them manually if needed."
}

