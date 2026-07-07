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
    [[ -n "$pkg" ]] || continue
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

install_available_packages() {
  local missing=()
  local pkg

  if (($# == 0)); then
    return 0
  fi

  apt_update_once
  for pkg in "$@"; do
    [[ -n "$pkg" ]] || continue
    if package_installed "$pkg"; then
      log_info "Package already installed: ${pkg}"
    elif package_available "$pkg"; then
      missing+=("$pkg")
    else
      log_warn "Package not available in configured APT repositories: ${pkg}"
      report_add_recommendation "Package ${pkg} was not available from APT repositories."
    fi
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  log_info "Installing available packages: ${missing[*]}"
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

install_launch_prerequisites() {
  if [[ "${AUTO_INSTALL_PREREQUISITES:-true}" != "true" ]]; then
    log_warn "Startup prerequisite installation is disabled"
    report_add_recommendation "Startup prerequisite installation was disabled."
    return 0
  fi

  log_section "Startup prerequisites"
  report_add_module "prerequisites"

  if ! command_exists apt-get || ! command_exists dpkg-query || ! command_exists apt-cache; then
    log_error "APT tooling is required on Debian: apt-get, apt-cache and dpkg-query must be available."
    return 1
  fi

  install_available_packages "${PREREQUISITE_PACKAGES[@]+"${PREREQUISITE_PACKAGES[@]}"}"
  log_success "Startup prerequisites checked"
}

install_security_tools_bundle() {
  log_section "Security tool installation"
  report_add_module "security-tools"

  if ! command_exists apt-get || ! command_exists dpkg-query || ! command_exists apt-cache; then
    log_error "APT tooling is required to install security tools."
    return 1
  fi

  install_available_packages "${SECURITY_TOOL_PACKAGES[@]+"${SECURITY_TOOL_PACKAGES[@]}"}"

  if [[ "${NGINX_ONLY:-true}" == "true" && "${NGINX_INSTALL_IF_MISSING:-true}" == "true" ]]; then
    install_available_packages "${NGINX_TOOL_PACKAGES[@]+"${NGINX_TOOL_PACKAGES[@]}"}"
  fi

  install_available_packages "${WAF_TOOL_PACKAGES[@]+"${WAF_TOOL_PACKAGES[@]}"}"

  local pkg
  for pkg in "${OPTIONAL_SECURITY_PACKAGES[@]+"${OPTIONAL_SECURITY_PACKAGES[@]}"}"; do
    [[ -n "$pkg" ]] || continue
    install_package_if_available "$pkg" || true
  done

  log_success "Security tool installation completed"
}
