# shellcheck shell=bash
#
# Standalone Certbot HTTP-01 (ACME) provisioning and scoped renewal timer
# management for Hysteria 2 public TLS certificates.

TB_HY2_ACME_NEED_ISSUE=0
TB_HY2_ACME_DOMAIN=""
TB_HY2_ACME_EMAIL=""
TB_HY2_ACME_LINEAGE=""

TB_HY2_ACME_MARKER="# Managed by ToastBox (hy2-certbot-timer)"

acme_lineage_for_domain() {
  printf 'toastbox-hy2-%s' "$1"
}

acme_live_cert_path() {
  printf '%s/%s/fullchain.pem' "$(certbot_live_root)" "$1"
}

acme_live_key_path() {
  printf '%s/%s/privkey.pem' "$(certbot_live_root)" "$1"
}

acme_service_path() {
  printf '%s/%s' "$TB_SYSTEMD_DIR" "$TB_HY2_ACME_SERVICE"
}

acme_timer_path() {
  printf '%s/%s' "$TB_SYSTEMD_DIR" "$TB_HY2_ACME_TIMER"
}

acme_timer_is_ours() {
  local path="$1"
  [[ -f "$path" ]] && grep -qF "$TB_HY2_ACME_MARKER" "$path"
}

acme_certbot_bin() {
  command -v certbot 2>/dev/null || return 1
}

acme_certbot_supports_ecdsa() {
  certbot --help certonly 2>/dev/null | grep -q -- '--key-type'
}

acme_install_certbot() {
  if has_cmd certbot; then
    return 0
  fi
  log_info info_install_deps "certbot"
  apt-get update >&2 || die err_hy2_acme_certbot_install
  apt_install certbot >&2 || die err_hy2_acme_certbot_install
  has_cmd certbot || die err_hy2_acme_certbot_install
}

acme_check_port_80() {
  local procs
  if procs="$(port_conflict tcp 80)"; then
    die err_hy2_acme_port80_busy "$procs"
  fi
}

acme_ip_is_nonpublic() {
  local ip="$1" lower="${1,,}"
  [[ -z "$ip" ]] && return 0
  if is_private_ipv4 "$ip"; then
    return 0
  fi
  case "$lower" in
    0.0.0.0 | :: | ::1 | fe80:* | fc* | fd*) return 0 ;;
  esac
  return 1
}

acme_resolve_ips() {
  local domain="$1"
  if has_cmd getent; then
    getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u
  elif has_cmd dig; then
    {
      dig +short A "$domain" 2>/dev/null
      dig +short AAAA "$domain" 2>/dev/null
    } | grep -E '^[0-9a-fA-F:.]+$' | sort -u
  fi
}

