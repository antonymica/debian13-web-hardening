#!/usr/bin/env bash
set -Eeuo pipefail

run_apparmor_hardening() {
  log_section "AppArmor hardening"
  report_add_module "apparmor"

  install_packages apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    if systemctl is-enabled --quiet apparmor 2>/dev/null && service_is_active apparmor; then
      log_success "AppArmor already installed, enabled, and active"
      report_add_already_configured "apparmor service"
    else
      report_mark_changed "AppArmor service enabled"
      run_cmd systemctl enable --now apparmor
    fi
    aa-status || true
  fi

  report_add_recommendation "Review AppArmor profiles before switching additional profiles to enforce mode."
  log_success "AppArmor installed and enabled where supported"
}
