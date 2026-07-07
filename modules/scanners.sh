#!/usr/bin/env bash
set -Eeuo pipefail

_scanner_run() {
  local output="$1"
  local title="$2"
  shift 2
  {
    printf '\n## %s\n\n' "$title"
    printf 'Command: %s\n\n' "$*"
  } >> "$output"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[dry-run] Command not executed.\n' >> "$output"
    log_info "[dry-run] scanner: $*"
    return 0
  fi

  if command_exists "$1"; then
    "$@" >> "$output" 2>&1 || true
  else
    printf 'Command not available: %s\n' "$1" >> "$output"
  fi
}

run_scanners_hardening() {
  log_section "Malware/rootkit/security scanner tools"
  report_add_module "scanners"

  install_packages lynis rkhunter chkrootkit debsums needrestart nmap iproute2
  install_package_if_available trivy || true

  local output
  output="${REPORT_DIR}/security-scanners-${HARDENING_TIMESTAMP}.txt"
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    touch "$output"
    chmod 0640 "$output"
  fi

  _scanner_run "$output" "Lynis quick audit" lynis audit system --quick
  _scanner_run "$output" "Debsums changed files" debsums -s
  _scanner_run "$output" "Listening sockets" ss -tulpn
  _scanner_run "$output" "Localhost nmap scan" nmap -sS -sV -O 127.0.0.1
  _scanner_run "$output" "Rkhunter check" rkhunter --check --sk
  _scanner_run "$output" "Chkrootkit check" chkrootkit

  log_success "Scanner report written to ${output}"
  report_add_modified_file "$output"
  report_add_recommendation "Review scanner findings manually; tools can produce false positives."
}

