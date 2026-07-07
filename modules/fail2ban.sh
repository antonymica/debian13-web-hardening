#!/usr/bin/env bash
set -Eeuo pipefail

run_fail2ban_hardening() {
  log_section "Fail2ban hardening"
  report_add_module "fail2ban"
  log_info "Starting Fail2ban hardening module"

  install_packages fail2ban

  local jail tmp ssh_port
  jail="/etc/fail2ban/jail.d/debian13-hardening.local"
  tmp="$(mktemp)"
  ssh_port="$(detect_ssh_port)"

  backup_file "$jail"

  {
    printf '# Managed by debian13-web-hardening.\n'
    printf '[DEFAULT]\n'
    printf 'bantime = %s\n' "${FAIL2BAN_BANTIME:-1h}"
    printf 'findtime = %s\n' "${FAIL2BAN_FINDTIME:-10m}"
    printf 'maxretry = %s\n' "${FAIL2BAN_MAXRETRY:-5}"
    printf 'backend = systemd\n'
    printf 'ignoreip = %s\n\n' "${FAIL2BAN_IGNOREIP:-127.0.0.1/8 ::1}"
    printf '[sshd]\n'
    printf 'enabled = true\n'
    printf 'port = %s\n' "$ssh_port"
    printf 'backend = systemd\n\n'
    if [[ -d /etc/nginx && -f /var/log/nginx/error.log ]]; then
      printf '[nginx-http-auth]\n'
      printf 'enabled = true\n'
      printf 'logpath = /var/log/nginx/error.log\n\n'
    elif [[ -d /etc/nginx ]]; then
      report_add_recommendation "Nginx detected, but /var/log/nginx/error.log was not found; enable nginx-http-auth jail after logs exist."
    fi
    if [[ "${APACHE_ENABLED:-false}" == "true" && -d /etc/apache2 && -f /var/log/apache2/error.log ]]; then
      printf '[apache-auth]\n'
      printf 'enabled = true\n'
      printf 'logpath = /var/log/apache2/error.log\n\n'
    elif [[ "${APACHE_ENABLED:-false}" == "true" && -d /etc/apache2 ]]; then
      report_add_recommendation "Apache detected, but /var/log/apache2/error.log was not found; enable apache-auth jail after logs exist."
    fi
  } > "$tmp"

  install_file_if_changed "$tmp" "$jail" 0644
  rm -f "$tmp"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] fail2ban-client -t"
    return 0
  fi

  fail2ban-client -t
  log_success "Fail2ban configuration test passed"
  run_cmd systemctl restart fail2ban
  fail2ban-client status || true
  log_success "Fail2ban hardening completed"
}
