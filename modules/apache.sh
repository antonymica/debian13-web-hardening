#!/usr/bin/env bash
set -Eeuo pipefail

run_apache_hardening() {
  log_section "Apache hardening"
  report_add_module "apache"

  if ! command_exists apachectl && [[ ! -d /etc/apache2 ]]; then
    log_warn "Apache is not installed; skipping Apache hardening"
    report_add_recommendation "Install Apache before running the Apache hardening module."
    return 0
  fi

  local conf tmp
  conf="/etc/apache2/conf-available/debian13-hardening.conf"
  tmp="$(mktemp)"

  {
    printf '# Managed by debian13-web-hardening.\n'
    printf 'ServerTokens %s\n' "${APACHE_SERVER_TOKENS:-Prod}"
    printf 'ServerSignature Off\n'
    printf 'TraceEnable Off\n'
    printf '<IfModule mod_headers.c>\n'
    printf '  Header always set X-Frame-Options "SAMEORIGIN"\n'
    printf '  Header always set X-Content-Type-Options "nosniff"\n'
    printf '  Header always set Referrer-Policy "strict-origin-when-cross-origin"\n'
    printf '  Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"\n'
    printf '  # Add a tested application-specific Content-Security-Policy before enabling.\n'
    printf '</IfModule>\n'
    printf '<FilesMatch "(^\\.|~$|\\.bak$|\\.old$|\\.orig$|\\.save$|\\.swp$|\\.tmp$)">\n'
    printf '  Require all denied\n'
    printf '</FilesMatch>\n'
    printf '<DirectoryMatch "/\\.(git|svn)">\n'
    printf '  Require all denied\n'
    printf '</DirectoryMatch>\n'
  } > "$tmp"

  if [[ -f "$conf" ]] && cmp -s "$tmp" "$conf"; then
    log_success "Apache hardening already configured"
    report_add_already_configured "$conf"
    rm -f "$tmp"
    return 0
  fi

  backup_file /etc/apache2/apache2.conf
  backup_file "$conf"
  install_file_if_changed "$tmp" "$conf" 0644
  rm -f "$tmp"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd a2enmod headers rewrite
    run_cmd a2enconf debian13-hardening
    apachectl configtest
    log_success "Apache configuration test passed"
    if service_is_active apache2; then
      run_cmd systemctl reload apache2
    else
      log_warn "Apache service is not active; configuration was written but not reloaded"
    fi
  fi
}
