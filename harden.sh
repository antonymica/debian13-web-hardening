#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULE_DIR="${SCRIPT_DIR}/modules"
HARDENING_TIMESTAMP="${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

_bootstrap_error() {
  local line="$1"
  local command="$2"
  printf '[ERROR] Bootstrap failure on line %s: %s\n' "$line" "$command" >&2
}

trap '_bootstrap_error "$LINENO" "$BASH_COMMAND"' ERR

ACTION="menu"
SELECTED_MODULE=""
CLI_PROFILE=""
PROFILE="balanced"
DRY_RUN="false"
ASSUME_YES="false"
DEBUG="false"
RUN_INITIAL_BACKUP="true"
ACTION_EXPLICIT="false"
CLI_INSTALL_SECURITY_TOOLS="false"
CLI_NO_INSTALL_PREREQS="false"
PREFLIGHT_DONE="false"

FIREWALL_EXTRA_TCP_PORTS=()
FIREWALL_EXTRA_UDP_PORTS=()

show_help() {
  cat <<'EOF'
Debian 13 Web Server Hardening

Usage:
  sudo ./harden.sh
  sudo ./harden.sh --menu
  sudo ./harden.sh --all
  sudo ./harden.sh --module ssh
  sudo ./harden.sh --module firewall
  sudo ./harden.sh --profile conservative
  sudo ./harden.sh --profile balanced
  sudo ./harden.sh --profile strict
  sudo ./harden.sh --dry-run
  sudo ./harden.sh --yes
  sudo ./harden.sh --install-tools
  sudo ./harden.sh --no-install-prereqs
  sudo ./harden.sh --initial-backup-only
  sudo ./harden.sh --no-initial-backup
  sudo ./harden.sh --doctor
  sudo ./harden.sh --rollback
  sudo ./harden.sh --report-only
  sudo ./harden.sh --help

Options:
  --menu                  Show interactive menu (default)
  --all                   Run all recommended hardening modules
  --module <name>         Run one module
  --profile <name>        Use conservative, balanced, or strict profile
  --dry-run               Show actions without applying changes
  --yes                   Auto-confirm prompts
  --install-tools         Install recommended security tooling
  --no-install-prereqs    Skip startup prerequisite installation
  --initial-backup-only   Create the initial configuration backup and exit
  --no-initial-backup     Skip initial baseline backup for this run
  --doctor                Run local diagnostics without changing the system
  --rollback              Restore files from a previous backup
  --report-only           Generate report only
  --debug                 Enable debug logs
  --help                  Show this help

Modules:
  ssh firewall fail2ban kernel services updates nginx waf auditd apparmor scanners
  apache is optional and disabled by default. Set APACHE_ENABLED=true to use it.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --menu)
        ACTION="menu"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --all)
        ACTION="all"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --module)
        if [[ -z "${2:-}" ]]; then
          printf 'Missing value for --module\n' >&2
          exit 2
        fi
        ACTION="module"
        ACTION_EXPLICIT="true"
        SELECTED_MODULE="$2"
        shift 2
        ;;
      --profile)
        if [[ -z "${2:-}" ]]; then
          printf 'Missing value for --profile\n' >&2
          exit 2
        fi
        CLI_PROFILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --yes)
        ASSUME_YES="true"
        shift
        ;;
      --install-tools)
        CLI_INSTALL_SECURITY_TOOLS="true"
        if [[ "$ACTION_EXPLICIT" != "true" ]]; then
          ACTION="install-tools"
        fi
        shift
        ;;
      --no-install-prereqs)
        CLI_NO_INSTALL_PREREQS="true"
        shift
        ;;
      --initial-backup-only)
        ACTION="initial-backup-only"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --no-initial-backup)
        RUN_INITIAL_BACKUP="false"
        shift
        ;;
      --doctor)
        ACTION="doctor"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --rollback)
        ACTION="rollback"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --report-only)
        ACTION="report-only"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --debug)
        DEBUG="true"
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        show_help >&2
        exit 2
        ;;
    esac
  done
}

