# shellcheck shell=bash
#
# Bilingual messages (English / 简体中文).
#
# Every message is a printf format string, so a literal percent sign must
# be written as %%. tests/unit/i18n.bats checks that both tables carry the
# same keys and that every key used in the code exists.

# -g: the tables must stay global even when this file is sourced from
# inside a function (as the test-suite does).
declare -gA TB_MSG_EN=()
declare -gA TB_MSG_ZH=()

TB_LANG_EXPLICIT=0

# msg KEY [ARGS...]
msg() {
  local key="$1" fmt=""
  shift
  if [[ "$TB_LANG" == "zh" ]]; then
    fmt="${TB_MSG_ZH[$key]:-}"
  fi
  if [[ -z "$fmt" ]]; then
    fmt="${TB_MSG_EN[$key]:-$key}"
  fi
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
}

# Language: --lang, then TOASTBOX_LANG, then the locale. Runs before the
# real argument parsing so that parse errors are already localized.
tb_init_lang() {
  local lang="" arg prev=""
  for arg in "$@"; do
    if [[ "$arg" == --lang=* ]]; then
      lang="${arg#*=}"
    elif [[ "$prev" == "--lang" ]]; then
      lang="$arg"
    fi
    prev="$arg"
  done
  [[ -n "$lang" ]] || lang="${TOASTBOX_LANG:-}"

  TB_LANG_EXPLICIT=1
  case "$lang" in
    zh | zh[_-]* | cn) TB_LANG="zh" ;;
    en | en[_-]*) TB_LANG="en" ;;
    "")
      TB_LANG_EXPLICIT=0
      case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        zh*) TB_LANG="zh" ;;
        *) TB_LANG="en" ;;
      esac
      ;;
    *)
      TB_LANG="en"
      die err_invalid_option --lang "$lang"
      ;;
  esac
}

# Asked once at the top of the interactive menu: SSH sessions rarely carry
# a locale that says anything about the person typing.
tb_choose_lang() {
  local reply default="1"
  [[ "$TB_LANG_EXPLICIT" == "1" ]] && return 0
  [[ "$TB_LANG" == "zh" ]] && default="2"
  reply="$(tb_readline "Language / 语言: 1) English  2) 中文 [$default]: ")"
  case "${reply:-$default}" in
    2 | zh | 中文) TB_LANG="zh" ;;
    *) TB_LANG="en" ;;
  esac
}

# ---------------------------------------------------------------------------
# English
# ---------------------------------------------------------------------------

