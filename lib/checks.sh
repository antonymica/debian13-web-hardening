#!/usr/bin/env bash
set -Eeuo pipefail

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf 'This script must be run as root. Use: sudo ./harden.sh\n' >&2
    exit 1
  fi
}

get_debian_version() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s %s' "${PRETTY_NAME:-Debian}" "${VERSION_ID:-unknown}"
    return 0
  fi
  printf 'Unknown'
}

require_debian_13_or_warn() {
  if [[ ! -r /etc/os-release ]]; then
    log_warn "/etc/os-release not found; cannot verify Debian version"
    return 0
  fi
  . /etc/os-release
  if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
    log_warn "This project targets Debian 13; detected ${PRETTY_NAME:-unknown OS}"
  else
    log_success "Detected ${PRETTY_NAME}"
  fi
}

detect_gcp() {
  command_exists curl || return 1
  curl -fsS --max-time 1 -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/name" >/dev/null 2>&1
}

detect_cloud_provider() {
  if detect_gcp; then
    printf 'Google Cloud Platform'
    return 0
  fi
  printf 'Unknown'
}

get_public_ip() {
  command_exists curl || {
    printf 'Unavailable'
    return 0
  }
  curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || printf 'Unavailable'
}

detect_ssh_port() {
  local port
  if command_exists sshd; then
    port="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
    if [[ -n "$port" ]]; then
      printf '%s' "$port"
      return 0
    fi
  fi
  port="$(awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null || true)"
  printf '%s' "${port:-22}"
}

validate_tcp_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

resolve_ssh_target_port() {
  local current configured
  current="$(detect_ssh_port)"
  configured="${SSH_PORT:-auto}"
  case "$configured" in
    ""|auto|current)
      printf '%s\n' "$current"
      ;;
    *)
      if validate_tcp_port "$configured"; then
        printf '%s\n' "$configured"
      else
        log_error "Invalid SSH_PORT=${configured}. Use auto/current or a TCP port between 1 and 65535."
        return 1
      fi
      ;;
  esac
}

effective_ssh_ports() {
  local current target port existing
  local ports=()
  current="$(detect_ssh_port)"
  target="$(resolve_ssh_target_port)"

  if [[ "$target" != "$current" && "${SSH_KEEP_CURRENT_PORT_ON_CHANGE:-true}" == "true" ]]; then
    ports+=("$current")
  fi
  ports+=("$target")

  for port in "${SSH_ADDITIONAL_PORTS[@]+"${SSH_ADDITIONAL_PORTS[@]}"}"; do
    [[ -n "$port" ]] || continue
    if ! validate_tcp_port "$port"; then
      log_error "Invalid SSH additional port: ${port}"
      return 1
    fi
    ports+=("$port")
  done

  local unique=()
  for port in "${ports[@]}"; do
    for existing in "${unique[@]+"${unique[@]}"}"; do
      [[ "$existing" == "$port" ]] && continue 2
    done
    unique+=("$port")
  done

  printf '%s\n' "${unique[@]}"
}

detect_admin_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s' "$SUDO_USER"
    return 0
  fi
  if [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
    printf '%s' "$USER"
    return 0
  fi
  printf 'root'
}

user_home_dir() {
  local user="$1"
  getent passwd "$user" | cut -d: -f6
}

has_valid_ssh_public_key() {
  local user="$1"
  local home auth_file
  home="$(user_home_dir "$user" || true)"
  [[ -n "$home" ]] || return 1
  auth_file="${home}/.ssh/authorized_keys"
  [[ -r "$auth_file" ]] || return 1
  grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]]+[A-Za-z0-9+/=]+' "$auth_file"
}

active_ssh_session_detected() {
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]
}

warn_gcp_if_detected() {
  if detect_gcp; then
    log_warn "GCP detected: verify GCP VPC firewall rules, OS Login, and metadata-managed SSH keys separately."
    report_add_recommendation "On GCP, verify VPC firewall rules and OS Login/SSH key policy outside the host firewall."
  fi
}
