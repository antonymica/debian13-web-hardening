#!/usr/bin/env bash
set -Eeuo pipefail

run_waf_hardening() {
  log_section "WAF: ModSecurity and OWASP CRS"
  report_add_module "waf"
  log_warn "ModSecurity can create false positives. DetectionOnly is safest until rules are tuned."

  local mode conf tmp apache_present nginx_present
  mode="${WAF_MODE:-DetectionOnly}"
  if [[ "$mode" == "On" && "${ASSUME_YES:-false}" != "true" ]]; then
    if ! confirm "Enable ModSecurity blocking mode?"; then
      mode="DetectionOnly"
      log_warn "Falling back to DetectionOnly mode"
    fi
  fi

  apache_present="false"
  nginx_present="false"
  if [[ "${APACHE_ENABLED:-false}" == "true" ]] && { command_exists apachectl || [[ -d /etc/apache2 ]]; }; then
    apache_present="true"
  fi
  if command_exists nginx || [[ -d /etc/nginx ]]; then
    nginx_present="true"
  fi

  if [[ "$apache_present" == "false" && "$nginx_present" == "false" ]]; then
    log_warn "No supported web server detected for WAF configuration"
    report_add_recommendation "Install Nginx before enabling ModSecurity/OWASP CRS, or set APACHE_ENABLED=true if this server intentionally uses Apache."
    return 0
  fi

  install_package_if_available modsecurity-crs || true
  conf="/etc/modsecurity/debian13-hardening.conf"
  tmp="$(mktemp)"
  backup_file "$conf"

  {
    printf '# Managed by debian13-web-hardening.\n'
    printf 'SecRuleEngine %s\n' "$mode"
    printf 'SecRequestBodyAccess On\n'
    printf 'SecAuditEngine RelevantOnly\n'
    printf 'SecAuditLogParts ABIJDEFHZ\n'
    printf 'SecResponseBodyAccess Off\n'
  } > "$tmp"

  install_file_if_changed "$tmp" "$conf" 0644
  rm -f "$tmp"

  if [[ "$apache_present" == "true" ]]; then
    install_package_if_available libapache2-mod-security2 || true
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      run_cmd a2enmod security2
      apachectl configtest
      if service_is_active apache2; then
        run_cmd systemctl reload apache2
      else
        log_warn "Apache service is not active; WAF configuration was written but not reloaded"
      fi
    fi
    log_success "Apache ModSecurity configured in ${mode} mode"
  fi

  if [[ "$nginx_present" == "true" ]]; then
    if install_package_if_available libnginx-mod-http-modsecurity; then
      local nginx_snippet nginx_tmp
      nginx_snippet="/etc/nginx/snippets/modsecurity.conf"
      nginx_tmp="$(mktemp)"
      backup_file "$nginx_snippet"
      {
        printf '# Managed by debian13-web-hardening. Include inside server blocks after testing.\n'
        printf 'modsecurity on;\n'
        printf 'modsecurity_rules_file %s;\n' "$conf"
      } > "$nginx_tmp"
      install_file_if_changed "$nginx_tmp" "$nginx_snippet" 0644
      rm -f "$nginx_tmp"
      report_add_recommendation "Include snippets/modsecurity.conf in tested Nginx server blocks to enable WAF protection."
    fi
  fi

  report_add_recommendation "Review ModSecurity audit logs and tune exclusions before relying on blocking mode."
}