TB_MSG_EN[err_root]='This command must be run as root (try: sudo bash toastbox.sh ...).'
TB_MSG_EN[err_os_version]='%s %s is not supported. %s %s or newer is required.'
TB_MSG_EN[err_os_unsupported]='Unsupported system "%s". ToastBox supports Debian 11+ and Ubuntu 20.04+.'
TB_MSG_EN[warn_os_derivative]='"%s" is a Debian/Ubuntu derivative. It is not tested, continuing anyway.'
TB_MSG_EN[err_arch_unsupported]='Unsupported CPU architecture "%s". Only amd64 and arm64 are supported.'
TB_MSG_EN[err_no_systemd]='systemd is required but is not running on this host.'
TB_MSG_EN[info_install_deps]='Installing required packages: %s'
TB_MSG_EN[err_apt_update]='apt-get update failed.'
TB_MSG_EN[err_apt_install]='Failed to install: %s'
TB_MSG_EN[err_download]='Download failed: %s'
TB_MSG_EN[err_state_corrupt]='The state file %s is unreadable or damaged.'
TB_MSG_EN[err_no_state]='No ToastBox node found on this host. Run "install" first.'
TB_MSG_EN[err_keypair]='Could not generate a REALITY key pair with %s.'
TB_MSG_EN[err_core]='Unknown core "%s". Use xray or sing-box.'
TB_MSG_EN[err_missing_value]='Option %s needs a value.'
TB_MSG_EN[err_unknown_arg]='Unknown argument: %s (see --help).'
TB_MSG_EN[err_invalid_option]='Invalid value for %s: "%s"'
TB_MSG_EN[err_invalid_value]='Invalid value: "%s"'
TB_MSG_EN[warn_invalid_input]='"%s" is not valid, please try again.'
TB_MSG_EN[err_protocols]='Invalid protocol list "%s". Use vless, ss, hy2, xhttp, both, all or comma-separated combinations.'
TB_MSG_EN[err_protocol_disabled]='Protocol "%s" is not enabled on this node.'
TB_MSG_EN[err_format]='Unknown format "%s". Use text, links, json, xray, sing-box, hysteria2, mihomo or nginx.'
TB_MSG_EN[err_format_requires_hy2]='Format "hysteria2" requires Hysteria 2 to be enabled and selected.'
TB_MSG_EN[err_format_singbox_no_xhttp]='Format "sing-box" does not support VLESS + XHTTP because ToastBox configures XHTTP on Xray; use "xray" or "mihomo" instead.'
TB_MSG_EN[warn_singbox_skip_xhttp]='sing-box outbound rendering skipped VLESS + XHTTP; use "show --format xray" or "show --format mihomo" for XHTTP.'
TB_MSG_EN[warn_singbox_xhttp_ws_only]='sing-box does not support VLESS + XHTTP; emitted companion VLESS + WS outbound only (use "show --format xray" or "show --format mihomo" for XHTTP).'
TB_MSG_EN[err_format_requires_xhttp]='Format "nginx" requires VLESS + XHTTP to be enabled and selected.'
TB_MSG_EN[err_format_nginx_requires_none]='Nginx location snippets are only generated when XHTTP runs behind a reverse proxy (--xhttp-tls none).'
TB_MSG_EN[err_aborted]='Aborted. Nothing was changed. (Use --yes to confirm without a prompt.)'
TB_MSG_EN[err_sockopt_core]='Custom TCP sockopt is supported only by Xray, not %s. Use install --reset-sockopt to clear it before switching cores.'
TB_MSG_EN[err_sockopt_command]='TCP sockopt options are only accepted with install; update and rotate reuse the saved settings.'
TB_MSG_EN[err_xhttp_core]='VLESS + XHTTP requires the Xray core, not %s.'
TB_MSG_EN[err_xhttp_command]='XHTTP options are only accepted with install; update and rotate reuse the saved settings.'
TB_MSG_EN[err_xhttp_not_enabled]='XHTTP options require xhttp to be included in --protocols.'
TB_MSG_EN[err_xhttp_cert_with_none]='--xhttp-cert and --xhttp-key cannot be combined with --xhttp-tls none.'
TB_MSG_EN[err_xhttp_cert_pair_required]='--xhttp-cert and --xhttp-key must be passed together.'
TB_MSG_EN[err_xhttp_none_loopback]='XHTTP TLS mode "none" is a plaintext h2c backend for a local reverse proxy and must listen on a loopback address (got "%s"); use 127.0.0.1 / ::1 or pass --xhttp-tls files.'
TB_MSG_EN[err_xhttp_host_required]='XHTTP requires your public hostname (for example cdn.example.com). Pass it with --xhttp-host (or --server-addr when using a domain).'
TB_MSG_EN[err_xhttp_files_required]='XHTTP TLS mode "files" requires --xhttp-cert and --xhttp-key.'
TB_MSG_EN[err_xhttp_cert_pair]='XHTTP certificate %s and private key %s are unreadable, expired or do not match.'
TB_MSG_EN[err_xhttp_cert_host_mismatch]='The XHTTP certificate is not valid for "%s".'
TB_MSG_EN[err_xhttp_tls_invalid]='The saved XHTTP certificate or key is invalid or expired; re-import with --xhttp-cert and --xhttp-key.'
TB_MSG_EN[err_xhttp_cert_sources_missing]='No external certificate source paths are recorded for XHTTP; import with --xhttp-cert and --xhttp-key first.'
TB_MSG_EN[err_xhttp_hook_not_none]='--xhttp-cert-hook certbot cannot be used with --xhttp-tls none.'
TB_MSG_EN[err_xhttp_ws_not_enabled]='XHTTP WebSocket keep-alive options (--xhttp-ws-*) require --xhttp-ws-keepalive to be enabled.'
TB_MSG_EN[err_xhttp_path_conflict]='XHTTP path "%s" conflicts with WebSocket keep-alive path "%s" (paths must differ and not be a path-segment prefix of each other).'
TB_MSG_EN[warn_xhttp_ws_heartbeat_cf]='XHTTP WS heartbeatPeriod is %ss; Cloudflare enforces a 125s proxy read timeout, so values above 60s may disconnect idle clients.'
TB_MSG_EN[warn_xhttp_alpn_h3]='XHTTP ALPN is "h3": origin listens on TCP only, so clients must connect through a CDN edge (e.g. Cloudflare) with HTTP/3 (QUIC) enabled, not directly to origin.'
TB_MSG_EN[warn_xhttp_ws_port_conflict]='XHTTP WS default port %s/tcp conflicts with another configured TCP port on this node; using fallback port %s/tcp.'
TB_MSG_EN[warn_xhttp_ws_port_busy]='XHTTP WS default port %s/tcp is already in use; using fallback port %s/tcp.'
TB_MSG_EN[err_hy2_command]='Hysteria 2 options are only accepted with install; update and rotate reuse the saved settings.'
TB_MSG_EN[err_hy2_cert_with_self_signed]='--hy2-cert and --hy2-key cannot be combined with --hy2-tls self-signed.'
TB_MSG_EN[err_hy2_cert_pair_required]='--hy2-cert and --hy2-key must be passed together.'
TB_MSG_EN[err_hy2_renew_not_self_signed]='--hy2-renew-cert can only be used with --hy2-tls self-signed.'
TB_MSG_EN[err_hy2_files_required]='Hysteria 2 TLS mode "files" requires --hy2-cert and --hy2-key.'
TB_MSG_EN[err_hy2_cert_pair]='Certificate %s and private key %s are unreadable, expired or do not match.'
TB_MSG_EN[err_hy2_sni_required]='Could not determine the Hysteria 2 certificate hostname; pass it with --hy2-sni.'
TB_MSG_EN[err_hy2_cert_sni_mismatch]='The Hysteria 2 certificate is not valid for "%s".'
TB_MSG_EN[err_hy2_tls_invalid]='The saved Hysteria 2 certificate or key is invalid or expired; re-import with --hy2-cert and --hy2-key.'
TB_MSG_EN[err_hy2_tls_gen]='Could not generate a self-signed TLS certificate for Hysteria 2.'
TB_MSG_EN[err_hy2_not_enabled]='Hysteria 2 options require Hysteria 2 (hy2) to be included in --protocols.'
TB_MSG_EN[err_hy2_hook_not_self_signed]='--hy2-cert-hook certbot cannot be used with --hy2-tls self-signed.'
TB_MSG_EN[err_hy2_cert_sources_missing]='No external certificate source paths are recorded for Hysteria 2; import with --hy2-cert and --hy2-key first.'
TB_MSG_EN[err_hy2_hook_certbot_paths]='Certbot deploy hook requires matching %s/<lineage>/fullchain.pem and privkey.pem source files.'
TB_MSG_EN[err_hy2_foreign_hook]='Refusing to overwrite an unmanaged deploy hook at %s.'
TB_MSG_EN[err_hy2_hook_needs_self]='Enabling --hy2-cert-hook requires a persistent toastbox binary at %s; run install using toastbox.sh first.'
TB_MSG_EN[err_hy2_hook_install]='Could not install the Certbot deploy hook at %s.'
TB_MSG_EN[err_hy2_acme_with_files]='ACME automatic issuance cannot be combined with --hy2-cert or --hy2-key.'
TB_MSG_EN[err_hy2_acme_tls_conflict]='ACME flags (--hy2-acme-*) can only be used with --hy2-tls acme.'
TB_MSG_EN[err_hy2_acme_requires_hook]='ACME automatic issuance requires automatic renewal sync; --hy2-cert-hook none cannot be combined with --hy2-tls acme.'
TB_MSG_EN[err_hy2_acme_domain_required]='ACME certificate issuance requires a domain name (--hy2-acme-domain or a domain --server-addr).'
TB_MSG_EN[err_hy2_acme_email_required]='ACME certificate issuance requires an account email address (--hy2-acme-email).'
TB_MSG_EN[err_hy2_acme_tos_required]='ACME certificate issuance requires accepting the CA Subscriber Agreement (--hy2-acme-agree-tos).'
TB_MSG_EN[err_hy2_acme_port80_conflict]='Certbot standalone HTTP-01 requires TCP port 80, which conflicts with the configured TCP port 80 listener.'
TB_MSG_EN[err_hy2_acme_port80_busy]='TCP port 80 is already in use by: %s. Certbot standalone requires port 80 and ToastBox will not stop existing services; use --hy2-cert and --hy2-key to reuse an existing certificate instead.'
TB_MSG_EN[err_hy2_acme_dns_unresolvable]='Domain %s did not resolve to any IP address in DNS. Point an A/AAAA record to this server before running ACME.'
TB_MSG_EN[err_hy2_acme_dns_private]='Domain %s resolved only to non-public IP address(es) (%s); public Let'\''s Encrypt HTTP-01 validation requires a public IP.'
TB_MSG_EN[warn_hy2_acme_dns_mismatch]='Domain %s resolved to %s, which differs from --server-addr %s.'
TB_MSG_EN[warn_hy2_acme_no_ecdsa_flag]='Installed certbot does not support --key-type ecdsa; continuing with its default key type.'
TB_MSG_EN[err_hy2_acme_certbot_install]='Could not install certbot automatically.'
TB_MSG_EN[info_hy2_acme_issuing]='Issuing public TLS certificate for %s via Certbot standalone (lineage %s)...'
TB_MSG_EN[err_hy2_acme_issue]='Certbot standalone issuance failed for %s; existing node configuration was left untouched.'
TB_MSG_EN[ok_hy2_acme_issued]='Issued public TLS certificate for %s (lineage %s).'
TB_MSG_EN[info_hy2_acme_reuse_cert]='Reusing existing valid Certbot certificate for %s (%s).'
TB_MSG_EN[info_hy2_acme_reuse_system_timer]='Reusing the active system Certbot renewal timer.'
TB_MSG_EN[ok_hy2_acme_timer_enabled]='Enabled scoped ToastBox renewal timer %s for lineage %s.'
TB_MSG_EN[err_hy2_acme_timer]='Could not configure the ToastBox Certbot renewal timer.'
TB_MSG_EN[err_hy2_hop_interval_requires_ports]='--hy2-hop-interval requires UDP port hopping to be enabled with --hy2-hop-ports.'
TB_MSG_EN[err_hy2_hop_ss_conflict]='UDP port hopping range (%s) overlaps with Shadowsocks UDP port %s.'
TB_MSG_EN[err_hy2_hop_ports_in_use]='Hysteria 2 hop ports are already in use by: %s'
TB_MSG_EN[err_hy2_hop_loopback]='Hysteria 2 UDP port hopping is not supported when --listen is a loopback address (%s).'
TB_MSG_EN[err_hy2_hop_no_backend]='Hysteria 2 UDP port hopping requires nftables (nft) or iptables.'
TB_MSG_EN[err_hy2_hop_no_cmd]='Hysteria 2 UDP port hopping requires the "%s" command.'
TB_MSG_EN[err_hy2_hop_apply]='Could not configure Hysteria 2 UDP port-hopping NAT rules.'
TB_MSG_EN[err_refresh_options]='refresh-cert accepts no installation or show options (only --yes / --lang).'
TB_MSG_EN[err_refresh_requires_protocol]='Neither Hysteria 2 nor XHTTP TLS certificate import is enabled on this node.'
TB_MSG_EN[err_refresh_requires_files]='refresh-cert requires Hysteria 2 or XHTTP TLS mode "files".'
TB_MSG_EN[info_cert_unchanged]='Certificate chain and key are unchanged; no restart needed.'
TB_MSG_EN[ok_cert_refreshed]='TLS certificate was refreshed.'
TB_MSG_EN[err_lock_open]='Could not open operation lock %s.'
TB_MSG_EN[err_lock_busy]='Another ToastBox operation holds the lock %s.'

TB_MSG_EN[prompt_core]='Core: 1) xray  2) sing-box'
TB_MSG_EN[prompt_protocols]='Protocols: 1) VLESS+SS  2) VLESS only  3) SS only  4) Hysteria 2 only  5) VLESS+SS+Hy2 (all)  6) XHTTP only (or comma list)'
TB_MSG_EN[info_detect_addr]='Detecting the public address of this server...'
TB_MSG_EN[err_server_addr_required]='Could not detect the public address. Pass it with --server-addr.'
TB_MSG_EN[prompt_server_addr]='Address clients connect to (IP or domain)'
TB_MSG_EN[prompt_vless_port]='VLESS port'
TB_MSG_EN[help_reality_sni]='
REALITY borrows the TLS identity of a real website (the "target").
Choose a site that:
  - supports TLS 1.3 and HTTP/2;
  - is NOT behind a CDN such as Cloudflare: connections that fail REALITY
    authentication are forwarded to the target, so a CDN target turns this
    server into a free relay for that CDN;
  - ideally is hosted in the same network (ASN) as this server.
