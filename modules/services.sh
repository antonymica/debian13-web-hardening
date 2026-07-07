#!/usr/bin/env bash
set -Eeuo pipefail

_is_protected_service() {
  local svc="$1"
  local protected
  for protected in "${SERVICE_PROTECTED[@]+"${SERVICE_PROTECTED[@]}"}"; do
    [[ "$svc" == "$protected" ]] && return 0
  done
  return 1
}

run_services_hardening() {
  log_section "Disable unnecessary services"
  report_add_module "services"
  log_info "Listing enabled services"
  systemctl list-unit-files --type=service --state=enabled || true

  local is_gcp svc disabled_count
  is_gcp="false"
  disabled_count=0
  if detect_gcp; then
    is_gcp="true"
    log_warn "GCP detected: Google guest agents will not be disabled"
  fi

  for svc in "${SERVICE_DISABLE_CANDIDATES[@]+"${SERVICE_DISABLE_CANDIDATES[@]}"}"; do
    [[ -n "$svc" ]] || continue
    if _is_protected_service "$svc"; then
      log_info "Skipping protected service: ${svc}"
      continue
    fi
    if [[ "$is_gcp" == "true" && "$svc" == google-* ]]; then
      log_info "Skipping GCP service: ${svc}"
      continue
    fi
    if ! service_exists "$svc"; then
      log_debug "Service not found: ${svc}"
      continue
    fi
    if ! systemctl is-enabled --quiet "$svc" 2>/dev/null && ! service_is_active "$svc"; then
      log_info "Service is not enabled or active: ${svc}"
      continue
    fi
    if confirm "Disable service ${svc}?"; then
      report_mark_changed "Service disabled"
      run_cmd systemctl disable --now "$svc"
      report_add_disabled_service "$svc"
      ((disabled_count += 1))
      log_success "Disabled service ${svc}"
    else
      log_info "Skipped service ${svc}"
      report_add_recommendation "Review whether service ${svc} is required."
    fi
  done

  if ((disabled_count == 0)); then
    log_success "No unnecessary service was disabled; service state is already acceptable"
    report_add_already_configured "No enabled unnecessary service required disabling"
  fi
}