acme_check_dns() {
  local domain="$1" expected="${2:-}" ip csv="" has_public=0 has_match=0
  local -a ips=()
  [[ "${TOASTBOX_SKIP_ACME_DNS:-0}" == "1" ]] && return 0

  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    ips+=("$ip")
    if ! acme_ip_is_nonpublic "$ip"; then
      has_public=1
    fi
    if [[ -n "$expected" && "$ip" == "$expected" ]]; then
      has_match=1
    fi
  done < <(acme_resolve_ips "$domain")

  ((${#ips[@]} > 0)) || die err_hy2_acme_dns_unresolvable "$domain"
  if [[ "$has_public" != "1" && "${TOASTBOX_ACME_ALLOW_PRIVATE_DNS:-0}" != "1" ]]; then
    csv="$(join_by ', ' "${ips[@]}")"
    die err_hy2_acme_dns_private "$domain" "$csv"
  fi
  if [[ -n "$expected" ]] && { valid_ipv4 "$expected" || valid_ipv6 "$expected"; } && [[ "$has_match" != "1" ]]; then
    csv="$(join_by ', ' "${ips[@]}")"
    log_warn warn_hy2_acme_dns_mismatch "$domain" "$csv" "$expected"
  fi
}

acme_cert_has_lifetime() {
  local cert_file="$1" min_seconds="${2:-2592000}"
  openssl x509 -checkend "$min_seconds" -noout -in "$cert_file" >/dev/null 2>&1
}

# Reuses an already-issued Certbot live certificate when it exists, is valid
# with at least 30 days remaining, pairs cleanly with its key, and matches DOMAIN.
acme_reusable_pair() {
  local domain="$1" cert_file="$2" key_file="$3"
  [[ -f "$cert_file" && -f "$key_file" ]] || return 1
  tls_validate_pair_files "$cert_file" "$key_file" 2>/dev/null || return 1
  tls_cert_matches_name "$cert_file" "$domain" || return 1
  acme_cert_has_lifetime "$cert_file" 2592000 || return 1
}

acme_run_certonly() {
  local domain="$1" email="$2" lineage="$3"
  local -a args=(
    certonly
    --standalone
    --non-interactive
    --agree-tos
    --email "$email"
    --cert-name "$lineage"
    -d "$domain"
    --preferred-challenges http
  )
  if acme_certbot_supports_ecdsa; then
    args+=(--key-type ecdsa)
  else
    log_warn warn_hy2_acme_no_ecdsa_flag
  fi
  if [[ "${TOASTBOX_CERTBOT_STAGING:-0}" == "1" ]]; then
    args+=(--test-cert)
  elif [[ -n "${TOASTBOX_CERTBOT_SERVER:-}" ]]; then
    args+=(--server "$TOASTBOX_CERTBOT_SERVER")
  fi
  certbot "${args[@]}" >&2
}

acme_import_live_pair() {
  local domain="$1" email="$2" lineage="$3" verify_name="$4"
  local cert_file key_file abs_cert abs_key
  cert_file="$(acme_live_cert_path "$lineage")"
  key_file="$(acme_live_key_path "$lineage")"

  tls_validate_pair_files "$cert_file" "$key_file" || die err_hy2_cert_pair "$cert_file" "$key_file"
  abs_cert="$(tls_abs_path "$cert_file")" || die err_hy2_cert_pair "$cert_file" "$key_file"
  abs_key="$(tls_abs_path "$key_file")" || die err_hy2_cert_pair "$cert_file" "$key_file"
  tls_cert_matches_name "$cert_file" "$verify_name" || die err_hy2_cert_sni_mismatch "$verify_name"

  CFG_HY2_TLS="files"
  CFG_HY2_CERT="$TLS_CERT_PEM"
  CFG_HY2_KEY="$TLS_KEY_PEM"
  CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"
  CFG_HY2_CERT_FILE="$abs_cert"
  CFG_HY2_KEY_FILE="$abs_key"
  CFG_HY2_CERTBOT_HOOK=1
  CFG_HY2_ACME=1
  CFG_HY2_ACME_DOMAIN="$domain"
  CFG_HY2_ACME_EMAIL="$email"
  CFG_HY2_ACME_LINEAGE="$lineage"
}

acme_provision_cert() {
  local domain="$1" email="$2" lineage="$3" verify_name="$4"
  local opened_80=0 cert_file key_file

  acme_check_dns "$domain" "$CFG_SERVER_ADDR"
  acme_check_port_80
  acme_install_certbot

  if [[ "$OPT_NO_FIREWALL" != "1" && -n "$(fw_backend)" ]] &&
    ! in_list "80/tcp" "${CFG_FW_RULES[@]}"; then
    if fw_open "80/tcp"; then
      opened_80=1
      log_ok info_fw_opened "80/tcp"
    fi
  fi

  log_info info_hy2_acme_issuing "$domain" "$lineage"
  local issue_failed=0
  acme_run_certonly "$domain" "$email" "$lineage" || issue_failed=1
  # HTTP-01 issuance is finished; successful installation reopens port 80
  # via sync_firewall for automatic renewal.
  [[ "$opened_80" == "1" ]] && fw_close "80/tcp"
  if [[ "$issue_failed" == "1" ]]; then
    die err_hy2_acme_issue "$domain"
  fi

  cert_file="$(acme_live_cert_path "$lineage")"
  key_file="$(acme_live_key_path "$lineage")"
  if [[ ! -f "$cert_file" || ! -f "$key_file" ]] ||
    ! tls_validate_pair_files "$cert_file" "$key_file"; then
    die err_hy2_cert_pair "$cert_file" "$key_file"
  fi
  if ! tls_cert_matches_name "$cert_file" "$verify_name"; then
    die err_hy2_cert_sni_mismatch "$verify_name"
  fi

  acme_import_live_pair "$domain" "$email" "$lineage" "$verify_name"
  log_ok ok_hy2_acme_issued "$domain" "$lineage"
}

acme_system_timer_active() {
  local unit
  for unit in certbot.timer snap.certbot.renew.timer; do
    if systemctl -q is-active "$unit" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

acme_render_service() {
  local lineage="$1" certbot_bin="$2"
  cat <<EOF
$TB_HY2_ACME_MARKER
[Unit]
Description=ToastBox Hysteria 2 Certbot certificate renewal
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$certbot_bin renew --non-interactive --cert-name $lineage
EOF
}

acme_render_timer() {
  cat <<EOF
$TB_HY2_ACME_MARKER
[Unit]
Description=ToastBox Hysteria 2 Certbot certificate renewal timer

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=43200
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

acme_write_unit() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.tb-acme.XXXXXX")" || return 1
  if ! cat >"$tmp" ||
    ! install_owned 644 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$dest"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

acme_timer_remove() {
  local svc_path timer_path changed=0
  svc_path="$(acme_service_path)"
  timer_path="$(acme_timer_path)"
  if acme_timer_is_ours "$timer_path" || acme_timer_is_ours "$svc_path"; then
    systemctl disable --now "$TB_HY2_ACME_TIMER" >/dev/null 2>&1 || true
    if acme_timer_is_ours "$timer_path"; then
      rm -f "$timer_path"
      changed=1
    fi
    if acme_timer_is_ours "$svc_path"; then
      rm -f "$svc_path"
      changed=1
    fi
    if [[ "$changed" == "1" ]]; then
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
  fi
}

acme_timer_sync() {
  local lineage="$1" certbot_bin svc_path timer_path
  if acme_system_timer_active; then
    acme_timer_remove
    log_info info_hy2_acme_reuse_system_timer
    return 0
  fi

  certbot_bin="$(acme_certbot_bin)" || return 1
  svc_path="$(acme_service_path)"
  timer_path="$(acme_timer_path)"
  if [[ -e "$svc_path" ]] && ! acme_timer_is_ours "$svc_path"; then
    return 1
  fi
  if [[ -e "$timer_path" ]] && ! acme_timer_is_ours "$timer_path"; then
    return 1
  fi

  acme_render_service "$lineage" "$certbot_bin" | acme_write_unit "$svc_path" || return 1
  acme_render_timer | acme_write_unit "$timer_path" || return 1
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now "$TB_HY2_ACME_TIMER" >/dev/null 2>&1 || return 1
  log_ok ok_hy2_acme_timer_enabled "$TB_HY2_ACME_TIMER" "$lineage"
}

acme_timer_backup() {
  local dir="$1" svc_path timer_path
  install -d -m 700 "$dir" || return 1
  svc_path="$(acme_service_path)"
  timer_path="$(acme_timer_path)"
  if acme_timer_is_ours "$svc_path"; then
    cp -p "$svc_path" "$dir/service" || true
  fi
  if acme_timer_is_ours "$timer_path"; then
    cp -p "$timer_path" "$dir/timer" || true
  fi
}

acme_timer_restore() {
  local dir="$1" svc_path timer_path target_dir
  svc_path="$(acme_service_path)"
  timer_path="$(acme_timer_path)"
  acme_timer_remove
  target_dir="$TB_SYSTEMD_DIR"
  if [[ -f "$dir/service" ]]; then
    install -d -m 755 "$target_dir" || true
    install_owned 644 root root "$dir/service" "$svc_path" || true
  fi
  if [[ -f "$dir/timer" ]]; then
    install -d -m 755 "$target_dir" || true
    install_owned 644 root root "$dir/timer" "$timer_path" || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable --now "$TB_HY2_ACME_TIMER" >/dev/null 2>&1 || true
  fi
}
