#!/usr/bin/env bash
set -Eeuo pipefail

run_ssh_hardening() {
  log_section "SSH hardening"
  report_add_module "ssh"
  log_info "Starting SSH hardening module"
  warn_gcp_if_detected

  install_packages openssh-server

  local ssh_port admin_user key_detected password_setting dropin tmp previous existed
  ssh_port="$(detect_ssh_port)"
  admin_user="$(detect_admin_user)"
  dropin="/etc/ssh/sshd_config.d/90-debian13-hardening.conf"
  tmp="$(mktemp)"
  previous="$(mktemp)"
  existed="false"

  log_info "Detected SSH port: ${ssh_port}"
  if active_ssh_session_detected; then
    log_info "Active SSH session detected"
  else
    log_warn "No active SSH session detected from environment variables"
  fi

  if has_valid_ssh_public_key "$admin_user"; then
    key_detected="true"
    log_success "Valid SSH public key detected for user ${admin_user}"
  else
    key_detected="false"
    log_warn "No valid SSH public key detected for user ${admin_user}"
    report_add_recommendation "Add and verify an SSH public key for ${admin_user} before disabling password authentication."
  fi

  password_setting=""
  case "${SSH_PASSWORD_AUTH:-auto}" in
    no)
      if [[ "$key_detected" == "true" ]]; then
        password_setting="PasswordAuthentication no"
      else
        log_warn "PasswordAuthentication will not be disabled because no valid SSH public key was detected"
      fi
      ;;
    yes)
      password_setting="PasswordAuthentication yes"
      log_warn "PasswordAuthentication explicitly kept enabled by configuration"
      ;;
    auto)
      if [[ "$key_detected" == "true" ]]; then
        password_setting="PasswordAuthentication no"
      else
        log_warn "PasswordAuthentication was not disabled because no valid SSH public key was detected"
      fi
      ;;
    *)
      log_warn "Unknown SSH_PASSWORD_AUTH=${SSH_PASSWORD_AUTH}; leaving password authentication unchanged"
      ;;
  esac

  backup_file /etc/ssh/sshd_config
  if [[ -e "$dropin" ]]; then
    existed="true"
    cp -a "$dropin" "$previous"
    backup_file "$dropin"
  fi

  {
    printf '# Managed by debian13-web-hardening. Do not edit manually.\n'
    printf '# BEGIN DEBIAN13-WEB-HARDENING\n'
    printf 'PermitRootLogin no\n'
    printf 'PubkeyAuthentication yes\n'
    if [[ -n "$password_setting" ]]; then
      printf '%s\n' "$password_setting"
    else
      printf '# PasswordAuthentication unchanged: no valid admin public key detected.\n'
    fi
    printf 'KbdInteractiveAuthentication no\n'
    printf 'ChallengeResponseAuthentication no\n'
    printf 'X11Forwarding no\n'
    printf 'AllowTcpForwarding %s\n' "${SSH_ALLOW_TCP_FORWARDING:-no}"
    printf 'PermitEmptyPasswords no\n'
    printf 'MaxAuthTries %s\n' "${SSH_MAX_AUTH_TRIES:-3}"
    printf 'LoginGraceTime %s\n' "${SSH_LOGIN_GRACE_TIME:-30}"
    printf 'ClientAliveInterval %s\n' "${SSH_CLIENT_ALIVE_INTERVAL:-300}"
    printf 'ClientAliveCountMax %s\n' "${SSH_CLIENT_ALIVE_COUNT_MAX:-2}"
    printf 'UsePAM yes\n'
    printf 'LogLevel VERBOSE\n'
    printf '# Protocol 2 is implicit in modern OpenSSH and is not set to avoid unsupported directives.\n'
    printf '# END DEBIAN13-WEB-HARDENING\n'
  } > "$tmp"

  install_file_if_changed "$tmp" "$dropin" 0644

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    rm -f "$tmp" "$previous"
    report_add_recommendation "Dry run only: run without --dry-run to apply SSH hardening."
    return 0
  fi

  if sshd -t; then
    log_success "SSH configuration test passed"
  else
    log_error "SSH configuration test failed; reverting ${dropin}"
    if [[ "$existed" == "true" ]]; then
      cp -a "$previous" "$dropin"
    else
      rm -f "$dropin"
    fi
    rm -f "$tmp" "$previous"
    return 1
  fi

  if systemctl reload ssh >/dev/null 2>&1; then
    log_success "Reloaded ssh service"
  elif systemctl reload sshd >/dev/null 2>&1; then
    log_success "Reloaded sshd service"
  else
    log_warn "Could not reload SSH service automatically; configuration was validated"
    report_add_recommendation "Reload SSH manually after verifying service name: systemctl reload ssh"
  fi

  report_add_firewall_rule "Keep SSH allowed on detected port ${ssh_port}"
  report_add_recommendation "Open a second SSH session and verify login before closing the current session."
  rm -f "$tmp" "$previous"
}

