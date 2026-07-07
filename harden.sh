#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULE_DIR="${SCRIPT_DIR}/modules"
HARDENING_TIMESTAMP="${HARDENING_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

ACTION="menu"
SELECTED_MODULE=""
CLI_PROFILE=""
PROFILE="balanced"
DRY_RUN="false"
ASSUME_YES="false"
DEBUG="false"
RUN_INITIAL_BACKUP="true"

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
  sudo ./harden.sh --initial-backup-only
  sudo ./harden.sh --no-initial-backup
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
  --initial-backup-only   Create the initial configuration backup and exit
  --no-initial-backup     Skip initial baseline backup for this run
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
        shift
        ;;
      --all)
        ACTION="all"
        shift
        ;;
      --module)
        if [[ -z "${2:-}" ]]; then
          printf 'Missing value for --module\n' >&2
          exit 2
        fi
        ACTION="module"
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
      --initial-backup-only)
        ACTION="initial-backup-only"
        shift
        ;;
      --no-initial-backup)
        RUN_INITIAL_BACKUP="false"
        shift
        ;;
      --rollback)
        ACTION="rollback"
        shift
        ;;
      --report-only)
        ACTION="report-only"
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
}

load_modules() {
  local module_file
  for module_file in "${MODULE_DIR}"/*.sh; do
    # shellcheck source=/dev/null
    source "$module_file"
  done
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
12) Run all recommended hardening modules
13) Generate security report only
0) Exit
EOF
    read -r -p "Select an option: " choice
    case "$choice" in
      1) run_module ssh ;;
      2) run_module firewall ;;
      3) run_module fail2ban ;;
      4) run_module kernel ;;
      5) run_module services ;;
      6) run_module updates ;;
      7) run_module nginx ;;
      8) run_module waf ;;
      9) run_module auditd ;;
      10) run_module apparmor ;;
      11) run_module scanners ;;
      12) run_all_recommended; break ;;
      13) log_info "Report-only selected"; break ;;
      0) log_info "Exit selected"; break ;;
      *) log_warn "Invalid menu option: ${choice}" ;;
    esac
  done
}

main() {
  parse_args "$@"
  load_libraries
  load_configuration

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
  require_debian_13_or_warn
  warn_gcp_if_detected

  load_modules

  case "$ACTION" in
    menu|all|module|initial-backup-only)
      if [[ "$RUN_INITIAL_BACKUP" == "true" ]]; then
        initial_config_backup
      else
        log_warn "Initial configuration backup skipped by --no-initial-backup"
        report_add_recommendation "Initial configuration backup was skipped by --no-initial-backup."
      fi
      ;;
  esac

  case "$ACTION" in
    menu)
      show_menu
      ;;
    all)
      run_all_recommended
      ;;
    module)
      run_module "$SELECTED_MODULE"
      ;;
    rollback)
      rollback_interactive
      ;;
    initial-backup-only)
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