load_libraries() {
  # shellcheck source=lib/colors.sh
  source "${LIB_DIR}/colors.sh"
  # shellcheck source=lib/logging.sh
  source "${LIB_DIR}/logging.sh"
  # shellcheck source=lib/report.sh
  source "${LIB_DIR}/report.sh"
  # shellcheck source=lib/utils.sh
  source "${LIB_DIR}/utils.sh"
  # shellcheck source=lib/checks.sh
  source "${LIB_DIR}/checks.sh"
  # shellcheck source=lib/backup.sh
  source "${LIB_DIR}/backup.sh"
  # shellcheck source=lib/packages.sh
  source "${LIB_DIR}/packages.sh"
  # shellcheck source=lib/rollback.sh
  source "${LIB_DIR}/rollback.sh"
}

load_configuration() {
  # shellcheck source=config/hardening.conf
  source "${CONFIG_DIR}/hardening.conf"

  if [[ -n "$CLI_PROFILE" ]]; then
    PROFILE="$CLI_PROFILE"
  fi

  local profile_file="${CONFIG_DIR}/profiles/${PROFILE}.conf"
  if [[ ! -r "$profile_file" ]]; then
    printf 'Unknown or unreadable profile: %s\n' "$PROFILE" >&2
    exit 2
  fi
  # shellcheck source=config/profiles/balanced.conf
  source "$profile_file"

  if [[ "$CLI_INSTALL_SECURITY_TOOLS" == "true" ]]; then
    INSTALL_SECURITY_TOOLS_ON_START="true"
  fi
  if [[ "$CLI_NO_INSTALL_PREREQS" == "true" ]]; then
    AUTO_INSTALL_PREREQUISITES="false"
  fi
}

