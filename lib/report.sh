#!/usr/bin/env bash
set -Eeuo pipefail

REPORT_DIR="${REPORT_DIR:-/var/log/debian13-hardening/reports}"
REPORT_FILE="${REPORT_FILE:-}"
WEB_REPORT_FILE="${WEB_REPORT_FILE:-/var/www/html/hardening.html}"

REPORT_MODULES=()
REPORT_MODIFIED_FILES=()
REPORT_ALREADY_CONFIGURED=()
REPORT_BACKUPS=()
REPORT_FIREWALL_RULES=()
REPORT_DISABLED_SERVICES=()
REPORT_RECOMMENDATIONS=()
REPORT_ROLLBACK_COMMANDS=()
REPORT_ROLLBACK_ACTIONS=()

HARDENING_CHANGED="${HARDENING_CHANGED:-false}"
HARDENING_STATUS="${HARDENING_STATUS:-No changes recorded yet}"

init_report() {
  if [[ -z "${REPORT_FILE:-}" ]]; then
    if [[ "${REPORT_HISTORY_ENABLED:-false}" == "true" ]]; then
      REPORT_FILE="${REPORT_DIR}/hardening-report-${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}.md"
    else
      REPORT_FILE="${REPORT_DIR}/hardening-report-latest.md"
    fi
  fi
  mkdir -p "$REPORT_DIR"
  chmod 0750 "$REPORT_DIR"
}

_report_add_unique() {
  local array_name="$1"
  local value="$2"
  local current
  local -n report_array="$array_name"
  for current in "${report_array[@]+"${report_array[@]}"}"; do
    if [[ "$current" == "$value" ]]; then
      return 0
    fi
  done
  report_array+=("$value")
}

report_add_module() {
  _report_add_unique REPORT_MODULES "$1"
}

report_add_modified_file() {
  HARDENING_CHANGED="true"
  HARDENING_STATUS="Changes applied"
  _report_add_unique REPORT_MODIFIED_FILES "$1"
}

report_add_already_configured() {
  _report_add_unique REPORT_ALREADY_CONFIGURED "$1"
}

report_add_backup() {
  _report_add_unique REPORT_BACKUPS "$1"
}

report_add_firewall_rule() {
  _report_add_unique REPORT_FIREWALL_RULES "$1"
}

report_add_disabled_service() {
  _report_add_unique REPORT_DISABLED_SERVICES "$1"
}

report_add_recommendation() {
  _report_add_unique REPORT_RECOMMENDATIONS "$1"
}

report_add_rollback_command() {
  _report_add_unique REPORT_ROLLBACK_COMMANDS "$1"
}

report_add_rollback_action() {
  HARDENING_CHANGED="true"
  HARDENING_STATUS="Rollback completed"
  _report_add_unique REPORT_ROLLBACK_ACTIONS "$1"
}

report_mark_changed() {
  HARDENING_CHANGED="true"
  HARDENING_STATUS="${1:-Changes applied}"
}

report_mark_no_changes_if_needed() {
  if [[ "$HARDENING_CHANGED" != "true" ]]; then
    HARDENING_STATUS="Already compliant - no changes required"
  fi
}

