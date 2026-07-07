#!/usr/bin/env bash
set -Eeuo pipefail

run_firewall_hardening() {
  log_section "Firewall hardening"
  report_add_module "firewall"
  log_info "Starting nftables firewall hardening module"
  log_warn "This script configures the Linux host firewall only. It does not configure GCP VPC firewall rules."
  log_warn "Make sure your GCP firewall allows the required SSH/HTTP/HTTPS ports."
  warn_gcp_if_detected

  install_packages nftables

  local ssh_port tmp tcp_ports udp_ports port
  ssh_port="$(detect_ssh_port)"
  tmp="$(mktemp)"
  tcp_ports=()
  udp_ports=()

  for port in "${FIREWALL_EXTRA_TCP_PORTS[@]+"${FIREWALL_EXTRA_TCP_PORTS[@]}"}"; do
    [[ -n "$port" ]] && tcp_ports+=("$port")
  done
  for port in "${FIREWALL_EXTRA_UDP_PORTS[@]+"${FIREWALL_EXTRA_UDP_PORTS[@]}"}"; do
    [[ -n "$port" ]] && udp_ports+=("$port")
  done

  {
    printf '#!/usr/sbin/nft -f\n'
    printf '# Managed by debian13-web-hardening.\n\n'
    printf 'flush ruleset\n\n'
    printf 'table inet debian13_hardening {\n'
    printf '  chain input {\n'
    printf '    type filter hook input priority 0; policy drop;\n'
    printf '    iif "lo" accept\n'
    printf '    ct state established,related accept\n'
    printf '    ct state invalid drop\n'
    printf '    ip protocol icmp accept\n'
    printf '    ip6 nexthdr icmpv6 accept\n'
    printf '    tcp dport %s accept\n' "$ssh_port"
    if is_true "${FIREWALL_ALLOW_WEB:-true}" || is_true "${WEB_SERVER_MODE:-true}"; then
      printf '    tcp dport { 80, 443 } accept\n'
    fi
    if ((${#tcp_ports[@]} > 0)); then
      printf '    tcp dport { %s } accept\n' "$(join_by_comma "${tcp_ports[@]}")"
    fi
    if ((${#udp_ports[@]} > 0)); then
      printf '    udp dport { %s } accept\n' "$(join_by_comma "${udp_ports[@]}")"
    fi
    printf '    counter drop\n'
    printf '  }\n\n'
    printf '  chain forward {\n'
    printf '    type filter hook forward priority 0; policy drop;\n'
    printf '  }\n\n'
    printf '  chain output {\n'
    printf '    type filter hook output priority 0; policy accept;\n'
    printf '  }\n'
    printf '}\n'
  } > "$tmp"

  if [[ -f /etc/nftables.conf ]] && cmp -s "$tmp" /etc/nftables.conf \
    && systemctl is-enabled --quiet nftables 2>/dev/null \
    && service_is_active nftables; then
    log_success "nftables firewall already configured and active"
    report_add_already_configured "/etc/nftables.conf"
    report_add_firewall_rule "Default deny inbound traffic"
    report_add_firewall_rule "Allow SSH on TCP port ${ssh_port}"
    if is_true "${FIREWALL_ALLOW_WEB:-true}" || is_true "${WEB_SERVER_MODE:-true}"; then
      report_add_firewall_rule "Allow HTTP/HTTPS on TCP ports 80 and 443"
    fi
    rm -f "$tmp"
    return 0
  fi

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    nft -c -f "$tmp"
    log_success "nftables configuration test passed"
  else
    log_info "[dry-run] nft -c -f ${tmp}"
  fi

  backup_file /etc/nftables.conf
  install_file_if_changed "$tmp" /etc/nftables.conf 0755

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    report_mark_changed "Firewall rules applied"
    run_cmd nft -f /etc/nftables.conf
    run_cmd systemctl enable --now nftables
  fi

  report_add_firewall_rule "Default deny inbound traffic"
  report_add_firewall_rule "Allow loopback traffic"
  report_add_firewall_rule "Allow established and related traffic"
  report_add_firewall_rule "Allow ICMP and ICMPv6"
  report_add_firewall_rule "Allow SSH on TCP port ${ssh_port}"
  if is_true "${FIREWALL_ALLOW_WEB:-true}" || is_true "${WEB_SERVER_MODE:-true}"; then
    report_add_firewall_rule "Allow HTTP/HTTPS on TCP ports 80 and 443"
  fi
  report_add_firewall_rule "Allow all outbound traffic, including GCP metadata access to 169.254.169.254"
  rm -f "$tmp"
}
