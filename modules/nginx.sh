#!/usr/bin/env bash
set -Eeuo pipefail

run_nginx_hardening() {
  log_section "Nginx hardening"
  report_add_module "nginx"

  if ! command_exists nginx && [[ ! -d /etc/nginx ]]; then
    if [[ "${NGINX_INSTALL_IF_MISSING:-true}" == "true" ]]; then
      log_warn "Nginx is not installed; installing Nginx because NGINX_INSTALL_IF_MISSING=true"
      if ((${#NGINX_TOOL_PACKAGES[@]} > 0)); then
        install_available_packages "${NGINX_TOOL_PACKAGES[@]}"
      else
        install_available_packages nginx
      fi
      if [[ "${DRY_RUN:-false}" != "true" ]] && ! command_exists nginx && [[ ! -d /etc/nginx ]]; then
        log_error "Nginx installation did not make nginx available; skipping Nginx hardening"
        report_add_recommendation "Nginx hardening was skipped because nginx could not be installed or detected."
        return 1
      fi
    else
      log_warn "Nginx is not installed; skipping Nginx hardening"
      report_add_recommendation "Install Nginx before running the Nginx hardening module, or set NGINX_INSTALL_IF_MISSING=true."
      return 0
    fi
  fi

  local headers_snippet hardening_snippet global_conf tmp_headers tmp_hardening tmp_global rollback_dir changed
  headers_snippet="/etc/nginx/snippets/security-headers.conf"
  hardening_snippet="/etc/nginx/snippets/hardening.conf"
  global_conf="/etc/nginx/conf.d/debian13-hardening.conf"
  tmp_headers="$(mktemp)"
  tmp_hardening="$(mktemp)"
  tmp_global="$(mktemp)"
  rollback_dir="$(mktemp -d)"
  changed="false"

  {
    printf '# Managed by debian13-web-hardening. Include inside server blocks.\n'
    printf 'add_header X-Frame-Options "SAMEORIGIN" always;\n'
    printf 'add_header X-Content-Type-Options "nosniff" always;\n'
    printf 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;\n'
    printf 'add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;\n'
    printf '# Consider enabling a tested CSP per application:\n'
    printf '# add_header Content-Security-Policy "default-src '\''self'\''" always;\n'
  } > "$tmp_headers"

  {
    printf '# Managed by debian13-web-hardening. Include inside server blocks.\n'
    printf 'server_tokens off;\n'
    printf 'client_max_body_size %s;\n' "${NGINX_CLIENT_MAX_BODY_SIZE:-10m}"
    printf 'client_body_timeout 15s;\n'
    printf 'client_header_timeout 15s;\n'
    printf 'keepalive_timeout 65s;\n'
    printf 'send_timeout 30s;\n'
    printf 'location ~ /\\.(env|git|svn) { deny all; return 404; }\n'
    printf 'location ~ /\\.ht { deny all; return 404; }\n'
    printf 'location ~* \\.(bak|old|orig|save|swp|tmp)$ { deny all; return 404; }\n'
  } > "$tmp_hardening"

  {
    printf '# Managed by debian13-web-hardening. Loaded in nginx http context.\n'
    printf 'client_max_body_size %s;\n' "${NGINX_CLIENT_MAX_BODY_SIZE:-10m}"
    printf 'client_body_timeout 15s;\n'
    printf 'client_header_timeout 15s;\n'
    printf 'send_timeout 30s;\n'
    printf 'gzip_vary on;\n'
    printf 'add_header X-Frame-Options "SAMEORIGIN" always;\n'
    printf 'add_header X-Content-Type-Options "nosniff" always;\n'
    printf 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;\n'
    printf 'add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;\n'
  } > "$tmp_global"

  if [[ -e "$headers_snippet" ]]; then cp -a "$headers_snippet" "${rollback_dir}/security-headers.conf"; fi
  if [[ -e "$hardening_snippet" ]]; then cp -a "$hardening_snippet" "${rollback_dir}/hardening.conf"; fi
  if [[ -e "$global_conf" ]]; then cp -a "$global_conf" "${rollback_dir}/debian13-hardening.conf"; fi

  install_file_with_backup_if_changed "$tmp_headers" "$headers_snippet" 0644
  [[ "$LAST_FILE_CHANGED" == "true" ]] && changed="true"
  install_file_with_backup_if_changed "$tmp_hardening" "$hardening_snippet" 0644
  [[ "$LAST_FILE_CHANGED" == "true" ]] && changed="true"
  install_file_with_backup_if_changed "$tmp_global" "$global_conf" 0644
  [[ "$LAST_FILE_CHANGED" == "true" ]] && changed="true"

  rm -f "$tmp_headers" "$tmp_hardening" "$tmp_global"

  if [[ "$changed" != "true" ]]; then
    log_success "Nginx hardening already configured; no reload needed"
    rm -rf "$rollback_dir"
    return 0
  fi

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    if ! nginx -t; then
      log_error "Nginx configuration test failed; restoring previous Nginx hardening files"
      if [[ -e "${rollback_dir}/security-headers.conf" ]]; then cp -a "${rollback_dir}/security-headers.conf" "$headers_snippet"; else rm -f "$headers_snippet"; fi
      if [[ -e "${rollback_dir}/hardening.conf" ]]; then cp -a "${rollback_dir}/hardening.conf" "$hardening_snippet"; else rm -f "$hardening_snippet"; fi
      if [[ -e "${rollback_dir}/debian13-hardening.conf" ]]; then cp -a "${rollback_dir}/debian13-hardening.conf" "$global_conf"; else rm -f "$global_conf"; fi
      rm -rf "$rollback_dir"
      report_add_recommendation "Nginx hardening files were restored because nginx -t failed."
      return 1
    fi
    log_success "Nginx configuration test passed"
    if service_is_active nginx; then
      run_cmd systemctl reload nginx
    else
      log_warn "Nginx service is not active; configuration was written but not reloaded"
    fi
  fi

  rm -rf "$rollback_dir"
  report_add_recommendation "For each Nginx server block, include snippets/security-headers.conf and snippets/hardening.conf after application testing."
}