_markdown_list() {
  local item
  local wrote="false"
  if (($# == 0)); then
    printf -- '- None recorded\n'
    return 0
  fi
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    printf -- '- %s\n' "$item"
    wrote="true"
  done
  if [[ "$wrote" != "true" ]]; then
    printf -- '- None recorded\n'
  fi
}

html_escape() {
  local value="$*"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&#39;}"
  printf '%s' "$value"
}

_html_list() {
  local item
  local wrote="false"
  printf '<ul>\n'
  if (($# > 0)); then
    for item in "$@"; do
      [[ -n "$item" ]] || continue
      printf '<li>%s</li>\n' "$(html_escape "$item")"
      wrote="true"
    done
  fi
  if [[ "$wrote" != "true" ]]; then
    printf '<li class="muted">None recorded</li>\n'
  fi
  printf '</ul>\n'
}

generate_html_report() {
  if [[ "${WEB_REPORT_ENABLED:-true}" != "true" ]]; then
    log_info "Web report generation is disabled"
    return 0
  fi

  local hostname debian_version public_ip provider status_class html_tmp web_dir
  hostname="$(hostname -f 2>/dev/null || hostname)"
  debian_version="$(get_debian_version 2>/dev/null || printf 'Unknown')"
  public_ip="$(get_public_ip 2>/dev/null || printf 'Unavailable')"
  provider="$(detect_cloud_provider 2>/dev/null || printf 'Unknown')"
  html_tmp="$(mktemp)"
  web_dir="$(dirname "$WEB_REPORT_FILE")"
  status_class="ok"
  if [[ "$HARDENING_CHANGED" == "true" ]]; then
    status_class="changed"
  fi

  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n'
    printf '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Debian 13 Hardening Report</title>\n'
    printf '<style>\n'
    printf ':root{color-scheme:light dark;--bg:#0f172a;--panel:#111827;--panel2:#1f2937;--text:#e5e7eb;--muted:#9ca3af;--ok:#22c55e;--warn:#f59e0b;--line:#334155;--accent:#38bdf8}*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(135deg,#0f172a,#111827 55%%,#0b1120);color:var(--text)}main{width:min(1180px,92vw);margin:0 auto;padding:36px 0 56px}.top{display:flex;justify-content:space-between;gap:24px;align-items:flex-start;margin-bottom:28px}.eyebrow{color:var(--accent);font-weight:700;text-transform:uppercase;font-size:12px;letter-spacing:.08em}h1{margin:.25rem 0 0;font-size:clamp(30px,5vw,54px);line-height:1.05}p{color:var(--muted)}.status{border:1px solid var(--line);background:rgba(17,24,39,.78);border-radius:8px;padding:16px;min-width:260px}.badge{display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:999px;font-weight:700}.badge.ok{background:rgba(34,197,94,.14);color:#86efac}.badge.changed{background:rgba(245,158,11,.16);color:#fcd34d}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:24px 0}.metric,.card{background:rgba(17,24,39,.82);border:1px solid var(--line);border-radius:8px;padding:16px}.metric span{display:block;color:var(--muted);font-size:12px;text-transform:uppercase}.metric strong{display:block;margin-top:6px;font-size:15px;overflow-wrap:anywhere}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.card h2{font-size:18px;margin:0 0 10px}.card ul{margin:0;padding-left:20px}.card li{margin:7px 0;color:#d1d5db;overflow-wrap:anywhere}.muted{color:var(--muted)!important}.footer{margin-top:24px;color:var(--muted);font-size:13px}@media(max-width:900px){.top,.cards{display:block}.status{margin-top:16px}.grid{grid-template-columns:1fr 1fr}.card{margin-bottom:16px}}@media(max-width:520px){.grid{grid-template-columns:1fr}}\n'
    printf '</style>\n</head>\n<body>\n<main>\n'
    printf '<section class="top"><div><div class="eyebrow">Debian 13 Web Hardening</div><h1>Security Report</h1><p>Latest generated host hardening status.</p></div>'
    printf '<aside class="status"><div class="badge %s">%s</div><p>%s</p></aside></section>\n' "$status_class" "$(html_escape "$HARDENING_STATUS")" "$(html_escape "Generated on $(date '+%Y-%m-%d %H:%M:%S %Z')")"
    printf '<section class="grid">\n'
    printf '<div class="metric"><span>Hostname</span><strong>%s</strong></div>\n' "$(html_escape "$hostname")"
    printf '<div class="metric"><span>Public IP</span><strong>%s</strong></div>\n' "$(html_escape "$public_ip")"
    printf '<div class="metric"><span>Cloud provider</span><strong>%s</strong></div>\n' "$(html_escape "$provider")"
    printf '<div class="metric"><span>Debian version</span><strong>%s</strong></div>\n' "$(html_escape "$debian_version")"
    printf '</section>\n<section class="cards">\n'
    printf '<article class="card"><h2>Modules executed</h2>'
    _html_list "${REPORT_MODULES[@]+"${REPORT_MODULES[@]}"}"
    printf '</article>\n<article class="card"><h2>Already configured</h2>'
    _html_list "${REPORT_ALREADY_CONFIGURED[@]+"${REPORT_ALREADY_CONFIGURED[@]}"}"
    printf '</article>\n<article class="card"><h2>Files modified</h2>'
    _html_list "${REPORT_MODIFIED_FILES[@]+"${REPORT_MODIFIED_FILES[@]}"}"
    printf '</article>\n<article class="card"><h2>Backups created</h2>'
    _html_list "${REPORT_BACKUPS[@]+"${REPORT_BACKUPS[@]}"}"
    printf '</article>\n<article class="card"><h2>Firewall rules</h2>'
    _html_list "${REPORT_FIREWALL_RULES[@]+"${REPORT_FIREWALL_RULES[@]}"}"
    printf '</article>\n<article class="card"><h2>Services disabled</h2>'
    _html_list "${REPORT_DISABLED_SERVICES[@]+"${REPORT_DISABLED_SERVICES[@]}"}"
    printf '</article>\n<article class="card"><h2>Rollback actions</h2>'
    _html_list "${REPORT_ROLLBACK_ACTIONS[@]+"${REPORT_ROLLBACK_ACTIONS[@]}"}"
    printf '</article>\n<article class="card"><h2>Recommendations</h2>'
    _html_list "${REPORT_RECOMMENDATIONS[@]+"${REPORT_RECOMMENDATIONS[@]}"}"
    printf '</article>\n</section>\n'
    printf '<p class="footer">Markdown report: %s<br>Log file: %s<br>Backup directory: %s</p>\n' "$(html_escape "$REPORT_FILE")" "$(html_escape "${LOG_FILE:-Unavailable}")" "$(html_escape "${BACKUP_DIR:-No new backup directory}")"
    printf '</main>\n</body>\n</html>\n'
  } > "$html_tmp"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] would publish web report to ${WEB_REPORT_FILE}"
    rm -f "$html_tmp"
    return 0
  fi

  mkdir -p "$web_dir"
  install -m 0644 "$html_tmp" "$WEB_REPORT_FILE"
  rm -f "$html_tmp"
  log_success "Web report written to ${WEB_REPORT_FILE}"
}

generate_report() {
  local hostname debian_version public_ip provider
  report_mark_no_changes_if_needed
  hostname="$(hostname -f 2>/dev/null || hostname)"
  debian_version="$(get_debian_version 2>/dev/null || printf 'Unknown')"
  public_ip="$(get_public_ip 2>/dev/null || printf 'Unavailable')"
  provider="$(detect_cloud_provider 2>/dev/null || printf 'Unknown')"

  {
    printf '# Debian 13 Web Hardening Report\n\n'
    printf -- '- Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf -- '- Status: %s\n' "$HARDENING_STATUS"
    printf -- '- Hostname: %s\n' "$hostname"
    printf -- '- Public IP: %s\n' "$public_ip"
    printf -- '- Cloud provider: %s\n' "$provider"
    printf -- '- Debian version: %s\n' "$debian_version"
    printf -- '- Log file: %s\n' "$LOG_FILE"
    printf -- '- Backup directory: %s\n\n' "${BACKUP_DIR:-Not initialized}"

    printf '## Modules executed\n\n'
    _markdown_list "${REPORT_MODULES[@]+"${REPORT_MODULES[@]}"}"
    printf '\n## Already configured\n\n'
    _markdown_list "${REPORT_ALREADY_CONFIGURED[@]+"${REPORT_ALREADY_CONFIGURED[@]}"}"
    printf '\n## Files modified\n\n'
    _markdown_list "${REPORT_MODIFIED_FILES[@]+"${REPORT_MODIFIED_FILES[@]}"}"
    printf '\n## Backups created\n\n'
    _markdown_list "${REPORT_BACKUPS[@]+"${REPORT_BACKUPS[@]}"}"
    printf '\n## Firewall rules applied\n\n'
    _markdown_list "${REPORT_FIREWALL_RULES[@]+"${REPORT_FIREWALL_RULES[@]}"}"
    printf '\n## Services disabled\n\n'
    _markdown_list "${REPORT_DISABLED_SERVICES[@]+"${REPORT_DISABLED_SERVICES[@]}"}"
    printf '\n## Rollback actions\n\n'
    _markdown_list "${REPORT_ROLLBACK_ACTIONS[@]+"${REPORT_ROLLBACK_ACTIONS[@]}"}"
    printf '\n## Remaining recommendations\n\n'
    _markdown_list "${REPORT_RECOMMENDATIONS[@]+"${REPORT_RECOMMENDATIONS[@]}"}"
    printf '\n## Rollback commands\n\n'
    _markdown_list "${REPORT_ROLLBACK_COMMANDS[@]+"${REPORT_ROLLBACK_COMMANDS[@]}"}"
  } > "$REPORT_FILE"

  chmod 0640 "$REPORT_FILE"
  log_success "Security report written to ${REPORT_FILE}"
  generate_html_report
}
