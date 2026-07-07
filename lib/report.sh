#!/usr/bin/env bash
set -Eeuo pipefail

REPORT_DIR="${REPORT_DIR:-/var/log/debian13-hardening/reports}"
REPORT_FILE="${REPORT_FILE:-}"
WEB_REPORT_FILE="${WEB_REPORT_FILE:-/var/www/html/hardening.html}"
WEB_REPORT_JSON_FILE="${WEB_REPORT_JSON_FILE:-/var/www/html/hardening-status.json}"
WEB_REPORT_REFRESH_SECONDS="${WEB_REPORT_REFRESH_SECONDS:-5}"
WEB_REPORT_LOG_LINES="${WEB_REPORT_LOG_LINES:-120}"
WEB_REPORT_RUNNING="${WEB_REPORT_RUNNING:-false}"

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
REPORT_HOSTNAME=""
REPORT_PUBLIC_IP=""
REPORT_PROVIDER=""
REPORT_DEBIAN_VERSION=""

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
  WEB_REPORT_RUNNING="true"
  report_refresh_metadata
  generate_html_report "true"
  publish_web_status "INIT" "Report initialized" "true" || true
}

report_refresh_metadata() {
  if [[ -n "$REPORT_HOSTNAME" ]]; then
    return 0
  fi
  REPORT_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
  REPORT_DEBIAN_VERSION="$(get_debian_version 2>/dev/null || printf 'Unknown')"
  REPORT_PUBLIC_IP="$(get_public_ip 2>/dev/null || printf 'Unavailable')"
  REPORT_PROVIDER="$(detect_cloud_provider 2>/dev/null || printf 'Unknown')"
}

report_publish_update() {
  if [[ "${WEB_REPORT_LIVE_ENABLED:-true}" == "true" ]]; then
    publish_web_status "STATUS" "$HARDENING_STATUS" "${WEB_REPORT_RUNNING:-true}" || true
  fi
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
  report_publish_update
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
  report_publish_update
}

