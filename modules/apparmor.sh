#!/usr/bin/env bash
set -Eeuo pipefail

run_apparmor_hardening() {
  log_section "AppArmor hardening"
  report_add_module "apparmor"

  install_packages apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd systemctl enable --now apparmor
    aa-status || true
  fi

  report_add_recommendation "Review AppArmor profiles before switching additional profiles to enforce mode."
  log_success "AppArmor installed and enabled where supported"
}

