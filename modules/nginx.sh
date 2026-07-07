#!/usr/bin/env bash
set -Eeuo pipefail

run_nginx_hardening() {
  log_section "Nginx hardening"
  report_add_module "nginx"

  if ! command_exists nginx && [[ ! -d /etc/nginx ]]; then
    log_warn "Nginx is not installed; skipping Nginx hardening"
    report_add_recommendation "Install Nginx before running the Nginx hardening module."
    return 0
  fi

  local headers_snippet hardening_snippet global_conf tmp_headers tmp_hardening tmp_global
  headers_snippet="/etc/nginx/snippets/security-headers.conf"
  hardening_snippet="/etc/nginx/snippets/hardening.conf"
  global_conf="/etc/nginx/conf.d/debian13-hardening.conf"
  tmp_headers="$(mktemp)"
  tmp_hardening="$(mktemp)"
  tmp_global="$(mktemp)"

  backup_file /etc/nginx/nginx.conf
  backup_file "$headers_snippet"
  backup_file "$hardening_snippet"
  backup_file "$global_conf"

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
    printf 'server_tokens off;\n'
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

  install_file_if_changed "$tmp_headers" "$headers_snippet" 0644
  install_file_if_changed "$tmp_hardening" "$hardening_snippet" 0644
  install_file_if_changed "$tmp_global" "$global_conf" 0644

  rm -f "$tmp_headers" "$tmp_hardening" "$tmp_global"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    nginx -t
    log_success "Nginx configuration test passed"
    if service_is_active nginx; then
      run_cmd systemctl reload nginx
    else
      log_warn "Nginx service is not active; configuration was written but not reloaded"
    fi
  fi

  report_add_recommendation "For each Nginx server block, include snippets/security-headers.conf and snippets/hardening.conf after application testing."
}