'
TB_MSG_EN[prompt_reality_sni]='REALITY target domain (SNI), e.g. www.example.com'
TB_MSG_EN[err_sni_required]='A REALITY target domain is required. Pass it with --reality-sni.'
TB_MSG_EN[info_probing_target]='Probing REALITY target %s (SNI %s)...'
TB_MSG_EN[ok_target]='%s speaks TLS 1.3 and presents a valid certificate.'
TB_MSG_EN[warn_target_no_h2]='%s did not negotiate HTTP/2. It works, but an HTTP/2 site blends in better.'
TB_MSG_EN[err_target_unreachable]='Could not connect to %s from this server.'
TB_MSG_EN[err_target_no_tls13]='%s does not support TLS 1.3, which REALITY requires.'
TB_MSG_EN[err_target_cert]='The certificate of %s is not valid for %s.'
TB_MSG_EN[prompt_target_anyway]='Use this target anyway?'
TB_MSG_EN[err_target_rejected]='The REALITY target was rejected. Choose another one, or pass --skip-target-check to skip the probe.'
TB_MSG_EN[prompt_ss_port]='Shadowsocks port'
TB_MSG_EN[prompt_ss_method]='Shadowsocks method: 1) 2022-blake3-aes-128-gcm  2) 2022-blake3-aes-256-gcm  3) 2022-blake3-chacha20-poly1305'
TB_MSG_EN[prompt_hy2_port]='Hysteria 2 UDP port'
TB_MSG_EN[prompt_hy2_tls]='Hysteria 2 TLS: 1) self-signed  2) files (import cert & key)  3) acme (Certbot public cert)'
TB_MSG_EN[prompt_hy2_acme_domain]='Domain name for public ACME certificate (DNS must point to this server)'
TB_MSG_EN[prompt_hy2_acme_email]='Account email for Let'\''s Encrypt / Certbot expiry notices'
TB_MSG_EN[prompt_hy2_acme_tos]='Agree to the Let'\''s Encrypt Subscriber Agreement for automatic issuance?'
TB_MSG_EN[prompt_hy2_cert]='Path to TLS certificate chain PEM'
TB_MSG_EN[prompt_hy2_key]='Path to TLS private key PEM'
TB_MSG_EN[prompt_hy2_sni]='Hysteria 2 TLS verification name (SNI)'
TB_MSG_EN[prompt_hy2_obfs]='Hysteria 2 obfuscation: 1) none  2) salamander'
TB_MSG_EN[prompt_xhttp_tls]='XHTTP TLS: 1) none (plaintext loopback backend behind reverse proxy, default)  2) files (direct TLS on 443/8443 using Origin CA or public PEM)'
TB_MSG_EN[prompt_xhttp_host]='Public XHTTP hostname (Host / SNI), e.g. edge.example.com'
TB_MSG_EN[prompt_xhttp_port]='XHTTP backend TCP port'
TB_MSG_EN[prompt_xhttp_connect_addr]='Client dial address / CDN preferred domain or IP (leave empty to match Host)'
TB_MSG_EN[prompt_xhttp_cert]='Path to XHTTP TLS certificate chain PEM (e.g. Cloudflare Origin CA)'
TB_MSG_EN[prompt_xhttp_key]='Path to XHTTP TLS private key PEM'
TB_MSG_EN[prompt_xhttp_ws_keepalive]='Also enable companion VLESS-WS keep-alive inbound for long idle connections (e.g. ChatGPT Desktop / idle SSH)?'
TB_MSG_EN[err_no_free_port]='Could not find a free port. Pass one with --ss-port.'
TB_MSG_EN[err_port_same]='Two TCP listeners cannot both bind to port %s.'
TB_MSG_EN[err_port_same_udp]='Hysteria 2 and Shadowsocks cannot both listen on UDP port %s.'
TB_MSG_EN[err_port_in_use]='Port %s is already in use by: %s'
TB_MSG_EN[plan_title]='About to deploy:'
TB_MSG_EN[prompt_proceed]='Proceed?'

TB_MSG_EN[warn_core_switch]='Switching core from %s to %s. The %s service is stopped and disabled once the new core is ready.'
TB_MSG_EN[prompt_overwrite_config]='%s already holds a configuration that ToastBox did not write. Replace it? (A backup is kept.)'
TB_MSG_EN[err_foreign_config]='Kept the existing configuration %s. Re-run with --overwrite-config to replace it.'
TB_MSG_EN[info_installing_core]='Installing %s from its official source...'
TB_MSG_EN[err_core_install]='Installing %s failed.'
TB_MSG_EN[err_core_too_old]='%s %s is too old: ToastBox needs %s or newer. Run "update" to upgrade it.'
TB_MSG_EN[err_core_version_too_old]='Requested %s %s is too old: ToastBox needs %s or newer.'
TB_MSG_EN[warn_core_rolled_back]='Restored the previous %s binary.'
TB_MSG_EN[ok_core_ready]='%s %s is installed.'
TB_MSG_EN[err_render]='Could not generate the configuration.'
TB_MSG_EN[err_validate]='%s rejected the generated configuration. Nothing was changed.'
TB_MSG_EN[err_backup_config]='Could not back up the existing configuration %s.'
TB_MSG_EN[err_install_config]='Could not write the configuration to %s.'
TB_MSG_EN[err_rollback_config]='Could not restore %s from backup %s.'
TB_MSG_EN[err_state_save]='Could not save node state to %s.'
TB_MSG_EN[err_xray_dynamic_user]='Service %s uses DynamicUser without a static group; refusing to make %s world-readable.'
TB_MSG_EN[err_xray_service_user]='Service %s is configured with unknown user "%s".'
TB_MSG_EN[info_restarting]='Restarting %s...'
TB_MSG_EN[ok_service_running]='%s is running.'
TB_MSG_EN[err_service_start]='%s failed to start with the new configuration. Recent log:'
TB_MSG_EN[warn_rolled_back]='Restored the previous configuration from %s.'
TB_MSG_EN[warn_service_stopped]='%s was not running before this change and has been left stopped.'
TB_MSG_EN[info_service_kept_stopped]='%s is stopped; configuration updated on disk without starting it.'
TB_MSG_EN[warn_old_core_restored]='Started the previous %s service again.'
TB_MSG_EN[err_apply]='The configuration was not applied.'
TB_MSG_EN[info_fw_opened]='Firewall (ufw): allowed %s'
TB_MSG_EN[info_fw_closed]='Firewall (ufw): removed rule %s'
TB_MSG_EN[warn_extra_configs]='sing-box merges every JSON file in its configuration directory. These files are also loaded: %s'
TB_MSG_EN[warn_clock]='The system clock is not NTP-synchronized. Shadowsocks 2022 rejects clients when the clocks differ too much; enable time sync (e.g. timedatectl set-ntp true).'
TB_MSG_EN[ok_installed]='The node is deployed.'
TB_MSG_EN[ok_self_installed]='Installed this script as %s; manage the node later with "toastbox <command>".'
TB_MSG_EN[ok_updated]='%s is now at version %s.'
TB_MSG_EN[prompt_rotate]='Generate new credentials? Every existing client will stop working until it is reconfigured.'
TB_MSG_EN[ok_rotated]='New credentials are active.'
TB_MSG_EN[prompt_uninstall]='Remove %s and this node? (Configuration files are kept.)'
TB_MSG_EN[prompt_uninstall_purge]='Remove %s, this node and ALL of its configuration, logs and backups?'
TB_MSG_EN[err_remove_failed]='Removing %s failed; node state was kept. Check the output above.'
TB_MSG_EN[ok_uninstalled]='%s and the ToastBox node were removed.'
TB_MSG_EN[ok_core_removed]='%s was removed. The node on %s is untouched.'
TB_MSG_EN[warn_no_qrencode]='qrencode is not available, skipping the QR code.'

