#!/usr/bin/env bash
set -Eeuo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_true() {
  [[ "${1:-false}" == "true" || "${1:-false}" == "yes" || "${1:-false}" == "1" ]]
}

run_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] $*"
    return 0
  fi
  log_debug "Running: $*"
  "$@"
}

confirm() {
  local prompt="$1"
  if [[ "${ASSUME_YES:-false}" == "true" ]]; then
    log_info "Auto-confirmed: ${prompt}"
    return 0
  fi
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

ensure_dir() {
  local dir="$1"
  local mode="${2:-0755}"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] would create directory ${dir} with mode ${mode}; no directory is created in dry-run mode"
    return 0
  fi
  mkdir -p "$dir"
  chmod "$mode" "$dir"
}

install_file_if_changed() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"
  local owner="${4:-root:root}"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    log_info "No changes needed for ${dest}"
    return 0
  fi

  report_add_modified_file "$dest"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] install ${src} -> ${dest}"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  install -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$src" "$dest"
  log_success "Updated ${dest}"
}

service_exists() {
  local svc="$1"
  systemctl list-unit-files --type=service --no-legend "${svc}.service" 2>/dev/null | grep -q . \
    || systemctl status "$svc" >/dev/null 2>&1
}

service_is_active() {
  systemctl is-active --quiet "$1" >/dev/null 2>&1
}

reload_first_available_service() {
  local svc
  for svc in "$@"; do
    if service_exists "$svc"; then
      if systemctl reload "$svc" >/dev/null 2>&1; then
        log_success "Reloaded ${svc}"
        return 0
      fi
      if systemctl restart "$svc" >/dev/null 2>&1; then
        log_success "Restarted ${svc}"
        return 0
      fi
      log_warn "Service ${svc} exists but could not be reloaded or restarted"
      return 1
    fi
  done
  log_warn "No matching service found: $*"
  return 1
}

managed_block() {
  local begin="# BEGIN DEBIAN13-WEB-HARDENING"
  local end="# END DEBIAN13-WEB-HARDENING"
  sed "/${begin}/,/${end}/d"
}

append_managed_block() {
  local file="$1"
  local block_file="$2"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    managed_block < "$file" > "$tmp"
  fi
  {
    printf '%s\n' '# BEGIN DEBIAN13-WEB-HARDENING'
    cat "$block_file"
    printf '%s\n' '# END DEBIAN13-WEB-HARDENING'
  } >> "$tmp"
  install_file_if_changed "$tmp" "$file" 0644
  rm -f "$tmp"
}

join_by_comma() {
  local IFS=", "
  printf '%s' "$*"
}
