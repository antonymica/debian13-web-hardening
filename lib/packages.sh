#!/usr/bin/env bash
set -Eeuo pipefail

APT_UPDATED="${APT_UPDATED:-false}"

apt_update_once() {
  if [[ "$APT_UPDATED" == "true" ]]; then
    return 0
  fi
  run_cmd apt-get update
  APT_UPDATED="true"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

install_packages() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    if package_installed "$pkg"; then
      log_info "Package already installed: ${pkg}"
    else
      missing+=("$pkg")
    fi
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  apt_update_once
  log_info "Installing packages: ${missing[*]}"
  run_cmd apt-get install -y "${missing[@]}"
}

install_package_if_available() {
  local pkg="$1"
  apt_update_once
  if package_available "$pkg"; then
    install_packages "$pkg"
    return 0
  fi
  log_warn "Package not available in configured APT repositories: ${pkg}"
  report_add_recommendation "Package ${pkg} was not available from APT repositories."
  return 1
}