TB_MSG_EN[word_running]='running'
TB_MSG_EN[word_stopped]='not running'
TB_MSG_EN[label_core]='Core'
TB_MSG_EN[label_server]='Server address'
TB_MSG_EN[label_config]='Server config'
TB_MSG_EN[label_sockopt]='TCP sockopt (Xray listeners)'
TB_MSG_EN[label_port]='Port'
TB_MSG_EN[label_uuid]='UUID'
TB_MSG_EN[label_flow]='Flow'
TB_MSG_EN[label_sni]='SNI'
TB_MSG_EN[label_target]='Target'
TB_MSG_EN[label_public_key]='Public key (password)'
TB_MSG_EN[label_short_id]='Short ID'
TB_MSG_EN[label_fingerprint]='Fingerprint'
TB_MSG_EN[label_method]='Method'
TB_MSG_EN[label_password]='Password'
TB_MSG_EN[label_tls]='TLS'
TB_MSG_EN[label_cert_file]='Certificate file'
TB_MSG_EN[label_cert_hook]='Deploy hook'
TB_MSG_EN[label_pin_sha256]='Pin SHA-256'
TB_MSG_EN[label_obfs]='Obfs'
TB_MSG_EN[label_obfs_password]='Obfs password'
TB_MSG_EN[label_masquerade]='Masquerade'
TB_MSG_EN[label_hop_ports]='Hop ports'
TB_MSG_EN[label_hop_interval]='Hop interval'
TB_MSG_EN[label_acme_domain]='ACME domain'
TB_MSG_EN[label_acme_lineage]='ACME lineage'
TB_MSG_EN[label_backend]='Backend'
TB_MSG_EN[label_connect_addr]='Connect addr'
TB_MSG_EN[label_host]='Host'
TB_MSG_EN[label_path]='Path'
TB_MSG_EN[label_xhttp_mode]='XHTTP mode'
TB_MSG_EN[label_alpn]='ALPN'
TB_MSG_EN[label_ws_heartbeat]='WS heartbeat'
TB_MSG_EN[label_link]='Share link:'
TB_MSG_EN[note_ss_landing]='Note: Shadowsocks has no TLS camouflage. Use it as a landing node behind a relay, not for connections that cross a censoring firewall directly.'
TB_MSG_EN[note_client_configs]='Client configurations: "show --format xray", "show --format sing-box", "show --format hysteria2" or "show --format mihomo". Links only: "show --format links". QR codes: "show --qr".'
TB_MSG_EN[note_hy2_hop_clients]='Port-hopping clients: Hysteria app/v2.14.0+, Xray 26.11.9+ (udphop), or sing-box 1.11.0+.'
TB_MSG_EN[note_hy2_hop_random_clients]='Random port-hopping clients: Hysteria app/v2.14.0+, Xray 26.11.9+ (udphop), or sing-box 1.14.0+ (hop_interval_max).'
TB_MSG_EN[note_hop_no_firewall]='Note: --no-firewall skips ufw only; UDP port-hopping PREROUTING NAT will still be configured.'
TB_MSG_EN[note_hy2_acme_firewall]='ACME HTTP-01 requires TCP 80 open in both firewall and cloud security group for renewals; certificate refreshes briefly restart %s.'
TB_MSG_EN[note_xhttp_ws_keepalive]='Note: Xray logs a deprecation notice for WebSocket (retained upstream); heartbeatPeriod is active in current Xray.'
TB_MSG_EN[note_xhttp_nginx]='Print Nginx reverse-proxy location snippets with "show --format nginx". Ensure Cloudflare SSL/TLS is "Full (strict)" with gRPC & WebSockets enabled.'
TB_MSG_EN[note_xhttp_mihomo_ver]='Full Clash / Mihomo config: "show --format mihomo" (requires Mihomo >= v1.19.34).'
TB_MSG_EN[note_firewall]='If the provider has its own firewall / security group, open the ports above there as well.'
TB_MSG_EN[note_security_group_udp]='Cloud security group UDP ports required: %s'

TB_MSG_EN[menu_items]='  1) Install or reconfigure a node
  2) Show connection details
  3) Update the core
  4) Rotate credentials
  5) Uninstall
  0) Exit'
TB_MSG_EN[prompt_menu]='Choose'

TB_MSG_EN[usage]='ToastBox %s - VLESS-TCP-REALITY-Vision, VLESS-XHTTP, Shadowsocks 2022 and Hysteria 2 nodes on Xray or sing-box

Usage: toastbox.sh [command] [options]

Run without a command for the interactive menu.

Commands:
  install      Deploy a node, or change the settings of an existing one
  show         Print connection details, share links or client configs
  update       Upgrade the core and restart the node
  rotate       Generate new UUID / keys / passwords
  refresh-cert Refresh imported Hysteria 2 or XHTTP certificates from saved paths
  uninstall    Remove the core and the node
  help, version

Options for install:
  --core xray|sing-box        Core to use (default: xray)
  --protocols LIST            vless, ss, hy2, xhttp, both (vless,ss), all (vless,ss,hy2),
                              or comma-separated combination (default: vless,ss)
  --server-addr ADDR          Address clients connect to (default: detected; optional host fallback for xhttp)
  --name NAME                 Node name used in share links (default: ToastBox)
  --listen ADDR               Bind to this local address (default: all)
  --vless-port PORT           VLESS port (default: 443)
  --reality-sni DOMAIN        REALITY target domain / SNI (required for vless)
  --reality-target HOST:PORT  REALITY target (default: <sni>:443)
  --skip-target-check         Do not probe the REALITY target
  --ss-port PORT              Shadowsocks port (default: random)
  --ss-method METHOD          2022-blake3-aes-128-gcm (default),
                              2022-blake3-aes-256-gcm or
                              2022-blake3-chacha20-poly1305
  --ss-network both|tcp|udp   Shadowsocks listen network (default: both)
  --hy2-port PORT             Hysteria 2 UDP port (default: 443)
  --hy2-sni NAME              Hysteria 2 TLS verification name (SNI)
  --hy2-tls MODE              Hysteria 2 TLS: self-signed (default), files, or acme
  --hy2-cert FILE             Certificate chain PEM to import (--hy2-tls files)
  --hy2-key FILE              Private key PEM to import (--hy2-tls files)
  --hy2-cert-hook MODE        certbot (install deploy hook) or none
  --hy2-acme-domain DOMAIN    Domain for Certbot standalone HTTP-01 (implies acme)
  --hy2-acme-email EMAIL      Account email for Certbot / CA notifications
  --hy2-acme-agree-tos        Accept CA Terms of Service for non-interactive ACME
  --hy2-obfs none|salamander  Hysteria 2 obfuscation (default: none)
  --hy2-masquerade none|URL   HTTP/3 reverse proxy masquerade URL, or none
  --hy2-hop-ports LIST|none   UDP port hopping ranges (e.g. 20000-20100,30000)
  --hy2-hop-interval SEC|MIN-MAX  Port-hop interval in seconds >=5 (default: 30)
  --hy2-renew-cert            Regenerate the self-signed Hysteria 2 certificate
  --xhttp-tls none|files      XHTTP TLS: none (loopback reverse-proxy backend, default) or files
  --xhttp-listen ADDR         XHTTP bind address (loopback for none; default: 127.0.0.1 / ::)
  --xhttp-port PORT           XHTTP listen TCP port (default: 10000 for none, 443 for files)
  --xhttp-public-port PORT    Client-facing HTTPS port when --xhttp-tls none (default: 443)
  --xhttp-host DOMAIN         Public hostname / SNI for XHTTP (or domain --server-addr)
  --xhttp-connect-addr ADDR   Client dial address / CDN preferred IP or domain (empty resets to host)
  --xhttp-path PATH           XHTTP request path (default: random /<slug>)
  --xhttp-mode MODE           Server XHTTP mode: auto (default), packet-up, stream-up or stream-one
  --xhttp-client-mode MODE    Client XHTTP mode: packet-up (default), auto, stream-up or stream-one
  --xhttp-alpn MODE           h2 (default), h3 or http/1.1
  --xhttp-cert FILE           Certificate chain PEM to import (--xhttp-tls files)
  --xhttp-key FILE            Private key PEM to import (--xhttp-tls files)
  --xhttp-cert-hook MODE      certbot (install deploy hook) or none
  --xhttp-ws-keepalive        Enable companion VLESS-WS keep-alive inbound (--no-xhttp-ws-keepalive to disable)
  --xhttp-ws-port PORT        WS listen port (default: 10001 for none, 8443/2053 for files)
  --xhttp-ws-public-port PORT Client-facing HTTPS port for WS when --xhttp-tls none (default: 443)
  --xhttp-ws-path PATH        WS request path (default: random /<slug>)
  --xhttp-ws-heartbeat SEC    Xray WebSocket heartbeatPeriod in seconds (default: 30)
  --tcp-keepalive-idle SEC    Xray TCP keepalive idle (1..32767 seconds)
  --tcp-keepalive-interval SEC  Xray TCP keepalive interval (1..32767 seconds)
  --tcp-user-timeout MS       Xray TCP user timeout (1..2147483647 milliseconds)
                              0 clears one override; unset values keep defaults
  --reset-sockopt             Clear all saved TCP overrides before applying flags
  --block-bt                  Reject BitTorrent traffic (--no-block-bt to undo)
  --allow-private             Allow relaying to private / loopback addresses
                              (--no-allow-private to undo)
  --core-version VERSION      Install this core version instead of the latest
  --no-firewall               Do not touch ufw (hop NAT still applies if enabled)
  --overwrite-config          Replace a configuration ToastBox did not write
                              (--yes alone never does)

Options for show:
  --format FORMAT             text (default), links, json, xray, sing-box, hysteria2, mihomo, nginx
  --protocols LIST            Limit the output to these protocols
  --qr                        Also print QR codes (text format)

Options for uninstall:
  --purge                     Also delete configuration, logs and backups
  --core xray|sing-box        Core to remove when no node state exists

General:
  -y, --yes                   Never prompt; answer yes to confirmations
  --lang en|zh                Language (default: from the locale)
  -h, --help                  Show this help
  -V, --version               Show the version

Settings that are not given on the command line keep their current value
when a node already exists.
'

# ---------------------------------------------------------------------------
# 简体中文
# ---------------------------------------------------------------------------

