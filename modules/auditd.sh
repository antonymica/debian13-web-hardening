#!/usr/bin/env bash
set -Eeuo pipefail

run_auditd_hardening() {
  log_section "Auditd and security logs"
  report_add_module "auditd"

  install_packages auditd audispd-plugins

  local rules tmp
  rules="/etc/audit/rules.d/debian13-hardening.rules"
  tmp="$(mktemp)"
  backup_file "$rules"

  {
    printf '# Managed by debian13-web-hardening.\n'
    printf '-w /etc/passwd -p wa -k identity\n'
    printf '-w /etc/shadow -p wa -k identity\n'
    printf '-w /etc/group -p wa -k identity\n'
    printf '-w /etc/sudoers -p wa -k privilege\n'
    printf '-w /etc/sudoers.d/ -p wa -k privilege\n'
    printf '-w /etc/ssh/sshd_config -p wa -k sshd_config\n'
    printf '-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config\n'
    printf '-w /var/log/auth.log -p wa -k authlog\n'
    printf '-w /usr/sbin/usermod -p x -k identity_exec\n'
    printf '-w /usr/bin/passwd -p x -k identity_exec\n'
    printf '-w /usr/bin/chage -p x -k identity_exec\n'
    printf '-w /usr/bin/sudo -p x -k privilege_exec\n'
    printf '-w /usr/bin/su -p x -k privilege_exec\n'
    printf '-w /usr/bin/systemctl -p x -k service_exec\n'
  } > "$tmp"

  install_file_if_changed "$tmp" "$rules" 0644
  rm -f "$tmp"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd augenrules --load
    run_cmd systemctl restart auditd
  fi
  log_success "Auditd rules configured"
}