report_mark_no_changes_if_needed() {
  if [[ "$HARDENING_CHANGED" != "true" ]]; then
    HARDENING_STATUS="Already compliant - no changes required"
  fi
  report_publish_update
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

json_escape() {
  local value="$*"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
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

_json_array() {
  local item
  local first="true"
  printf '['
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    if [[ "$first" != "true" ]]; then
      printf ','
    fi
    printf '"%s"' "$(json_escape "$item")"
    first="false"
  done
  printf ']'
}

_json_log_tail() {
  local line
  local first="true"
  printf '['
  if [[ -r "${LOG_FILE:-}" ]]; then
    while IFS= read -r line; do
      if [[ "$first" != "true" ]]; then
        printf ','
      fi
      printf '"%s"' "$(json_escape "$line")"
      first="false"
    done < <(tail -n "${WEB_REPORT_LOG_LINES:-120}" "$LOG_FILE" 2>/dev/null || true)
  fi
  printf ']'
}

_json_report_history() {
  local report
  local first="true"
  printf '['
  if [[ -d "$REPORT_DIR" ]]; then
    while IFS= read -r report; do
      if [[ "$first" != "true" ]]; then
        printf ','
      fi
      printf '"%s"' "$(json_escape "$report")"
      first="false"
    done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort -r || true)
  fi
  printf ']'
}

publish_web_status() {
  local event_level="${1:-STATUS}"
  local event_message="${2:-}"
  local running="${3:-${WEB_REPORT_RUNNING:-true}}"
  local web_dir json_tmp now changed_json running_json

  if [[ "${WEB_REPORT_ENABLED:-true}" != "true" || "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  if [[ "${PUBLISHING_WEB_STATUS:-false}" == "true" ]]; then
    return 0
  fi

  PUBLISHING_WEB_STATUS="true"
  report_refresh_metadata
  web_dir="$(dirname "$WEB_REPORT_JSON_FILE")"
  mkdir -p "$web_dir" 2>/dev/null || {
    PUBLISHING_WEB_STATUS="false"
    return 0
  }

  now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  changed_json="false"
  running_json="false"
  [[ "$HARDENING_CHANGED" == "true" ]] && changed_json="true"
  [[ "$running" == "true" ]] && running_json="true"
  json_tmp="$(mktemp)"

  {
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(json_escape "$now")"
    printf '  "running": %s,\n' "$running_json"
    printf '  "changed": %s,\n' "$changed_json"
    printf '  "status": "%s",\n' "$(json_escape "$HARDENING_STATUS")"
    printf '  "last_event": {"level": "%s", "message": "%s"},\n' "$(json_escape "$event_level")" "$(json_escape "$event_message")"
    printf '  "host": {"hostname": "%s", "public_ip": "%s", "provider": "%s", "debian_version": "%s"},\n' \
      "$(json_escape "$REPORT_HOSTNAME")" "$(json_escape "$REPORT_PUBLIC_IP")" "$(json_escape "$REPORT_PROVIDER")" "$(json_escape "$REPORT_DEBIAN_VERSION")"
    printf '  "paths": {"markdown_report": "%s", "log_file": "%s", "backup_dir": "%s", "html_report": "%s"},\n' \
      "$(json_escape "${REPORT_FILE:-}")" "$(json_escape "${LOG_FILE:-}")" "$(json_escape "${BACKUP_DIR:-}")" "$(json_escape "$WEB_REPORT_FILE")"
    printf '  "modules": '
    _json_array "${REPORT_MODULES[@]+"${REPORT_MODULES[@]}"}"
    printf ',\n  "already_configured": '
    _json_array "${REPORT_ALREADY_CONFIGURED[@]+"${REPORT_ALREADY_CONFIGURED[@]}"}"
    printf ',\n  "modified_files": '
    _json_array "${REPORT_MODIFIED_FILES[@]+"${REPORT_MODIFIED_FILES[@]}"}"
    printf ',\n  "backups": '
    _json_array "${REPORT_BACKUPS[@]+"${REPORT_BACKUPS[@]}"}"
    printf ',\n  "firewall_rules": '
    _json_array "${REPORT_FIREWALL_RULES[@]+"${REPORT_FIREWALL_RULES[@]}"}"
    printf ',\n  "disabled_services": '
    _json_array "${REPORT_DISABLED_SERVICES[@]+"${REPORT_DISABLED_SERVICES[@]}"}"
    printf ',\n  "rollback_actions": '
    _json_array "${REPORT_ROLLBACK_ACTIONS[@]+"${REPORT_ROLLBACK_ACTIONS[@]}"}"
    printf ',\n  "recommendations": '
    _json_array "${REPORT_RECOMMENDATIONS[@]+"${REPORT_RECOMMENDATIONS[@]}"}"
    printf ',\n  "rollback_commands": '
    _json_array "${REPORT_ROLLBACK_COMMANDS[@]+"${REPORT_ROLLBACK_COMMANDS[@]}"}"
    printf ',\n  "report_history": '
    _json_report_history
    printf ',\n  "log_tail": '
    _json_log_tail
    printf '\n}\n'
  } > "$json_tmp"

  install -m 0644 "$json_tmp" "$WEB_REPORT_JSON_FILE" 2>/dev/null || true
  rm -f "$json_tmp"
  PUBLISHING_WEB_STATUS="false"
}

generate_html_report() {
  local quiet="${1:-false}"
  local html_tmp web_dir json_url refresh_seconds

  if [[ "${WEB_REPORT_ENABLED:-true}" != "true" ]]; then
    [[ "$quiet" == "true" ]] || log_info "Web report generation is disabled"
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    [[ "$quiet" == "true" ]] || log_info "[dry-run] would publish live web dashboard to ${WEB_REPORT_FILE}"
    return 0
  fi

  web_dir="$(dirname "$WEB_REPORT_FILE")"
  json_url="./$(basename "$WEB_REPORT_JSON_FILE")"
  refresh_seconds="${WEB_REPORT_REFRESH_SECONDS:-5}"
  html_tmp="$(mktemp)"

  mkdir -p "$web_dir"
  cat > "$html_tmp" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Debian 13 Hardening Live Report</title>
<style>
:root{color-scheme:light dark;--bg:#0f172a;--panel:#111827;--panel2:#172033;--text:#e5e7eb;--muted:#9ca3af;--ok:#22c55e;--warn:#f59e0b;--bad:#ef4444;--line:#334155;--accent:#38bdf8}*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(135deg,#0f172a,#111827 55%,#0b1120);color:var(--text)}main{width:min(1220px,92vw);margin:0 auto;padding:34px 0 54px}.top{display:flex;justify-content:space-between;gap:24px;align-items:flex-start;margin-bottom:24px}.eyebrow{color:var(--accent);font-weight:800;text-transform:uppercase;font-size:12px;letter-spacing:.08em}h1{margin:.25rem 0 0;font-size:clamp(30px,5vw,54px);line-height:1.05}p{color:var(--muted)}.status{border:1px solid var(--line);background:rgba(17,24,39,.82);border-radius:8px;padding:16px;min-width:280px}.badge{display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:999px;font-weight:800}.badge.ok{background:rgba(34,197,94,.14);color:#86efac}.badge.changed{background:rgba(245,158,11,.16);color:#fcd34d}.badge.running{background:rgba(56,189,248,.14);color:#7dd3fc}.dot{width:9px;height:9px;border-radius:999px;background:currentColor;box-shadow:0 0 0 6px rgba(56,189,248,.1)}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:24px 0}.metric,.card{background:rgba(17,24,39,.84);border:1px solid var(--line);border-radius:8px;padding:16px}.metric span{display:block;color:var(--muted);font-size:12px;text-transform:uppercase}.metric strong{display:block;margin-top:6px;font-size:15px;overflow-wrap:anywhere}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.card h2{font-size:18px;margin:0 0 10px}.card ul{margin:0;padding-left:20px}.card li{margin:7px 0;color:#d1d5db;overflow-wrap:anywhere}.muted{color:var(--muted)!important}.log{grid-column:1/-1}.log pre{margin:0;max-height:360px;overflow:auto;background:#020617;border:1px solid var(--line);border-radius:8px;padding:14px;color:#cbd5e1;white-space:pre-wrap;font-size:13px}.footer{margin-top:24px;color:var(--muted);font-size:13px}.links a{color:#7dd3fc;text-decoration:none}.links a:hover{text-decoration:underline}@media(max-width:900px){.top,.cards{display:block}.status{margin-top:16px}.grid{grid-template-columns:1fr 1fr}.card{margin-bottom:16px}}@media(max-width:520px){.grid{grid-template-columns:1fr}}
</style>
</head>
<body>
<main>
  <section class="top">
    <div>
      <div class="eyebrow">Debian 13 Web Hardening</div>
      <h1>Live Security Report</h1>
      <p>Auto-refreshing hardening status for this server.</p>
    </div>
    <aside class="status">
      <div id="statusBadge" class="badge running"><span class="dot"></span><span>Loading</span></div>
      <p id="statusText">Waiting for live report data...</p>
      <p class="muted" id="lastUpdate">Last update: unknown</p>
    </aside>
  </section>

  <section class="grid">
    <div class="metric"><span>Hostname</span><strong id="hostname">-</strong></div>
    <div class="metric"><span>Public IP</span><strong id="publicIp">-</strong></div>
    <div class="metric"><span>Cloud provider</span><strong id="provider">-</strong></div>
    <div class="metric"><span>Debian version</span><strong id="debianVersion">-</strong></div>
  </section>

  <section class="cards">
    <article class="card"><h2>Modules executed</h2><ul id="modules"></ul></article>
    <article class="card"><h2>Already configured</h2><ul id="alreadyConfigured"></ul></article>
    <article class="card"><h2>Files modified</h2><ul id="modifiedFiles"></ul></article>
    <article class="card"><h2>Backups created</h2><ul id="backups"></ul></article>
    <article class="card"><h2>Firewall rules</h2><ul id="firewallRules"></ul></article>
    <article class="card"><h2>Services disabled</h2><ul id="disabledServices"></ul></article>
    <article class="card"><h2>Rollback actions</h2><ul id="rollbackActions"></ul></article>
    <article class="card"><h2>Recommendations</h2><ul id="recommendations"></ul></article>
    <article class="card"><h2>Rollback commands</h2><ul id="rollbackCommands"></ul></article>
    <article class="card"><h2>Report history</h2><ul id="reportHistory"></ul></article>
    <article class="card"><h2>Report files</h2><ul id="reportFiles"></ul></article>
    <article class="card log"><h2>Live log tail</h2><pre id="logTail">Waiting for logs...</pre></article>
  </section>

  <p class="footer">Polling <code>${json_url}</code> every ${refresh_seconds}s. This page is generated by debian13-web-hardening.</p>
</main>
<script>
const statusUrl = '${json_url}';
const refreshMs = Math.max(1000, Number('${refresh_seconds}') * 1000);

function text(id, value) {
  document.getElementById(id).textContent = value || '-';
}

function list(id, values) {
  const node = document.getElementById(id);
  node.innerHTML = '';
  const items = Array.isArray(values) ? values.filter(Boolean) : [];
  if (!items.length) {
    const li = document.createElement('li');
    li.className = 'muted';
    li.textContent = 'None recorded';
    node.appendChild(li);
    return;
  }
  for (const value of items) {
    const li = document.createElement('li');
    li.textContent = value;
    node.appendChild(li);
  }
}

function render(data) {
  const badge = document.getElementById('statusBadge');
  badge.className = 'badge ' + (data.running ? 'running' : (data.changed ? 'changed' : 'ok'));
  badge.innerHTML = '<span class="dot"></span><span>' + (data.running ? 'Running' : (data.changed ? 'Changed' : 'Compliant')) + '</span>';
  text('statusText', data.status);
  text('lastUpdate', 'Last update: ' + (data.generated_at || 'unknown'));
  text('hostname', data.host && data.host.hostname);
  text('publicIp', data.host && data.host.public_ip);
  text('provider', data.host && data.host.provider);
  text('debianVersion', data.host && data.host.debian_version);
  list('modules', data.modules);
  list('alreadyConfigured', data.already_configured);
  list('modifiedFiles', data.modified_files);
  list('backups', data.backups);
  list('firewallRules', data.firewall_rules);
  list('disabledServices', data.disabled_services);
  list('rollbackActions', data.rollback_actions);
  list('recommendations', data.recommendations);
  list('rollbackCommands', data.rollback_commands);
  list('reportHistory', data.report_history);
  list('reportFiles', [
    data.paths && data.paths.markdown_report ? 'Markdown: ' + data.paths.markdown_report : '',
    data.paths && data.paths.log_file ? 'Log: ' + data.paths.log_file : '',
    data.paths && data.paths.backup_dir ? 'Backup: ' + data.paths.backup_dir : ''
  ]);
  document.getElementById('logTail').textContent = Array.isArray(data.log_tail) && data.log_tail.length ? data.log_tail.join('\\n') : 'No log lines yet.';
}

async function refresh() {
  try {
    const response = await fetch(statusUrl + '?t=' + Date.now(), {cache: 'no-store'});
    if (!response.ok) throw new Error('HTTP ' + response.status);
    render(await response.json());
  } catch (error) {
    text('statusText', 'Live status is not available yet: ' + error.message);
  }
}

refresh();
setInterval(refresh, refreshMs);
</script>
</body>
</html>
HTML

  install -m 0644 "$html_tmp" "$WEB_REPORT_FILE"
  rm -f "$html_tmp"
  [[ "$quiet" == "true" ]] || log_success "Live web dashboard written to ${WEB_REPORT_FILE}"
}

generate_report() {
  report_mark_no_changes_if_needed
  WEB_REPORT_RUNNING="false"
  publish_web_status "COMPLETE" "$HARDENING_STATUS" "false" || true

  {
    printf '# Debian 13 Web Hardening Report\n\n'
    printf -- '- Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf -- '- Status: %s\n' "$HARDENING_STATUS"
    printf -- '- Hostname: %s\n' "$REPORT_HOSTNAME"
    printf -- '- Public IP: %s\n' "$REPORT_PUBLIC_IP"
    printf -- '- Cloud provider: %s\n' "$REPORT_PROVIDER"
    printf -- '- Debian version: %s\n' "$REPORT_DEBIAN_VERSION"
    printf -- '- Log file: %s\n' "$LOG_FILE"
    printf -- '- Backup directory: %s\n' "${BACKUP_DIR:-Not initialized}"
    printf -- '- Web dashboard: %s\n' "$WEB_REPORT_FILE"
    printf -- '- Live JSON: %s\n\n' "$WEB_REPORT_JSON_FILE"

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
  generate_html_report "false"
  publish_web_status "COMPLETE" "$HARDENING_STATUS" "false" || true
  log_success "Security report written to ${REPORT_FILE}"
}