TB_MSG_ZH[err_root]='此命令需要 root 权限（可使用：sudo bash toastbox.sh ...）。'
TB_MSG_ZH[err_os_version]='不支持 %s %s，需要 %s %s 或更高版本。'
TB_MSG_ZH[err_os_unsupported]='不支持的系统“%s”。ToastBox 支持 Debian 11+ 和 Ubuntu 20.04+。'
TB_MSG_ZH[warn_os_derivative]='“%s”是 Debian/Ubuntu 的衍生发行版，未经测试，将继续执行。'
TB_MSG_ZH[err_arch_unsupported]='不支持的 CPU 架构“%s”，仅支持 amd64 和 arm64。'
TB_MSG_ZH[err_no_systemd]='需要 systemd，但本机未运行 systemd。'
TB_MSG_ZH[info_install_deps]='正在安装依赖：%s'
TB_MSG_ZH[err_apt_update]='apt-get update 执行失败。'
TB_MSG_ZH[err_apt_install]='安装失败：%s'
TB_MSG_ZH[err_download]='下载失败：%s'
TB_MSG_ZH[err_state_corrupt]='状态文件 %s 无法读取或已损坏。'
TB_MSG_ZH[err_no_state]='本机没有 ToastBox 节点，请先执行 install。'
TB_MSG_ZH[err_keypair]='无法使用 %s 生成 REALITY 密钥对。'
TB_MSG_ZH[err_core]='未知内核“%s”，可选 xray 或 sing-box。'
TB_MSG_ZH[err_missing_value]='选项 %s 需要一个值。'
TB_MSG_ZH[err_unknown_arg]='未知参数：%s（参见 --help）。'
TB_MSG_ZH[err_invalid_option]='%s 的值无效：“%s”'
TB_MSG_ZH[err_invalid_value]='无效的值：“%s”'
TB_MSG_ZH[warn_invalid_input]='“%s”无效，请重新输入。'
TB_MSG_ZH[err_protocols]='协议列表“%s”无效，可选 vless、ss、hy2、xhttp、both、all 或逗号分隔组合。'
TB_MSG_ZH[err_protocol_disabled]='此节点未启用协议“%s”。'
TB_MSG_ZH[err_format]='未知格式“%s”，可选 text、links、json、xray、sing-box、hysteria2、mihomo 或 nginx。'
TB_MSG_ZH[err_format_requires_hy2]='格式“hysteria2”要求节点启用并选择了 Hysteria 2 协议。'
TB_MSG_ZH[err_format_singbox_no_xhttp]='格式“sing-box”不支持 VLESS + XHTTP，请改用“xray”或“mihomo”。'
TB_MSG_ZH[warn_singbox_skip_xhttp]='已跳过 sing-box 输出中的 VLESS + XHTTP；请使用“show --format xray”或“show --format mihomo”获取 XHTTP 客户端配置。'
TB_MSG_ZH[warn_singbox_xhttp_ws_only]='sing-box 不支持 VLESS + XHTTP，已仅导出配套的 VLESS + WS 保活节点（完整 XHTTP 请使用“show --format xray”或“show --format mihomo”）。'
TB_MSG_ZH[err_format_requires_xhttp]='格式“nginx”要求节点启用并选择了 VLESS + XHTTP 协议。'
TB_MSG_ZH[err_format_nginx_requires_none]='Nginx location 片段仅在 XHTTP 处于反向代理模式（--xhttp-tls none）时生成。'
TB_MSG_ZH[err_aborted]='已取消，未做任何更改。（使用 --yes 可跳过确认。）'
TB_MSG_ZH[err_sockopt_core]='自定义 TCP sockopt 仅支持 Xray，不支持 %s。切换内核前请用 install --reset-sockopt 清除。'
TB_MSG_ZH[err_sockopt_command]='TCP sockopt 选项仅可用于 install；update 和 rotate 会复用已保存的设置。'
TB_MSG_ZH[err_xhttp_core]='VLESS + XHTTP 仅支持 Xray 内核，不支持 %s。'
TB_MSG_ZH[err_xhttp_command]='XHTTP 选项仅可用于 install；update 和 rotate 会复用已保存的设置。'
TB_MSG_ZH[err_xhttp_not_enabled]='只有在 --protocols 中启用了 XHTTP（xhttp）时才能使用 XHTTP 选项。'
TB_MSG_ZH[err_xhttp_cert_with_none]='--xhttp-cert 与 --xhttp-key 不能与 --xhttp-tls none 同时使用。'
TB_MSG_ZH[err_xhttp_cert_pair_required]='--xhttp-cert 与 --xhttp-key 必须成对提供。'
TB_MSG_ZH[err_xhttp_none_loopback]='XHTTP TLS 模式“none”是供本机反向代理使用的明文 h2c 后端，必须监听回环地址（当前为“%s”）；请使用 127.0.0.1 / ::1，或改用 --xhttp-tls files。'
TB_MSG_ZH[err_xhttp_host_required]='XHTTP 需要提供公网域名（例如 cdn.example.com），请使用 --xhttp-host 指定（或在非纯 IP 时使用域名形式的 --server-addr）。'
TB_MSG_ZH[err_xhttp_files_required]='XHTTP 的 TLS 模式“files”需要提供 --xhttp-cert 和 --xhttp-key。'
TB_MSG_ZH[err_xhttp_cert_pair]='XHTTP 证书 %s 与私钥 %s 无法读取、已过期或不匹配。'
TB_MSG_ZH[err_xhttp_cert_host_mismatch]='XHTTP 证书对“%s”无效。'
TB_MSG_ZH[err_xhttp_tls_invalid]='已保存的 XHTTP 证书或私钥无效或已过期，请用 --xhttp-cert 与 --xhttp-key 重新导入。'
TB_MSG_ZH[err_xhttp_cert_sources_missing]='未记录 XHTTP 外部证书来源路径，请先使用 --xhttp-cert 与 --xhttp-key 重新导入。'
TB_MSG_ZH[err_xhttp_hook_not_none]='--xhttp-cert-hook certbot 不能与 --xhttp-tls none 模式同时使用。'
TB_MSG_ZH[err_xhttp_ws_not_enabled]='使用 XHTTP WebSocket 保活参数（--xhttp-ws-*）需要同时启用 --xhttp-ws-keepalive。'
TB_MSG_ZH[err_xhttp_path_conflict]='XHTTP 路径“%s”与 WebSocket 保活路径“%s”冲突（两者必须不同且不能互为路径前缀）。'
TB_MSG_ZH[warn_xhttp_ws_heartbeat_cf]='XHTTP WS 心跳间隔设为 %s 秒；Cloudflare 代理读取超时为 125 秒，大于 60 秒可能导致空闲长连接断开。'
TB_MSG_ZH[warn_xhttp_alpn_h3]='XHTTP ALPN 设为“h3”：源站仅监听 TCP，客户端必须经由已开启 HTTP/3（QUIC）的 CDN 边缘节点（如 Cloudflare）连接，不能直连源站。'
TB_MSG_ZH[warn_xhttp_ws_port_conflict]='XHTTP WS 默认端口 %s/tcp 与本节点其他 TCP 端口冲突，已自动改用备用端口 %s/tcp。'
TB_MSG_ZH[warn_xhttp_ws_port_busy]='XHTTP WS 默认端口 %s/tcp 已被占用，已自动改用备用端口 %s/tcp。'
TB_MSG_ZH[err_hy2_command]='Hysteria 2 选项仅可用于 install；update 和 rotate 会复用已保存的设置。'
TB_MSG_ZH[err_hy2_cert_with_self_signed]='--hy2-cert 与 --hy2-key 不能与 --hy2-tls self-signed 同时使用。'
TB_MSG_ZH[err_hy2_cert_pair_required]='--hy2-cert 与 --hy2-key 必须成对提供。'
TB_MSG_ZH[err_hy2_renew_not_self_signed]='--hy2-renew-cert 仅可用于 --hy2-tls self-signed。'
TB_MSG_ZH[err_hy2_files_required]='Hysteria 2 的 TLS 模式“files”需要提供 --hy2-cert 和 --hy2-key。'
TB_MSG_ZH[err_hy2_cert_pair]='证书 %s 与私钥 %s 无法读取、已过期或不匹配。'
TB_MSG_ZH[err_hy2_sni_required]='无法从证书推断 Hysteria 2 的验证域名，请使用 --hy2-sni 指定。'
TB_MSG_ZH[err_hy2_cert_sni_mismatch]='Hysteria 2 证书对“%s”无效。'
TB_MSG_ZH[err_hy2_tls_invalid]='已保存的 Hysteria 2 证书或私钥无效或已过期，请用 --hy2-cert 与 --hy2-key 重新导入。'
TB_MSG_ZH[err_hy2_tls_gen]='无法为 Hysteria 2 生成自签 TLS 证书。'
TB_MSG_ZH[err_hy2_not_enabled]='只有在 --protocols 中启用了 Hysteria 2（hy2）时才能使用 Hysteria 2 选项。'
TB_MSG_ZH[err_hy2_hook_not_self_signed]='--hy2-cert-hook certbot 不能与 --hy2-tls self-signed 模式同时使用。'
TB_MSG_ZH[err_hy2_cert_sources_missing]='未记录 Hysteria 2 外部证书来源路径，请先使用 --hy2-cert 与 --hy2-key 重新导入。'
TB_MSG_ZH[err_hy2_hook_certbot_paths]='Certbot 钩子要求证书与私钥来自成对的 %s/<lineage>/fullchain.pem 与 privkey.pem。'
TB_MSG_ZH[err_hy2_foreign_hook]='拒绝覆盖非 ToastBox 管理的部署钩子：%s'
TB_MSG_ZH[err_hy2_hook_needs_self]='启用 --hy2-cert-hook 需要先将持久化入口安装到 %s；请先使用单文件 toastbox.sh 执行安装。'
TB_MSG_ZH[err_hy2_hook_install]='无法安装 Certbot 部署钩子：%s'
TB_MSG_ZH[err_hy2_acme_with_files]='ACME 自动签发模式不能与 --hy2-cert 或 --hy2-key 同时使用。'
TB_MSG_ZH[err_hy2_acme_tls_conflict]='ACME 参数（--hy2-acme-*）只能与 --hy2-tls acme 配合使用。'
TB_MSG_ZH[err_hy2_acme_requires_hook]='ACME 自动签发需要自动续期同步，--hy2-cert-hook none 不能与 --hy2-tls acme 同时使用。'
TB_MSG_ZH[err_hy2_acme_domain_required]='ACME 自动签发需要提供域名（请指定 --hy2-acme-domain 或域名形式的 --server-addr）。'
TB_MSG_ZH[err_hy2_acme_email_required]='ACME 自动签发需要提供账户邮箱（--hy2-acme-email）。'
TB_MSG_ZH[err_hy2_acme_tos_required]='ACME 自动签发需要明确同意 CA 服务条款（--hy2-acme-agree-tos）。'
TB_MSG_ZH[err_hy2_acme_port80_conflict]='Certbot standalone HTTP-01 需要占用 TCP 80 端口，与已配置的 TCP 80 监听端口冲突。'
TB_MSG_ZH[err_hy2_acme_port80_busy]='TCP 80 端口已被占用：%s。Certbot standalone 验证需要空闲的 80 端口，ToastBox 不会自动停止现有服务；若同机已有网站，请改用 --hy2-cert 与 --hy2-key 导入已有证书。'
TB_MSG_ZH[err_hy2_acme_dns_unresolvable]='域名 %s 在 DNS 中无法解析到任何 IP 地址，请先将 A/AAAA 记录指向本服务器后再使用 ACME。'
TB_MSG_ZH[err_hy2_acme_dns_private]='域名 %s 仅解析到非公网 IP（%s）；Let'\''s Encrypt HTTP-01 公网验证要求解析到公网 IP。'
TB_MSG_ZH[warn_hy2_acme_dns_mismatch]='域名 %s 解析结果为 %s，与 --server-addr（%s）不一致。'
TB_MSG_ZH[warn_hy2_acme_no_ecdsa_flag]='当前 certbot 版本不支持 --key-type ecdsa 参数，将继续使用其默认密钥类型。'
TB_MSG_ZH[err_hy2_acme_certbot_install]='无法自动安装 certbot。'
TB_MSG_ZH[info_hy2_acme_issuing]='正在通过 Certbot standalone 为 %s 申请公共 TLS 证书（lineage %s）……'
TB_MSG_ZH[err_hy2_acme_issue]='Certbot standalone 为 %s 申请证书失败；已保留现有可用节点配置。'
TB_MSG_ZH[ok_hy2_acme_issued]='已为 %s 签发公共 TLS 证书（lineage %s）。'
TB_MSG_ZH[info_hy2_acme_reuse_cert]='复用已有的有效 Certbot 证书：%s（%s）。'
TB_MSG_ZH[info_hy2_acme_reuse_system_timer]='检测到系统已有运行中的 Certbot 续期定时器，直接复用。'
TB_MSG_ZH[ok_hy2_acme_timer_enabled]='已为 %s（lineage %s）启用 ToastBox 限定范围续期定时器。'
TB_MSG_ZH[err_hy2_acme_timer]='配置 ToastBox Certbot 续期定时器失败。'
TB_MSG_ZH[err_hy2_hop_interval_requires_ports]='--hy2-hop-interval 需要同时或事先通过 --hy2-hop-ports 开启端口跳跃。'
TB_MSG_ZH[err_hy2_hop_ss_conflict]='UDP 端口跳跃范围（%s）与 Shadowsocks UDP 端口 %s 冲突。'
TB_MSG_ZH[err_hy2_hop_ports_in_use]='Hysteria 2 跳跃端口已被占用：%s'
TB_MSG_ZH[err_hy2_hop_loopback]='监听在回环地址（%s）时不支持 Hysteria 2 UDP 端口跳跃。'
TB_MSG_ZH[err_hy2_hop_no_backend]='Hysteria 2 UDP 端口跳跃需要 nftables（nft）或 iptables。'
TB_MSG_ZH[err_hy2_hop_no_cmd]='Hysteria 2 UDP 端口跳跃需要“%s”命令。'
TB_MSG_ZH[err_hy2_hop_apply]='配置 Hysteria 2 UDP 端口跳跃 NAT 规则失败。'
TB_MSG_ZH[err_refresh_options]='refresh-cert 不接受安装或展示参数（仅支持 --yes / --lang）。'
TB_MSG_ZH[err_refresh_requires_protocol]='此节点未启用 Hysteria 2，也未启用需要外部证书的 XHTTP TLS 模式。'
TB_MSG_ZH[err_refresh_requires_files]='refresh-cert 仅适用于 Hysteria 2 或 XHTTP 的 files 证书模式。'
TB_MSG_ZH[info_cert_unchanged]='证书链与私钥内容未变化，无需重启。'
TB_MSG_ZH[ok_cert_refreshed]='TLS 证书已刷新。'
TB_MSG_ZH[err_lock_open]='无法打开操作锁 %s。'
TB_MSG_ZH[err_lock_busy]='另一项 ToastBox 操作正在持有锁 %s。'