load_modules() {
  local module_file
  for module_file in "${MODULE_DIR}"/*.sh; do
    # shellcheck source=/dev/null
    source "$module_file"
  done
}

doctor_check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '[OK] %s\n' "$label"
  else
    printf '[WARN] %s\n' "$label"
  fi
}

run_doctor() {
  printf 'Debian 13 hardening doctor\n\n'
  printf 'Script path: %s\n' "$SCRIPT_DIR/harden.sh"
  printf 'Bash: %s\n' "${BASH_VERSION:-unknown}"
  printf 'User: %s\n' "$(id -un 2>/dev/null || printf unknown)"
  printf 'EUID: %s\n' "$EUID"
  printf 'PWD: %s\n' "$(pwd)"
  printf '\n'

  doctor_check "harden.sh is readable" test -r "${SCRIPT_DIR}/harden.sh"
  doctor_check "harden.sh is executable" test -x "${SCRIPT_DIR}/harden.sh"
  doctor_check "config/hardening.conf is readable" test -r "${CONFIG_DIR}/hardening.conf"
  doctor_check "config/profiles/balanced.conf is readable" test -r "${CONFIG_DIR}/profiles/balanced.conf"
  doctor_check "lib directory is readable" test -d "$LIB_DIR"
  doctor_check "modules directory is readable" test -d "$MODULE_DIR"
  doctor_check "main is called at end of harden.sh" grep -q '^main "\$@"$' "${SCRIPT_DIR}/harden.sh"
  doctor_check "bash syntax is valid" bash -n "${SCRIPT_DIR}/harden.sh"
  doctor_check "apt-get is available" command -v apt-get
  doctor_check "apt-cache is available" command -v apt-cache
  doctor_check "dpkg-query is available" command -v dpkg-query

  printf '\nExpected runtime paths:\n'
  printf -- '- Logs: %s\n' "${LOG_DIR:-/var/log/debian13-hardening}"
  printf -- '- Backups: %s\n' "${BACKUP_ROOT:-/var/backups/debian13-hardening}"
  printf '\nIf normal execution is silent, run:\n'
  printf '  sudo bash -x ./harden.sh --help\n'
  printf '  sudo bash -x ./harden.sh --dry-run --initial-backup-only\n'
}

run_module() {
  local module="$1"
  case "$module" in
    ssh)
      run_ssh_hardening
      ;;
    firewall)
      run_firewall_hardening
      ;;
    fail2ban)
      run_fail2ban_hardening
      ;;
    kernel|sysctl)
      run_kernel_hardening
      ;;
    services)
      run_services_hardening
      ;;
    updates)
      run_updates_hardening
      ;;
    nginx)
      run_nginx_hardening
      ;;
    apache)
      if [[ "${APACHE_ENABLED:-false}" == "true" ]]; then
        run_apache_hardening
      else
        log_warn "Apache module is disabled. Set APACHE_ENABLED=true in config/hardening.conf to enable it."
        report_add_recommendation "Apache hardening was skipped because this project is configured for Nginx-only servers."
      fi
      ;;
    waf)
      run_waf_hardening
      ;;
    auditd|audit)
      run_auditd_hardening
      ;;
    apparmor)
      run_apparmor_hardening
      ;;
    scanners|scanner)
      run_scanners_hardening
      ;;
    *)
      log_error "Unknown module: ${module}"
      return 1
      ;;
  esac
}

run_all_recommended() {
  local module
  for module in ssh firewall fail2ban kernel updates services nginx waf auditd apparmor scanners; do
    run_module "$module"
  done
}

prepare_for_changes() {
  if [[ "$PREFLIGHT_DONE" == "true" ]]; then
    return 0
  fi

  if [[ "$RUN_INITIAL_BACKUP" == "true" ]]; then
    initial_config_backup
  else
    log_warn "Initial configuration backup skipped by --no-initial-backup"
    report_add_recommendation "Initial configuration backup was skipped by --no-initial-backup."
  fi

  install_launch_prerequisites
  if [[ "${INSTALL_SECURITY_TOOLS_ON_START:-false}" == "true" ]]; then
    install_security_tools_bundle
  fi
  warn_gcp_if_detected
  PREFLIGHT_DONE="true"
}

show_menu() {
  local choice
  while true; do
    cat <<'EOF'

Debian 13 Web Server Hardening

1) SSH hardening
2) Firewall hardening
3) Fail2ban hardening
4) Kernel / sysctl hardening
5) Disable unnecessary services
6) System updates and unattended upgrades
7) Web server hardening: Nginx
8) WAF: ModSecurity + OWASP CRS
9) Auditd and security logs
10) AppArmor hardening
11) Malware/rootkit/security scanner tools
12) Install/verify required security tools
13) Run all recommended hardening modules
14) Generate security report only
0) Exit
EOF
    read -r -p "Select an option: " choice
    case "$choice" in
      1) prepare_for_changes; run_module ssh ;;
      2) prepare_for_changes; run_module firewall ;;
      3) prepare_for_changes; run_module fail2ban ;;
      4) prepare_for_changes; run_module kernel ;;
      5) prepare_for_changes; run_module services ;;
      6) prepare_for_changes; run_module updates ;;
      7) prepare_for_changes; run_module nginx ;;
      8) prepare_for_changes; run_module waf ;;
      9) prepare_for_changes; run_module auditd ;;
      10) prepare_for_changes; run_module apparmor ;;
      11) prepare_for_changes; run_module scanners ;;
      12) prepare_for_changes; install_security_tools_bundle ;;
      13) prepare_for_changes; run_all_recommended; break ;;
      14) log_info "Report-only selected"; break ;;
      0) log_info "Exit selected"; break ;;
      *) log_warn "Invalid menu option: ${choice}" ;;
    esac
  done
}

main() {
  parse_args "$@"
  load_libraries
  load_configuration

  if [[ "$ACTION" == "doctor" ]]; then
    run_doctor
    exit 0
  fi

  require_root
  init_logging
  init_report
  init_backup
  trap 'log_error "Failure on line ${LINENO}: ${BASH_COMMAND}"; generate_report || true' ERR

  log_section "Debian 13 Web Server Hardening"
  log_info "Profile: ${PROFILE}"
  log_info "Dry run: ${DRY_RUN}"
  log_info "Assume yes: ${ASSUME_YES}"
  log_info "Nginx-only mode: ${NGINX_ONLY:-true}"
  log_info "Auto-install prerequisites: ${AUTO_INSTALL_PREREQUISITES:-true}"
  log_info "Install security tools: ${INSTALL_SECURITY_TOOLS_ON_START:-false}"
  require_debian_13_or_warn

  load_modules

  case "$ACTION" in
    menu)
      show_menu
      ;;
    all)
      prepare_for_changes
      run_all_recommended
      ;;
    module)
      prepare_for_changes
      run_module "$SELECTED_MODULE"
      ;;
    rollback)
      rollback_interactive
      ;;
    install-tools)
      prepare_for_changes
      log_info "Security tool installation only selected"
      ;;
    initial-backup-only)
      initial_config_backup
      log_info "Initial backup only selected"
      ;;
    report-only)
      log_info "Generating report only"
      ;;
    *)
      log_error "Unknown action: ${ACTION}"
      exit 2
      ;;
  esac

  generate_report
}

main "$@"
