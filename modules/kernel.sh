#!/usr/bin/env bash
set -Eeuo pipefail

run_kernel_hardening() {
  log_section "Kernel and sysctl hardening"
  report_add_module "kernel"
  log_info "Starting kernel/sysctl hardening module"

  local conf tmp
  conf="/etc/sysctl.d/99-debian13-hardening.conf"
  tmp="$(mktemp)"

  {
    printf '# Managed by debian13-web-hardening.\n'
    printf '# BEGIN DEBIAN13-WEB-HARDENING\n'
    printf 'net.ipv4.ip_forward = 0\n'
    printf 'net.ipv4.conf.all.accept_redirects = 0\n'
    printf 'net.ipv4.conf.default.accept_redirects = 0\n'
    printf 'net.ipv4.conf.all.secure_redirects = 0\n'
    printf 'net.ipv4.conf.default.secure_redirects = 0\n'
    printf 'net.ipv4.conf.all.send_redirects = 0\n'
    printf 'net.ipv4.conf.default.send_redirects = 0\n'
    printf 'net.ipv4.conf.all.accept_source_route = 0\n'
    printf 'net.ipv4.conf.default.accept_source_route = 0\n'
    printf 'net.ipv4.conf.all.log_martians = 1\n'
    printf 'net.ipv4.conf.default.log_martians = 1\n'
    printf 'net.ipv4.tcp_syncookies = 1\n'
    printf 'net.ipv4.icmp_echo_ignore_broadcasts = 1\n'
    printf 'net.ipv4.icmp_ignore_bogus_error_responses = 1\n'
    printf 'kernel.randomize_va_space = 2\n'
    printf 'kernel.kptr_restrict = 2\n'
    printf 'kernel.dmesg_restrict = 1\n'
    printf 'fs.protected_hardlinks = 1\n'
    printf 'fs.protected_symlinks = 1\n'
    if is_true "${DISABLE_IPV6:-false}"; then
      printf 'net.ipv6.conf.all.disable_ipv6 = 1\n'
      printf 'net.ipv6.conf.default.disable_ipv6 = 1\n'
      report_add_recommendation "IPv6 was disabled by profile; verify that applications and monitoring do not require IPv6."
    else
      printf '# IPv6 is intentionally not disabled by default.\n'
    fi
    printf '# END DEBIAN13-WEB-HARDENING\n'
  } > "$tmp"

  if [[ -f "$conf" ]] && cmp -s "$tmp" "$conf"; then
    log_success "Kernel/sysctl hardening already configured; no sysctl reload needed"
    report_add_already_configured "$conf"
    rm -f "$tmp"
    return 0
  fi

  backup_file "$conf"
  install_file_if_changed "$tmp" "$conf" 0644
  rm -f "$tmp"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd sysctl --system
  fi
  log_success "Kernel/sysctl hardening completed"
}