TB_MSG_ZH[prompt_core]='内核：1) xray  2) sing-box'
TB_MSG_ZH[prompt_protocols]='协议：1) VLESS+SS  2) 仅 VLESS  3) 仅 SS  4) 仅 Hysteria 2  5) VLESS+SS+Hy2（all）  6) 仅 XHTTP（或逗号分隔）'
TB_MSG_ZH[info_detect_addr]='正在检测本机公网地址……'
TB_MSG_ZH[err_server_addr_required]='无法检测公网地址，请用 --server-addr 指定。'
TB_MSG_ZH[prompt_server_addr]='客户端连接所用的地址（IP 或域名）'
TB_MSG_ZH[prompt_vless_port]='VLESS 端口'
TB_MSG_ZH[help_reality_sni]='
REALITY 会借用一个真实网站（“目标站”）的 TLS 身份。
请选择满足以下条件的网站：
  - 支持 TLS 1.3 和 HTTP/2；
  - 不在 Cloudflare 等 CDN 之后：未通过 REALITY 认证的连接会被原样
    转发到目标站，选用 CDN 站点会让本机变成该 CDN 的免费转发节点；
  - 最好与本机位于同一网络（ASN）。
'
TB_MSG_ZH[prompt_reality_sni]='REALITY 目标域名（SNI），例如 www.example.com'
TB_MSG_ZH[err_sni_required]='必须提供 REALITY 目标域名，请用 --reality-sni 指定。'
TB_MSG_ZH[info_probing_target]='正在探测 REALITY 目标站 %s（SNI %s）……'
TB_MSG_ZH[ok_target]='%s 支持 TLS 1.3，证书有效。'
TB_MSG_ZH[warn_target_no_h2]='%s 未协商 HTTP/2。可以使用，但支持 HTTP/2 的站点伪装效果更好。'
TB_MSG_ZH[err_target_unreachable]='本机无法连接到 %s。'
TB_MSG_ZH[err_target_no_tls13]='%s 不支持 TLS 1.3，而 REALITY 需要 TLS 1.3。'
TB_MSG_ZH[err_target_cert]='%s 的证书对 %s 无效。'
TB_MSG_ZH[prompt_target_anyway]='仍然使用这个目标站？'
TB_MSG_ZH[err_target_rejected]='REALITY 目标站未通过检查。请换一个，或使用 --skip-target-check 跳过探测。'
TB_MSG_ZH[prompt_ss_port]='Shadowsocks 端口'
TB_MSG_ZH[prompt_ss_method]='Shadowsocks 加密方式：1) 2022-blake3-aes-128-gcm  2) 2022-blake3-aes-256-gcm  3) 2022-blake3-chacha20-poly1305'
TB_MSG_ZH[prompt_hy2_port]='Hysteria 2 UDP 端口'
TB_MSG_ZH[prompt_hy2_tls]='Hysteria 2 TLS：1) 自签证书（self-signed）  2) 导入证书文件（files）  3) Certbot 自动申请公共证书（acme）'
TB_MSG_ZH[prompt_hy2_acme_domain]='用于 ACME 公共证书的域名（需提前解析到本服务器）'
TB_MSG_ZH[prompt_hy2_acme_email]='用于 Let'\''s Encrypt / Certbot 通知的邮箱'
TB_MSG_ZH[prompt_hy2_acme_tos]='是否同意 Let'\''s Encrypt 服务条款以自动申请公共证书？'
TB_MSG_ZH[prompt_hy2_cert]='TLS 证书链 PEM 文件路径'
TB_MSG_ZH[prompt_hy2_key]='TLS 私钥 PEM 文件路径'
TB_MSG_ZH[prompt_hy2_sni]='Hysteria 2 TLS 证书验证名称（SNI）'
TB_MSG_ZH[prompt_hy2_obfs]='Hysteria 2 混淆：1) 无（none）  2) salamander'
TB_MSG_ZH[prompt_xhttp_tls]='XHTTP TLS：1) none（回环明文后端，配合本机反向代理，默认）  2) files（导入源站或公共证书，直接监听 443/8443 TLS）'
TB_MSG_ZH[prompt_xhttp_host]='XHTTP 公网域名（Host / SNI），例如 edge.example.com'
TB_MSG_ZH[prompt_xhttp_port]='XHTTP 监听 TCP 端口'
TB_MSG_ZH[prompt_xhttp_connect_addr]='客户端直连 / Cloudflare 优选域名或 IP（留空则与公网域名相同）'
TB_MSG_ZH[prompt_xhttp_cert]='XHTTP TLS 证书链 PEM 文件路径（如 Cloudflare Origin CA）'
TB_MSG_ZH[prompt_xhttp_key]='XHTTP TLS 私钥 PEM 文件路径'
TB_MSG_ZH[prompt_xhttp_ws_keepalive]='是否同时启用辅助 VLESS-WS 保活入站，用于长连接保活（如 ChatGPT 桌面端 / 空闲 SSH）？'
TB_MSG_ZH[err_no_free_port]='找不到空闲端口，请用 --ss-port 指定。'
TB_MSG_ZH[err_port_same]='两个 TCP 监听不能同时绑定到端口 %s。'
TB_MSG_ZH[err_port_same_udp]='Hysteria 2 和 Shadowsocks 不能同时监听 UDP 端口 %s。'
TB_MSG_ZH[err_port_in_use]='端口 %s 已被占用：%s'
TB_MSG_ZH[plan_title]='即将部署：'
TB_MSG_ZH[prompt_proceed]='继续？'

