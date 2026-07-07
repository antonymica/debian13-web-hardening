#!/usr/bin/env bash
set -Eeuo pipefail

run_updates_hardening() {
  log_section "System updates and unattended upgrades"
  report_add_module "updates"
  log_info "Starting updates hardening module"

  install_packages unattended-upgrades apt-listchanges needrestart

  local conf tmp reboot_value
  conf="/etc/apt/apt.conf.d/52-debian13-hardening"
  tmp="$(mktemp)"
  reboot_value="false"
  if is_true "${AUTO_REBOOT:-false}"; then
    reboot_value="true"
    report_add_recommendation "Automatic reboot is enabled; confirm maintenance windows and service availability."
  fi

  backup_file "$conf"
  {
    printf '// Managed by debian13-web-hardening.\n'
    printf 'APT::Periodic::Update-Package-Lists "1";\n'
    printf 'APT::Periodic::Download-Upgradeable-Packages "1";\n'
    printf 'APT::Periodic::AutocleanInterval "7";\n'
    printf 'APT::Periodic::Unattended-Upgrade "1";\n'
    printf 'APT::Periodic::Verbose "1";\n'
    printf 'Unattended-Upgrade::Remove-Unused-Dependencies "true";\n'
    printf 'Unattended-Upgrade::Automatic-Reboot "%s";\n' "$reboot_value"
    printf 'Unattended-Upgrade::Automatic-Reboot-Time "03:30";\n'
  } > "$tmp"

  install_file_if_changed "$tmp" "$conf" 0644
  rm -f "$tmp"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd systemctl enable --now unattended-upgrades
  fi
  log_success "Unattended upgrades configured"
}

