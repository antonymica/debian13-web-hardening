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

  local selected manifest original backup restored_count removed_count skipped_count
  selected="${backups[$((choice - 1))]}"
  manifest="${selected}/backup-manifest.txt"
  restored_count=0
  removed_count=0
  skipped_count=0
  if [[ ! -r "$manifest" ]]; then
    log_error "Manifest not readable: ${manifest}"
    return 1
  fi

  if ! confirm "Restore files from ${selected}?"; then
    log_info "Rollback cancelled"
    return 0
  fi

  local entries=()
  local line index
  while IFS= read -r line; do
    [[ -n "$line" ]] && entries+=("$line")
  done < "$manifest"

  for ((index = ${#entries[@]} - 1; index >= 0; index--)); do
    IFS='|' read -r original backup <<< "${entries[$index]}"
    [[ -n "$original" && -n "$backup" ]] || continue
    if [[ "$backup" == "${MISSING_BACKUP_MARKER:-__DEBIAN13_HARDENING_MISSING__}" ]]; then
      if [[ ! -e "$original" ]]; then
        log_info "Path still absent, nothing to remove: ${original}"
        ((skipped_count += 1))
        continue
      fi
      if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] remove path created after backup: ${original}"
        ((skipped_count += 1))
        continue
      fi
      if [[ -f "$original" || -L "$original" ]]; then
        rm -f "$original"
        log_success "Removed file created after backup: ${original}"
        report_add_rollback_action "Removed file created after backup: ${original}"
        ((removed_count += 1))
      elif [[ -d "$original" ]]; then
        if rmdir "$original" 2>/dev/null; then
          log_success "Removed empty directory created after backup: ${original}"
          report_add_rollback_action "Removed empty directory created after backup: ${original}"
          ((removed_count += 1))
        else
          log_warn "Directory was absent during backup but is not empty now; leaving in place: ${original}"
          report_add_rollback_action "Left non-empty directory in place: ${original}"
          ((skipped_count += 1))
        fi
      else
        log_warn "Path was absent during backup but is an unsupported type now; leaving in place: ${original}"
        report_add_rollback_action "Left unsupported path type in place: ${original}"
        ((skipped_count += 1))
      fi
      continue
    fi
    if [[ ! -e "$backup" ]]; then
      log_warn "Backup missing: ${backup}"
      report_add_rollback_action "Backup missing: ${backup}"
      ((skipped_count += 1))
      continue
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[dry-run] restore ${backup} -> ${original}"
      ((skipped_count += 1))
      continue
    fi
    if [[ -d "$backup" && ! -L "$backup" ]]; then
      mkdir -p "$original"
      cp -a "${backup}/." "${original}/"
      chown --reference="$backup" "$original" 2>/dev/null || true
      chmod --reference="$backup" "$original" 2>/dev/null || true
    else
      mkdir -p "$(dirname "$original")"
      cp -a "$backup" "$original"
    fi
    log_success "Restored ${original}"
    report_add_rollback_action "Restored ${original}"
    ((restored_count += 1))
  done

  report_add_module "rollback"
  log_success "Rollback completed: ${restored_count} restored, ${removed_count} removed, ${skipped_count} skipped. Validate affected services before closing your session."
  report_add_rollback_action "Rollback summary: ${restored_count} restored, ${removed_count} removed, ${skipped_count} skipped."
  report_add_recommendation "After rollback, validate affected services and reload them manually if needed."
}