TB_MSG_ZH[warn_core_switch]='内核将由 %s 切换为 %s，新内核就绪后 %s 服务会被停止并禁用。'
TB_MSG_ZH[prompt_overwrite_config]='%s 中已有一份并非由 ToastBox 生成的配置。是否替换？（会保留备份。）'
TB_MSG_ZH[err_foreign_config]='已保留现有配置 %s。如需替换，请加上 --overwrite-config 重新运行。'
TB_MSG_ZH[info_installing_core]='正在从官方渠道安装 %s……'
TB_MSG_ZH[err_core_install]='安装 %s 失败。'
TB_MSG_ZH[err_core_too_old]='%s %s 版本过旧：ToastBox 需要 %s 或更高版本。请执行 update 升级。'
TB_MSG_ZH[err_core_version_too_old]='指定的 %s %s 版本过旧：ToastBox 需要 %s 或更高版本。'
TB_MSG_ZH[warn_core_rolled_back]='已恢复之前的 %s 二进制文件。'
TB_MSG_ZH[ok_core_ready]='%s %s 已安装。'
TB_MSG_ZH[err_render]='无法生成配置。'
TB_MSG_ZH[err_validate]='%s 未通过对生成配置的校验，未做任何更改。'
TB_MSG_ZH[err_backup_config]='无法备份现有配置 %s。'
TB_MSG_ZH[err_install_config]='无法将配置写入 %s。'
TB_MSG_ZH[err_rollback_config]='无法恢复 %s（备份：%s）。'
TB_MSG_ZH[err_state_save]='无法将节点状态保存到 %s。'
TB_MSG_ZH[err_xray_dynamic_user]='服务 %s 启用了 DynamicUser 且没有静态用户组，拒绝将 %s 设为所有用户可读。'
TB_MSG_ZH[err_xray_service_user]='服务 %s 配置了不存在的用户“%s”。'
TB_MSG_ZH[info_restarting]='正在重启 %s……'
TB_MSG_ZH[ok_service_running]='%s 正在运行。'
TB_MSG_ZH[err_service_start]='%s 使用新配置启动失败。最近的日志：'
TB_MSG_ZH[warn_rolled_back]='已从 %s 恢复之前的配置。'
TB_MSG_ZH[warn_service_stopped]='%s 在本次更改之前并未运行，现已保持停止状态。'
TB_MSG_ZH[info_service_kept_stopped]='%s 当前处于停止状态，已仅更新磁盘配置与状态。'
TB_MSG_ZH[warn_old_core_restored]='已重新启动之前的 %s 服务。'
TB_MSG_ZH[err_apply]='配置未生效。'
TB_MSG_ZH[info_fw_opened]='防火墙（ufw）：已放行 %s'
TB_MSG_ZH[info_fw_closed]='防火墙（ufw）：已移除规则 %s'
TB_MSG_ZH[warn_extra_configs]='sing-box 会合并配置目录下的所有 JSON 文件，以下文件也会被加载：%s'
TB_MSG_ZH[warn_clock]='系统时钟未与 NTP 同步。两端时间相差过大时 Shadowsocks 2022 会拒绝连接，请开启时间同步（例如 timedatectl set-ntp true）。'
TB_MSG_ZH[ok_installed]='节点部署完成。'
TB_MSG_ZH[ok_self_installed]='已将本脚本安装为 %s，之后可用 toastbox <命令> 管理节点。'
TB_MSG_ZH[ok_updated]='%s 已更新到 %s。'
TB_MSG_ZH[prompt_rotate]='重新生成凭据？所有现有客户端在重新配置前都将无法连接。'
TB_MSG_ZH[ok_rotated]='新凭据已生效。'
TB_MSG_ZH[prompt_uninstall]='移除 %s 和此节点？（配置文件会保留。）'
TB_MSG_ZH[prompt_uninstall_purge]='移除 %s、此节点及其全部配置、日志和备份？'
TB_MSG_ZH[err_remove_failed]='移除 %s 失败，已保留节点状态，请查看上方输出。'
TB_MSG_ZH[ok_uninstalled]='%s 和 ToastBox 节点已移除。'
TB_MSG_ZH[ok_core_removed]='%s 已移除，运行在 %s 上的节点不受影响。'
TB_MSG_ZH[warn_no_qrencode]='qrencode 不可用，跳过二维码。'

TB_MSG_ZH[word_running]='运行中'
TB_MSG_ZH[word_stopped]='未运行'
TB_MSG_ZH[label_core]='内核'
TB_MSG_ZH[label_server]='服务器地址'
TB_MSG_ZH[label_config]='服务端配置'
TB_MSG_ZH[label_sockopt]='TCP sockopt（Xray 入站）'
TB_MSG_ZH[label_port]='端口'
TB_MSG_ZH[label_uuid]='UUID'
TB_MSG_ZH[label_flow]='流控（flow）'
TB_MSG_ZH[label_sni]='SNI'
TB_MSG_ZH[label_target]='目标站'
TB_MSG_ZH[label_public_key]='公钥（password）'
TB_MSG_ZH[label_short_id]='Short ID'
TB_MSG_ZH[label_fingerprint]='指纹'
TB_MSG_ZH[label_method]='加密方式'
TB_MSG_ZH[label_password]='密码'
TB_MSG_ZH[label_tls]='TLS'
TB_MSG_ZH[label_cert_file]='证书文件'
TB_MSG_ZH[label_cert_hook]='部署钩子'
TB_MSG_ZH[label_pin_sha256]='证书指纹（SHA-256）'
TB_MSG_ZH[label_obfs]='混淆'
TB_MSG_ZH[label_obfs_password]='混淆密码'
TB_MSG_ZH[label_masquerade]='网页伪装'
TB_MSG_ZH[label_hop_ports]='跳跃端口'
TB_MSG_ZH[label_hop_interval]='跳跃间隔'
TB_MSG_ZH[label_acme_domain]='ACME 域名'
TB_MSG_ZH[label_acme_lineage]='ACME 谱系'
TB_MSG_ZH[label_backend]='后端监听'
TB_MSG_ZH[label_connect_addr]='连接地址'
TB_MSG_ZH[label_host]='域名（Host）'
TB_MSG_ZH[label_path]='路径（Path）'
TB_MSG_ZH[label_xhttp_mode]='XHTTP 模式'
TB_MSG_ZH[label_alpn]='ALPN'
TB_MSG_ZH[label_ws_heartbeat]='WS 心跳'
TB_MSG_ZH[label_link]='分享链接：'
TB_MSG_ZH[note_ss_landing]='注意：Shadowsocks 没有 TLS 伪装，适合作为中转之后的落地节点，不适合直接穿越审查防火墙。'
TB_MSG_ZH[note_client_configs]='客户端配置：show --format xray、show --format sing-box、show --format hysteria2 或 show --format mihomo；仅链接：show --format links；二维码：show --qr。'
TB_MSG_ZH[note_hy2_hop_clients]='端口跳跃客户端要求：Hysteria app/v2.14.0+、Xray 26.11.9+（udphop）或 sing-box 1.11.0+。'
TB_MSG_ZH[note_hy2_hop_random_clients]='随机间隔跳跃客户端要求：Hysteria app/v2.14.0+、Xray 26.11.9+（udphop）或 sing-box 1.14.0+（hop_interval_max）。'
TB_MSG_ZH[note_hop_no_firewall]='注意：--no-firewall 仅跳过 ufw；若开启端口跳跃，仍会配置必需的 PREROUTING NAT 转发规则。'
TB_MSG_ZH[note_hy2_acme_firewall]='ACME HTTP-01 自动续期需要防火墙与云安全组均保持放行 TCP 80；证书刷新时会重启 %s（连接短暂中断）。'
TB_MSG_ZH[note_xhttp_ws_keepalive]='注意：Xray 启动时会对 WebSocket 传输层打印弃用提示（官方保留不移除），当前主线中 heartbeatPeriod 正常生效。'
TB_MSG_ZH[note_xhttp_nginx]='使用“show --format nginx”查看 Nginx 反代 location 片段；请确认 Cloudflare 已开启 gRPC 与 WebSockets 并将 SSL/TLS 设为“完全（严格）”。'
TB_MSG_ZH[note_xhttp_mihomo_ver]='完整 Clash / Mihomo 配置：“show --format mihomo”（需 Mihomo >= v1.19.34）。'
TB_MSG_ZH[note_firewall]='如果服务商另有防火墙 / 安全组，请在那里同样放行上述端口。'
TB_MSG_ZH[note_security_group_udp]='云厂商安全组需放行的 UDP 端口：%s'

TB_MSG_ZH[menu_items]='  1) 安装或重新配置节点
  2) 查看连接信息
  3) 更新内核
  4) 重新生成凭据
  5) 卸载
  0) 退出'
TB_MSG_ZH[prompt_menu]='请选择'

TB_MSG_ZH[usage]='ToastBox %s - 基于 Xray 或 sing-box 部署 VLESS-TCP-REALITY-Vision、VLESS-XHTTP、Shadowsocks 2022 与 Hysteria 2 节点

用法：toastbox.sh [命令] [选项]

不带命令运行将进入交互菜单。

命令：
  install      部署节点，或修改现有节点的设置
  show         显示连接信息、分享链接或客户端配置
  update       升级内核并重启节点
  rotate       重新生成 UUID / 密钥 / 密码
  refresh-cert 从已登记来源刷新 Hysteria 2 或 XHTTP 证书与私钥
  uninstall    移除内核和节点
  help, version

install 的选项：
  --core xray|sing-box        使用的内核（默认：xray）
  --protocols LIST            vless、ss、hy2、xhttp、both（vless,ss）、all（vless,ss,hy2），
                              或逗号分隔组合（默认：vless,ss）
  --server-addr ADDR          客户端连接所用的地址（默认：自动检测；xhttp 可直接继承域名）
  --name NAME                 分享链接中的节点名称（默认：ToastBox）
  --listen ADDR               绑定到指定的本机地址（默认：全部）
  --vless-port PORT           VLESS 端口（默认：443）
  --reality-sni DOMAIN        REALITY 目标域名 / SNI（启用 vless 时必填）
  --reality-target HOST:PORT  REALITY 目标站（默认：<sni>:443）
  --skip-target-check         不探测 REALITY 目标站
  --ss-port PORT              Shadowsocks 端口（默认：随机）
  --ss-method METHOD          2022-blake3-aes-128-gcm（默认）、
                              2022-blake3-aes-256-gcm 或
                              2022-blake3-chacha20-poly1305
  --ss-network both|tcp|udp   Shadowsocks 监听的网络（默认：both）
  --hy2-port PORT             Hysteria 2 UDP 端口（默认：443）
  --hy2-sni NAME              Hysteria 2 TLS 证书验证名称（SNI）
  --hy2-tls MODE              Hysteria 2 TLS：self-signed（默认）、files 或 acme
  --hy2-cert FILE             导入的证书链 PEM 文件（--hy2-tls files）
  --hy2-key FILE              导入的私钥 PEM 文件（--hy2-tls files）
  --hy2-cert-hook MODE        certbot（安装续期部署钩子）或 none
  --hy2-acme-domain DOMAIN    Certbot standalone HTTP-01 申请域名（隐含 acme）
  --hy2-acme-email EMAIL      Certbot / CA 账户通知邮箱
  --hy2-acme-agree-tos        非交互 ACME 签发时同意 CA 服务条款
  --hy2-obfs none|salamander  Hysteria 2 混淆方式（默认：none）
  --hy2-masquerade none|URL   HTTP/3 反向代理伪装 URL，或 none 清除
  --hy2-hop-ports LIST|none   UDP 端口跳跃范围（如 20000-20100,30000）
  --hy2-hop-interval SEC|MIN-MAX  端口跳跃间隔（整数秒 >=5，默认 30）
  --hy2-renew-cert            重新签发自签 Hysteria 2 证书
  --xhttp-tls none|files      XHTTP TLS：none（回环反代后端，默认）或 files
  --xhttp-listen ADDR         XHTTP 绑定地址（none 须为回环；默认 127.0.0.1 / ::）
  --xhttp-port PORT           XHTTP 监听 TCP 端口（none 默认 10000，files 默认 443）
  --xhttp-public-port PORT    none 模式下客户端对外 HTTPS 端口（默认 443）
  --xhttp-host DOMAIN         XHTTP 公网域名 / SNI（或域名形式的 --server-addr）
  --xhttp-connect-addr ADDR   客户端优选连接域名/IP（传空值可恢复与 host 相同）
  --xhttp-path PATH           XHTTP 请求路径（默认：随机 /<slug>）
  --xhttp-mode MODE           服务端 XHTTP 模式：auto（默认）、packet-up、stream-up 或 stream-one
  --xhttp-client-mode MODE    客户端 XHTTP 模式：packet-up（默认）、auto、stream-up 或 stream-one
  --xhttp-alpn MODE           h2（默认）、h3 或 http/1.1
  --xhttp-cert FILE           导入的 XHTTP 证书链 PEM 文件（--xhttp-tls files）
  --xhttp-key FILE            导入的 XHTTP 私钥 PEM 文件（--xhttp-tls files）
  --xhttp-cert-hook MODE      certbot（安装续期部署钩子）或 none
  --xhttp-ws-keepalive        启用辅助 VLESS-WS 保活入站（--no-xhttp-ws-keepalive 关闭）
  --xhttp-ws-port PORT        WS 监听端口（none 默认 10001，files 默认 8443/2053）
  --xhttp-ws-public-port PORT none 模式下 WS 对外 HTTPS 端口（默认 443）
  --xhttp-ws-path PATH        WS 请求路径（默认：随机 /<slug>）
  --xhttp-ws-heartbeat SEC    Xray WebSocket heartbeatPeriod 秒数（默认：30）
  --tcp-keepalive-idle SEC    Xray TCP 保活空闲时间（1..32767 秒）
  --tcp-keepalive-interval SEC  Xray TCP 保活探测间隔（1..32767 秒）
  --tcp-user-timeout MS       Xray TCP 用户超时（1..2147483647 毫秒）
                              0 清除单项覆盖；未设置时沿用默认值
  --reset-sockopt             清除已保存的 TCP 覆盖，再应用本次显式参数
  --block-bt                  拒绝 BitTorrent 流量（--no-block-bt 取消）
  --allow-private             允许转发到私有 / 回环地址
                              （--no-allow-private 取消）
  --core-version VERSION      安装指定版本的内核，而不是最新版
  --no-firewall               不修改 ufw（启用跳跃时仍会配置 NAT）
  --overwrite-config          替换并非由 ToastBox 生成的现有配置
                              （仅有 --yes 不会替换）

show 的选项：
  --format FORMAT             text（默认）、links、json、xray、sing-box、hysteria2、mihomo、nginx
  --protocols LIST            只输出指定的协议
  --qr                        同时输出二维码（text 格式）

uninstall 的选项：
  --purge                     同时删除配置、日志和备份
  --core xray|sing-box        没有节点状态时指定要移除的内核

通用选项：
  -y, --yes                   不提示，对所有确认回答“是”
  --lang en|zh                语言（默认：取自系统 locale）
  -h, --help                  显示本帮助
  -V, --version               显示版本

节点已存在时，命令行未给出的设置保持当前值。
'
