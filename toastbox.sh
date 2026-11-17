#!/usr/bin/env bash
#
# ToastBox - deploy VLESS-TCP-REALITY-Vision and Shadowsocks-2022 nodes
# with Xray or sing-box on Debian / Ubuntu.
#
# https://github.com/Claudedu-dev/ToastBox
#
# GENERATED FILE - DO NOT EDIT.
# Built from src/ by scripts/build.sh; change the sources and rebuild.

set -euo pipefail

TB_BUILT=1

# ===== src/lib/00-core.sh =====
#
# Constants, logging and small helpers shared by every module.

TB_VERSION="0.1.0"

# Oldest core versions whose configuration format matches what ToastBox
# writes. Xray renamed inbound `clients` to `users` in v26.5.9 and
# `streamSettings.network` to `method` in v26.7.11. sing-box 1.12 is the
# first release with the rule actions and DNS layout used here.
TB_XRAY_MIN_VERSION="26.7.11"
TB_SINGBOX_MIN_VERSION="1.12.0"

TB_XRAY_INSTALLER_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
TB_SINGBOX_KEY_URL="https://sing-box.app/gpg.key"
TB_SINGBOX_APT_URL="https://deb.sagernet.org/"

# Paths. The TOASTBOX_* overrides exist for the test-suite.
TB_STATE_DIR="${TOASTBOX_STATE_DIR:-/etc/toastbox}"
TB_STATE_FILE="$TB_STATE_DIR/state.json"
TB_BACKUP_DIR="$TB_STATE_DIR/backup"
if [[ -n "${TOASTBOX_LOCK_FILE:-}" ]]; then
  TB_LOCK_FILE="$TOASTBOX_LOCK_FILE"
elif [[ -n "${TOASTBOX_STATE_DIR:-}" ]]; then
  TB_LOCK_FILE="$TB_STATE_DIR.lock"
else
  TB_LOCK_FILE="/run/toastbox/operation.lock"
fi
TB_XRAY_BIN="${TOASTBOX_XRAY_BIN:-/usr/local/bin/xray}"
TB_XRAY_CONFIG="${TOASTBOX_XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
TB_SINGBOX_BIN="${TOASTBOX_SINGBOX_BIN:-/usr/bin/sing-box}"
TB_SINGBOX_CONFIG="${TOASTBOX_SINGBOX_CONFIG:-/etc/sing-box/config.json}"
TB_SINGBOX_KEYRING="/etc/apt/keyrings/sagernet.asc"
TB_SINGBOX_APT_SOURCE="/etc/apt/sources.list.d/sagernet.sources"
TB_SELF_PATH="${TOASTBOX_SELF_PATH:-/usr/local/bin/toastbox}"
TB_CERTBOT_LIVE_DIR="${TOASTBOX_CERTBOT_LIVE_DIR:-/etc/letsencrypt/live}"
TB_CERTBOT_HOOK_PATH="${TOASTBOX_CERTBOT_HOOK_PATH:-/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh}"
TB_CERTBOT_HOOK_MARKER="# Managed by ToastBox (hy2-certbot-hook)"
TB_HY2_HOP_HELPER="${TOASTBOX_HY2_HOP_HELPER:-/usr/local/libexec/toastbox-hy2-hop}"
TB_HY2_HOP_STATE="${TOASTBOX_HY2_HOP_STATE:-$TB_STATE_DIR/hy2-hop.json}"
TB_SYSTEMD_DIR="${TOASTBOX_SYSTEMD_DIR:-/etc/systemd/system}"
TB_HY2_HOP_SERVICE="toastbox-hy2-hop.service"
TB_HY2_ACME_SERVICE="toastbox-hy2-certbot.service"
TB_HY2_ACME_TIMER="toastbox-hy2-certbot.timer"

TB_SS_METHODS=(
  "2022-blake3-aes-128-gcm"
  "2022-blake3-aes-256-gcm"
  "2022-blake3-chacha20-poly1305"
)

# Destinations that a public node should not relay to: loopback, RFC 1918,
# CGNAT, link-local (cloud metadata lives there), benchmarking, multicast,
# reserved, and the IPv6 equivalents.
TB_PRIVATE_CIDRS=(
  "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8"
  "169.254.0.0/16" "172.16.0.0/12" "192.0.0.0/24" "192.168.0.0/16"
  "198.18.0.0/15" "224.0.0.0/3"
  "::/127" "fc00::/7" "fe80::/10" "ff00::/8"
)

TB_LANG=""
TB_TMP=""

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

tb_setup_colors() {
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    TB_C_RED=$'\033[31m' TB_C_GREEN=$'\033[32m' TB_C_YELLOW=$'\033[33m'
    TB_C_CYAN=$'\033[36m' TB_C_BOLD=$'\033[1m' TB_C_RESET=$'\033[0m'
  else
    TB_C_RED="" TB_C_GREEN="" TB_C_YELLOW="" TB_C_CYAN="" TB_C_BOLD="" TB_C_RESET=""
  fi
}
tb_setup_colors

# All diagnostics go to stderr so that stdout only ever carries data
# (share links, JSON), which keeps `toastbox show --format json | jq` usable.
log_info() { printf '%s[*]%s %s\n' "$TB_C_CYAN" "$TB_C_RESET" "$(msg "$@")" >&2; }
log_ok() { printf '%s[+]%s %s\n' "$TB_C_GREEN" "$TB_C_RESET" "$(msg "$@")" >&2; }
log_warn() { printf '%s[!]%s %s\n' "$TB_C_YELLOW" "$TB_C_RESET" "$(msg "$@")" >&2; }
log_err() { printf '%s[x]%s %s\n' "$TB_C_RED" "$TB_C_RESET" "$(msg "$@")" >&2; }

die() {
  log_err "$@"
  exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

tb_mktemp_dir() {
  if [[ -z "$TB_TMP" ]]; then
    TB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/toastbox.XXXXXXXX")"
    chmod 700 "$TB_TMP"
  fi
}

tb_cleanup() {
  if declare -F tb_release_lock >/dev/null 2>&1; then
    tb_release_lock
  fi
  if [[ -n "$TB_TMP" && -d "$TB_TMP" ]]; then
    rm -rf "$TB_TMP"
  fi
}

# ver_ge A B: true when version A >= version B. Pre-release suffixes
# ("1.15.0-alpha.3") are compared by their numeric part only.
ver_ge() {
  local a="${1#v}" b="${2#v}"
  a="${a%%-*}" b="${b%%-*}"
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" == "$b" ]]
}

# install_owned MODE OWNER GROUP SRC DEST: like install(1), owned by OWNER:GROUP.
# Ownership is only set when running as root, which is always the case in
# production; the test-suite runs unprivileged.
install_owned() {
  local mode="$1" owner="$2" group="$3" src="$4" dest="$5"
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m "$mode" -o "$owner" -g "$group" "$src" "$dest"
  else
    install -m "$mode" "$src" "$dest"
  fi
}

tb_download() {
  local url="$1" dest="$2"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$dest" "$url"
}

# join_by SEP ITEM...
join_by() {
  local sep="$1" out="" item
  shift
  for item in "$@"; do
    out+="${out:+$sep}$item"
  done
  printf '%s' "$out"
}

# in_list NEEDLE ITEM...
in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# ===== src/lib/10-i18n.sh =====
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
TB_MSG_EN[err_protocols]='Invalid protocol list "%s". Use vless, ss, hy2, both, all or comma-separated combinations.'
TB_MSG_EN[err_protocol_disabled]='Protocol "%s" is not enabled on this node.'
TB_MSG_EN[err_format]='Unknown format "%s". Use text, links, json, xray, sing-box or hysteria2.'
TB_MSG_EN[err_format_requires_hy2]='Format "hysteria2" requires Hysteria 2 to be enabled and selected.'
TB_MSG_EN[err_aborted]='Aborted. Nothing was changed. (Use --yes to confirm without a prompt.)'
TB_MSG_EN[err_sockopt_core]='Custom TCP sockopt is supported only by Xray, not %s. Use install --reset-sockopt to clear it before switching cores.'
TB_MSG_EN[err_sockopt_command]='TCP sockopt options are only accepted with install; update and rotate reuse the saved settings.'
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
TB_MSG_EN[err_hy2_acme_port80_conflict]='Certbot standalone HTTP-01 requires TCP port 80, which conflicts with the configured VLESS or Shadowsocks TCP port 80.'
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
TB_MSG_EN[err_refresh_requires_hy2]='Hysteria 2 is not enabled on this node.'
TB_MSG_EN[err_refresh_requires_files]='refresh-cert requires Hysteria 2 TLS mode "files".'
TB_MSG_EN[info_hy2_cert_unchanged]='Hysteria 2 certificate chain and key are unchanged; no restart needed.'
TB_MSG_EN[ok_hy2_cert_refreshed]='Hysteria 2 certificate was refreshed.'
TB_MSG_EN[err_lock_open]='Could not open operation lock %s.'
TB_MSG_EN[err_lock_busy]='Another ToastBox operation holds the lock %s.'

TB_MSG_EN[prompt_core]='Core: 1) xray  2) sing-box'
TB_MSG_EN[prompt_protocols]='Protocols: 1) VLESS+SS  2) VLESS only  3) SS only  4) Hysteria 2 only  5) all three (or comma list)'
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
TB_MSG_EN[err_no_free_port]='Could not find a free port. Pass one with --ss-port.'
TB_MSG_EN[err_port_same]='VLESS and Shadowsocks cannot both listen on TCP port %s.'
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
TB_MSG_EN[label_link]='Share link:'
TB_MSG_EN[note_ss_landing]='Note: Shadowsocks has no TLS camouflage. Use it as a landing node behind a relay, not for connections that cross a censoring firewall directly.'
TB_MSG_EN[note_client_configs]='Client configurations: "show --format xray", "show --format sing-box" or "show --format hysteria2". Links only: "show --format links". QR codes: "show --qr".'
TB_MSG_EN[note_hy2_hop_clients]='Port-hopping clients: Hysteria app/v2.14.0+, Xray 26.11.9+ (udphop), or sing-box 1.11.0+.'
TB_MSG_EN[note_hy2_hop_random_clients]='Random port-hopping clients: Hysteria app/v2.14.0+, Xray 26.11.9+ (udphop), or sing-box 1.14.0+ (hop_interval_max).'
TB_MSG_EN[note_hop_no_firewall]='Note: --no-firewall skips ufw only; UDP port-hopping PREROUTING NAT will still be configured.'
TB_MSG_EN[note_hy2_acme_firewall]='ACME HTTP-01 requires TCP 80 open in both firewall and cloud security group for renewals; certificate refreshes briefly restart %s.'
TB_MSG_EN[note_firewall]='If the provider has its own firewall / security group, open the ports above there as well.'
TB_MSG_EN[note_security_group_udp]='Cloud security group UDP ports required: %s'

TB_MSG_EN[menu_items]='  1) Install or reconfigure a node
  2) Show connection details
  3) Update the core
  4) Rotate credentials
  5) Uninstall
  0) Exit'
TB_MSG_EN[prompt_menu]='Choose'

TB_MSG_EN[usage]='ToastBox %s - VLESS-TCP-REALITY-Vision, Shadowsocks 2022 and Hysteria 2 nodes on Xray or sing-box

Usage: toastbox.sh [command] [options]

Run without a command for the interactive menu.

Commands:
  install      Deploy a node, or change the settings of an existing one
  show         Print connection details, share links or client configs
  update       Upgrade the core and restart the node
  rotate       Generate new UUID / keys / passwords
  refresh-cert Refresh imported Hysteria 2 certificate & key from saved paths
  uninstall    Remove the core and the node
  help, version

Options for install:
  --core xray|sing-box        Core to use (default: xray)
  --protocols LIST            vless, ss, hy2, both (vless,ss), all (all three),
                              or comma-separated combination (default: vless,ss)
  --server-addr ADDR          Address clients connect to (default: detected)
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
  --format FORMAT             text (default), links, json, xray, sing-box, hysteria2
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
TB_MSG_ZH[err_protocols]='协议列表“%s”无效，可选 vless、ss、hy2、both、all 或逗号分隔组合。'
TB_MSG_ZH[err_protocol_disabled]='此节点未启用协议“%s”。'
TB_MSG_ZH[err_format]='未知格式“%s”，可选 text、links、json、xray、sing-box 或 hysteria2。'
TB_MSG_ZH[err_format_requires_hy2]='格式“hysteria2”要求节点启用并选择了 Hysteria 2 协议。'
TB_MSG_ZH[err_aborted]='已取消，未做任何更改。（使用 --yes 可跳过确认。）'
TB_MSG_ZH[err_sockopt_core]='自定义 TCP sockopt 仅支持 Xray，不支持 %s。切换内核前请用 install --reset-sockopt 清除。'
TB_MSG_ZH[err_sockopt_command]='TCP sockopt 选项仅可用于 install；update 和 rotate 会复用已保存的设置。'
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
TB_MSG_ZH[err_hy2_acme_port80_conflict]='Certbot standalone HTTP-01 需要占用 TCP 80 端口，与已配置的 VLESS 或 Shadowsocks TCP 80 端口冲突。'
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
TB_MSG_ZH[err_refresh_requires_hy2]='此节点未启用 Hysteria 2。'
TB_MSG_ZH[err_refresh_requires_files]='refresh-cert 仅适用于 Hysteria 2 的 files 证书模式。'
TB_MSG_ZH[info_hy2_cert_unchanged]='Hysteria 2 证书链与私钥内容未变化，无需重启。'
TB_MSG_ZH[ok_hy2_cert_refreshed]='Hysteria 2 证书已刷新。'
TB_MSG_ZH[err_lock_open]='无法打开操作锁 %s。'
TB_MSG_ZH[err_lock_busy]='另一项 ToastBox 操作正在持有锁 %s。'

TB_MSG_ZH[prompt_core]='内核：1) xray  2) sing-box'
TB_MSG_ZH[prompt_protocols]='协议：1) VLESS+SS  2) 仅 VLESS  3) 仅 SS  4) 仅 Hysteria 2  5) 三者全部（或逗号分隔）'
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
TB_MSG_ZH[err_no_free_port]='找不到空闲端口，请用 --ss-port 指定。'
TB_MSG_ZH[err_port_same]='VLESS 和 Shadowsocks 不能同时监听 TCP 端口 %s。'
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
TB_MSG_ZH[label_link]='分享链接：'
TB_MSG_ZH[note_ss_landing]='注意：Shadowsocks 没有 TLS 伪装，适合作为中转之后的落地节点，不适合直接穿越审查防火墙。'
TB_MSG_ZH[note_client_configs]='客户端配置：show --format xray、show --format sing-box 或 show --format hysteria2；仅链接：show --format links；二维码：show --qr。'
TB_MSG_ZH[note_hy2_hop_clients]='端口跳跃客户端要求：Hysteria app/v2.14.0+、Xray 26.11.9+（udphop）或 sing-box 1.11.0+。'
TB_MSG_ZH[note_hy2_hop_random_clients]='随机间隔跳跃客户端要求：Hysteria app/v2.14.0+、Xray 26.11.9+（udphop）或 sing-box 1.14.0+（hop_interval_max）。'
TB_MSG_ZH[note_hop_no_firewall]='注意：--no-firewall 仅跳过 ufw；若开启端口跳跃，仍会配置必需的 PREROUTING NAT 转发规则。'
TB_MSG_ZH[note_hy2_acme_firewall]='ACME HTTP-01 自动续期需要防火墙与云安全组均保持放行 TCP 80；证书刷新时会重启 %s（连接短暂中断）。'
TB_MSG_ZH[note_firewall]='如果服务商另有防火墙 / 安全组，请在那里同样放行上述端口。'
TB_MSG_ZH[note_security_group_udp]='云厂商安全组需放行的 UDP 端口：%s'

TB_MSG_ZH[menu_items]='  1) 安装或重新配置节点
  2) 查看连接信息
  3) 更新内核
  4) 重新生成凭据
  5) 卸载
  0) 退出'
TB_MSG_ZH[prompt_menu]='请选择'

TB_MSG_ZH[usage]='ToastBox %s - 基于 Xray 或 sing-box 部署 VLESS-TCP-REALITY-Vision、Shadowsocks 2022 与 Hysteria 2 节点

用法：toastbox.sh [命令] [选项]

不带命令运行将进入交互菜单。

命令：
  install      部署节点，或修改现有节点的设置
  show         显示连接信息、分享链接或客户端配置
  update       升级内核并重启节点
  rotate       重新生成 UUID / 密钥 / 密码
  refresh-cert 从已登记来源刷新 Hysteria 2 证书与私钥
  uninstall    移除内核和节点
  help, version

install 的选项：
  --core xray|sing-box        使用的内核（默认：xray）
  --protocols LIST            vless、ss、hy2、both（vless,ss）、all（三者全部），
                              或逗号分隔组合（默认：vless,ss）
  --server-addr ADDR          客户端连接所用的地址（默认：自动检测）
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
  --format FORMAT             text（默认）、links、json、xray、sing-box、hysteria2
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

# ===== src/lib/20-system.sh =====
#
# Host checks, dependency installation and user prompts.

TB_OS_ID=""
TB_OS_VERSION=""
TB_INTERACTIVE=0

TB_LOCK_HELD=0

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die err_root
}

tb_acquire_lock() {
  local dir
  [[ "$TB_LOCK_HELD" == "1" ]] && return 0
  dir="$(dirname "$TB_LOCK_FILE")"
  if [[ ! -d "$dir" ]]; then
    install -d -m 700 "$dir" || die err_lock_open "$TB_LOCK_FILE"
  fi
  exec 9>"$TB_LOCK_FILE" || die err_lock_open "$TB_LOCK_FILE"
  if has_cmd flock; then
    flock -w "${TOASTBOX_LOCK_TIMEOUT:-60}" 9 || {
      exec 9>&- 2>/dev/null || true
      die err_lock_busy "$TB_LOCK_FILE"
    }
  fi
  TB_LOCK_HELD=1
}

tb_release_lock() {
  if [[ "$TB_LOCK_HELD" == "1" ]]; then
    exec 9>&- 2>/dev/null || true
    TB_LOCK_HELD=0
  fi
}

# Reads ID / VERSION_ID / ID_LIKE without polluting our own namespace.
tb_os_release_field() {
  local field="$1" file="${TOASTBOX_OS_RELEASE:-/etc/os-release}"
  [[ -r "$file" ]] || return 0
  (
    # shellcheck source=/dev/null
    . "$file"
    eval "printf '%s' \"\${$field:-}\""
  )
}

detect_os() {
  TB_OS_ID="$(tb_os_release_field ID)"
  TB_OS_VERSION="$(tb_os_release_field VERSION_ID)"
  local like
  like="$(tb_os_release_field ID_LIKE)"

  if [[ "${TOASTBOX_SKIP_OS_CHECK:-0}" == "1" ]]; then
    return 0
  fi

  case "$TB_OS_ID" in
    debian)
      # Debian testing/unstable have no VERSION_ID; let them through.
      if [[ -n "$TB_OS_VERSION" ]] && ! ver_ge "$TB_OS_VERSION" "11"; then
        die err_os_version "Debian" "$TB_OS_VERSION" "11"
      fi
      ;;
    ubuntu)
      if [[ -n "$TB_OS_VERSION" ]] && ! ver_ge "$TB_OS_VERSION" "20.04"; then
        die err_os_version "Ubuntu" "$TB_OS_VERSION" "20.04"
      fi
      ;;
    *)
      if [[ " $like " == *" debian "* || " $like " == *" ubuntu "* ]]; then
        log_warn warn_os_derivative "${TB_OS_ID:-unknown}"
      else
        die err_os_unsupported "${TB_OS_ID:-unknown}"
      fi
      ;;
  esac
}

# Both cores publish Debian/Ubuntu builds for more architectures, but only
# these two are exercised.
require_supported_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64 | amd64 | aarch64 | arm64) ;;
    *) die err_arch_unsupported "$machine" ;;
  esac
}

require_systemd() {
  if [[ ! -d /run/systemd/system ]] || ! has_cmd systemctl; then
    die err_no_systemd
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" >&2
}

# Installs whatever is missing from the small set of tools the script uses.
install_deps() {
  local -a missing=()
  has_cmd curl || missing+=(curl)
  has_cmd jq || missing+=(jq)
  has_cmd openssl || missing+=(openssl)
  has_cmd ss || missing+=(iproute2)
  [[ -e /etc/ssl/certs/ca-certificates.crt ]] || missing+=(ca-certificates)

  if ((${#missing[@]} == 0)); then
    return 0
  fi
  log_info info_install_deps "${missing[*]}"
  apt-get update >&2 || die err_apt_update
  apt_install "${missing[@]}" || die err_apt_install "${missing[*]}"
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

# A terminal is usable either on stdin or, for `curl ... | bash`, through
# /dev/tty.
tb_tty_ok() {
  [[ -t 0 ]] && return 0
  (: </dev/tty) 2>/dev/null
}

tb_detect_interactive() {
  if [[ "${OPT_YES:-0}" == "1" ]] || ! tb_tty_ok; then
    TB_INTERACTIVE=0
  else
    TB_INTERACTIVE=1
  fi
}

# tb_readline PROMPT: prints the reply on stdout. The prompt itself is
# written to stderr by `read -p`, so command substitution is safe.
tb_readline() {
  local reply=""
  if [[ -t 0 ]]; then
    read -r -p "$1" reply || true
  else
    read -r -p "$1" reply </dev/tty || true
  fi
  printf '%s' "$reply"
}

# ask DEFAULT MSG_KEY [ARGS...]: returns DEFAULT when not interactive or when
# the user just presses Enter.
ask() {
  local default="$1" reply
  shift
  if [[ "$TB_INTERACTIVE" != "1" ]]; then
    printf '%s' "$default"
    return 0
  fi
  if [[ -n "$default" ]]; then
    reply="$(tb_readline "$(msg "$@") [$default]: ")"
  else
    reply="$(tb_readline "$(msg "$@"): ")"
  fi
  # Trim surrounding whitespace.
  reply="${reply#"${reply%%[![:space:]]*}"}"
  reply="${reply%"${reply##*[![:space:]]}"}"
  printf '%s' "${reply:-$default}"
}

# confirm DEFAULT(y|n) MSG_KEY [ARGS...]
# --yes answers yes to everything. Without a terminal and without --yes the
# default applies, so destructive prompts must default to "n".
confirm() {
  local default="$1" reply hint
  shift
  if [[ "${OPT_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "$TB_INTERACTIVE" != "1" ]]; then
    [[ "$default" == "y" ]]
    return
  fi
  if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
  reply="$(tb_readline "$(msg "$@") [$hint]: ")"
  reply="${reply:-$default}"
  [[ "$reply" == [yY]* ]]
}

# ---------------------------------------------------------------------------
# systemd
# ---------------------------------------------------------------------------

systemd_running() { [[ -d /run/systemd/system ]] && has_cmd systemctl; }

service_is_active() { systemctl -q is-active "$1" 2>/dev/null; }

service_unit_exists() {
  systemd_running && systemctl cat "$1" >/dev/null 2>&1
}

service_unit_prop() {
  systemctl show -p "$2" --value "$1" 2>/dev/null || true
}

# Restarts SERVICE and waits until it has stayed up for a moment: a core
# that rejects its configuration exits right after start.
service_restart_checked() {
  local svc="$1"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable "$svc" >/dev/null 2>&1 || true
  systemctl restart "$svc" >/dev/null 2>&1 || return 1
  for _ in 1 2 3; do
    sleep 1
    service_is_active "$svc" || return 1
  done
  return 0
}

service_stop_disable() {
  local svc="$1"
  systemctl stop "$svc" >/dev/null 2>&1 || true
  systemctl disable "$svc" >/dev/null 2>&1 || true
}

service_show_log() {
  journalctl -u "$1" -n 20 --no-pager >&2 2>/dev/null || true
}

# ===== src/lib/30-net.sh =====
#
# Address and port validation, port availability, public address
# detection, REALITY target probing, firewall and clock checks.

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

valid_domain() {
  ((${#1} <= 253)) &&
    [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

valid_ipv4() {
  local ip="$1" octet
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  local IFS=.
  for octet in $ip; do
    ((10#$octet <= 255)) || return 1
  done
}

# Deliberately loose: the cores do the authoritative parsing.
valid_ipv6() {
  [[ "$1" == *:*:* && "$1" =~ ^[0-9A-Fa-f:.]+$ ]]
}

valid_host() {
  valid_ipv4 "$1" || valid_ipv6 "$1" || valid_domain "$1"
}

valid_http_url() {
  local url="$1" rest authority
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || return 1
  rest="${url#*://}"
  authority="${rest%%[/?#]*}"
  [[ "$authority" == "localhost" ]] && return 0
  if [[ "$authority" == localhost:* ]]; then
    valid_port "${authority#localhost:}"
    return
  fi
  valid_host "$authority" || valid_host_port "$authority"
}

# "host:port" with a domain, an IPv4 address or a bracketed IPv6 address.
valid_host_port() {
  local value="$1" host port
  [[ "$value" == *:* ]] || return 1
  port="${value##*:}"
  host="${value%:*}"
  valid_port "$port" || return 1
  if [[ "$host" == \[*\] ]]; then
    host="${host#[}"
    valid_ipv6 "${host%]}"
  else
    valid_ipv4 "$host" || valid_domain "$host"
  fi
}

# host_of "host:port" / port_of "host:port": brackets of IPv6 literals are
# removed from the host part.
host_of() {
  local host="${1%:*}"
  host="${host#[}"
  printf '%s' "${host%]}"
}
port_of() { printf '%s' "${1##*:}"; }

# Formats a host for use inside a URI or "host:port" pair.
uri_host() {
  if valid_ipv6 "$1"; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

is_private_ipv4() {
  case "$1" in
    10.* | 127.* | 169.254.* | 192.168.*) return 0 ;;
    172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
    100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------

# port_owners PROTO PORT: prints one line per listening process name; prints
# "?" when something listens but the owner cannot be determined.
port_owners() {
  local proto="$1" port="$2" flags="-ltnp" lines names
  [[ "$proto" == "udp" ]] && flags="-lunp"
  lines="$(ss -H "$flags" "sport = :$port" 2>/dev/null || true)"
  [[ -n "$lines" ]] || return 0
  names="$(printf '%s\n' "$lines" | grep -o 'users:(("[^"]*"' | sed 's/^users:(("//; s/"$//' | sort -u || true)"
  printf '%s\n' "${names:-?}"
}

# port_conflict PROTO PORT OWN_PROCESS...: succeeds (and prints the offending
# process names) when the port is taken by anything other than the listed
# processes.
port_conflict() {
  local proto="$1" port="$2" owner
  local -a others=()
  shift 2
  while IFS= read -r owner; do
    [[ -n "$owner" ]] || continue
    in_list "$owner" "$@" || others+=("$owner")
  done < <(port_owners "$proto" "$port")
  ((${#others[@]} > 0)) || return 1
  printf '%s' "${others[*]}"
}

# Prints "PORT OWNER" lines for every bound UDP socket on the host using a
# single `ss` invocation so wide port ranges can be checked quickly.
udp_listening_ports() {
  ss -H -lunp 2>/dev/null | awk '
    {
      col = ($1 ~ /^(udp|tcp|raw|icmp)/) ? 5 : 4
      local_addr = $col
      if (local_addr !~ /:/) next
      sub(/.*:/, "", local_addr)
      if (local_addr !~ /^[0-9]+$/) next
      rest = $0
      found = 0
      while (match(rest, /\("[^"]+"/)) {
        owner = substr(rest, RSTART + 2, RLENGTH - 3)
        print local_addr, owner
        found = 1
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (!found) print local_addr, "?"
    }
  '
}

random_free_port() {
  local port
  for _ in $(seq 1 100); do
    port=$((20000 + (RANDOM * 32768 + RANDOM) % 40000))
    if [[ -z "$(port_owners tcp "$port")" && -z "$(port_owners udp "$port")" ]]; then
      printf '%s' "$port"
      return 0
    fi
  done
  return 1
}

ipv6_enabled() {
  [[ -e /proc/net/if_inet6 ]] &&
    [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" == "0" ]]
}

# ---------------------------------------------------------------------------
# Public address
# ---------------------------------------------------------------------------

local_route_ipv4() {
  ip -4 route get 1.1.1.1 2>/dev/null |
    awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}'
}

# Asks an external service which address the outside world sees. Only used
# when the local route address is private (NAT) or missing.
public_ip_lookup() {
  local family="$1" ip=""
  ip="$(curl "-$family" -fsS --max-time 6 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null |
    awk -F= '$1 == "ip" {print $2}' || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl "-$family" -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s' "$ip"
}

detect_server_addr() {
  local ip
  ip="$(local_route_ipv4 || true)"
  if [[ -n "$ip" ]] && valid_ipv4 "$ip" && ! is_private_ipv4 "$ip"; then
    printf '%s' "$ip"
    return 0
  fi
  ip="$(public_ip_lookup 4)"
  if valid_ipv4 "$ip"; then
    printf '%s' "$ip"
    return 0
  fi
  ip="$(public_ip_lookup 6)"
  if valid_ipv6 "$ip"; then
    printf '%s' "$ip"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# REALITY target probe
# ---------------------------------------------------------------------------

TB_TARGET_H2=0

# probe_reality_target SNI HOST:PORT
#   0  TLS 1.3 handshake succeeded and the certificate is valid for SNI
#   1  could not connect
#   2  connected, but no TLS 1.3
#   3  TLS 1.3 works, but the certificate does not verify for SNI
# TB_TARGET_H2 is set to 1 when the target negotiated HTTP/2.
probe_reality_target() {
  local sni="$1" target="$2" out
  TB_TARGET_H2=0
  out="$(timeout 15 openssl s_client -connect "$target" -servername "$sni" \
    -tls1_3 -alpn h2,http/1.1 -verify_hostname "$sni" </dev/null 2>&1 || true)"
  [[ "$out" == *"CONNECTED("* ]] || return 1
  [[ "$out" == *"TLSv1.3"* ]] || return 2
  [[ "$out" == *"ALPN protocol: h2"* ]] && TB_TARGET_H2=1
  [[ "$out" == *"Verify return code: 0 (ok)"* ]] || return 3
  return 0
}

# ---------------------------------------------------------------------------
# Clock
# ---------------------------------------------------------------------------

clock_synchronized() {
  [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]
}

# ---------------------------------------------------------------------------
# Firewall (ufw)
# ---------------------------------------------------------------------------

fw_backend() {
  local status
  has_cmd ufw || return 0
  # Captured rather than piped into `grep -q`: with pipefail, grep leaving
  # early would make a long rule listing look like a failure.
  status="$(LC_ALL=C ufw status 2>/dev/null || true)"
  if [[ "$status" == "Status: active"* ]]; then
    printf 'ufw'
  fi
}

# fw_open RULE ("443/tcp"): succeeds only when a new rule was really added,
# so that a rule the administrator created is never recorded as ours.
fw_open() {
  local out
  out="$(LC_ALL=C ufw allow "$1" comment 'ToastBox' 2>&1 || true)"
  [[ "$out" == *"Rule added"* || "$out" == *"Rules updated"* ]]
}

fw_close() {
  LC_ALL=C ufw delete allow "$1" >/dev/null 2>&1 || true
}

# fw_sync RULE...: opens the wanted rules and closes rules that an earlier
# run added but that are no longer needed. Tracks ownership in CFG_FW_RULES.
fw_sync() {
  local -a wanted=("$@") kept=()
  local rule backend
  backend="$(fw_backend)"
  if [[ -z "$backend" ]]; then
    return 0
  fi
  for rule in "${CFG_FW_RULES[@]}"; do
    if ! in_list "$rule" "${wanted[@]}"; then
      fw_close "$rule"
      log_info info_fw_closed "$rule"
    fi
  done
  for rule in "${wanted[@]}"; do
    if in_list "$rule" "${CFG_FW_RULES[@]}"; then
      kept+=("$rule")
    elif fw_open "$rule"; then
      kept+=("$rule")
      log_ok info_fw_opened "$rule"
    fi
  done
  CFG_FW_RULES=("${kept[@]}")
}

fw_close_all() {
  local rule
  [[ -n "$(fw_backend)" ]] || return 0
  for rule in "${CFG_FW_RULES[@]}"; do
    fw_close "$rule"
    log_info info_fw_closed "$rule"
  done
  CFG_FW_RULES=()
}

# ===== src/lib/35-hy2-hop.sh =====
#
# Hysteria 2 UDP port hopping: port set and interval normalization,
# conflict checks, nftables/iptables PREROUTING NAT management and systemd
# persistence. Server core configs remain single-port listeners.

HY2_HOP_V4=0
HY2_HOP_V6=0
HY2_HOP_BACKEND=""
PARSED_HOP_MIN=30
PARSED_HOP_MAX=30

# norm_hy2_hop_ports VALUE: accepts "none"/"off" or comma-separated ports and
# start-end ranges (1..65535), sorts and merges overlapping/adjacent intervals,
# and requires at least two distinct ports when enabling hopping.
norm_hy2_hop_ports() {
  local raw="$1" token s e cur_s="" cur_e="" count=0
  local -a items=() ranges=() merged_ports=()

  case "$raw" in
    none | off)
      printf 'none'
      return 0
      ;;
    "" | ,* | *, | *,,*) return 1 ;;
  esac
  [[ "$raw" != *[[:space:]]* ]] || return 1

  IFS=',' read -r -a items <<<"$raw"
  ((${#items[@]} > 0)) || return 1

  for token in "${items[@]}"; do
    if [[ "$token" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
      s="${BASH_REMATCH[1]}"
      e="${BASH_REMATCH[2]}"
      valid_port "$s" && valid_port "$e" || return 1
      s=$((10#$s))
      e=$((10#$e))
      ((s <= e)) || return 1
    elif valid_port "$token"; then
      s=$((10#$token))
      e="$s"
    else
      return 1
    fi
    ranges+=("$(printf '%05d %05d' "$s" "$e")")
  done

  while IFS=' ' read -r s e; do
    s=$((10#$s))
    e=$((10#$e))
    if [[ -z "$cur_s" ]]; then
      cur_s="$s"
      cur_e="$e"
    elif ((s <= cur_e + 1)); then
      ((e > cur_e)) && cur_e="$e"
    else
      count=$((count + cur_e - cur_s + 1))
      if ((cur_s == cur_e)); then
        merged_ports+=("$cur_s")
      else
        merged_ports+=("$cur_s-$cur_e")
      fi
      cur_s="$s"
      cur_e="$e"
    fi
  done < <(printf '%s\n' "${ranges[@]}" | sort -n -k1,1 -k2,2)

  count=$((count + cur_e - cur_s + 1))
  ((count >= 2)) || return 1
  if ((cur_s == cur_e)); then
    merged_ports+=("$cur_s")
  else
    merged_ports+=("$cur_s-$cur_e")
  fi
  join_by , "${merged_ports[@]}"
}

# norm_hy2_hop_interval VALUE: accepts integer seconds N or MIN-MAX with
# 5 <= MIN <= MAX <= 2147483647 (matching Xray's Int32Range bound).
norm_hy2_hop_interval() {
  local raw="$1" lo hi
  if [[ "$raw" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    lo="$(norm_socket_int "${BASH_REMATCH[1]}" 2147483647)" || return 1
    hi="$(norm_socket_int "${BASH_REMATCH[2]}" 2147483647)" || return 1
    ((lo >= 5 && hi >= 5 && lo <= hi)) || return 1
    if ((lo == hi)); then
      printf '%d' "$lo"
    else
      printf '%d-%d' "$lo" "$hi"
    fi
  else
    lo="$(norm_socket_int "$raw" 2147483647)" || return 1
    ((lo >= 5)) || return 1
    printf '%d' "$lo"
  fi
}

hy2_hop_parse_interval() {
  local canon
  canon="$(norm_hy2_hop_interval "$1")" || return 1
  if [[ "$canon" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    PARSED_HOP_MIN="${BASH_REMATCH[1]}"
    PARSED_HOP_MAX="${BASH_REMATCH[2]}"
  else
    PARSED_HOP_MIN="$canon"
    PARSED_HOP_MAX="$canon"
  fi
}

# hy2_hop_contains_port PORTS PORT
hy2_hop_contains_port() {
  local ports="$1" target="$((10#$2))" item s e
  local -a items=()
  [[ -n "$ports" ]] || return 1
  IFS=',' read -r -a items <<<"$ports"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      s=$((10#${item%-*}))
      e=$((10#${item#*-}))
      ((target >= s && target <= e)) && return 0
    else
      ((target == 10#$item)) && return 0
    fi
  done
  return 1
}

# hy2_hop_redirect_ranges PORTS LISTEN_PORT: prints one NAT rule port token
# ("START-END" or "PORT") per line, omitting LISTEN_PORT itself if included.
hy2_hop_redirect_ranges() {
  local ports="$1" listen_port="${2:-}" item s e
  local -a items=()
  [[ -n "$ports" ]] || return 0
  IFS=',' read -r -a items <<<"$ports"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      s=$((10#${item%-*}))
      e=$((10#${item#*-}))
    else
      s=$((10#$item))
      e="$s"
    fi
    if [[ -n "$listen_port" ]] && ((listen_port >= s && listen_port <= e)); then
      if ((s < listen_port)); then
        if ((s == listen_port - 1)); then
          printf '%d\n' "$s"
        else
          printf '%d-%d\n' "$s" "$((listen_port - 1))"
        fi
      fi
      if ((listen_port < e)); then
        if ((listen_port + 1 == e)); then
          printf '%d\n' "$e"
        else
          printf '%d-%d\n' "$((listen_port + 1))" "$e"
        fi
      fi
    else
      if ((s == e)); then
        printf '%d\n' "$s"
      else
        printf '%d-%d\n' "$s" "$e"
      fi
    fi
  done
}

# hy2_hop_port_conflicts PORTS OWN_PROCS...: prints "PORT/udp (OWNER)" lines or
# returns 1 when no foreign UDP listener overlaps the hop port set.
hy2_hop_port_conflicts() {
  local ports="$1" port owner
  local -a conflicts=()
  shift
  [[ -n "$ports" ]] || return 1
  while read -r port owner; do
    [[ -n "$port" ]] || continue
    if hy2_hop_contains_port "$ports" "$port"; then
      if [[ "$owner" == "?" ]] || ! in_list "$owner" "$@"; then
        in_list "$port/udp ($owner)" "${conflicts[@]}" || conflicts+=("$port/udp ($owner)")
      fi
    fi
  done < <(udp_listening_ports)
  ((${#conflicts[@]} > 0)) || return 1
  printf '%s' "${conflicts[*]}"
}

hy2_hop_detect_backend() {
  local forced="${TOASTBOX_HY2_HOP_BACKEND:-}"
  if [[ -n "$forced" ]]; then
    case "$forced" in
      nftables | nft)
        printf 'nftables'
        return 0
        ;;
      iptables | ipt)
        printf 'iptables'
        return 0
        ;;
      *) return 1 ;;
    esac
  fi
  if has_cmd nft; then
    printf 'nftables'
  elif has_cmd iptables; then
    printf 'iptables'
  else
    return 1
  fi
}

hy2_hop_families() {
  local listen="$1"
  HY2_HOP_V4=0
  HY2_HOP_V6=0
  if [[ -z "$listen" || "$listen" == "::" ]]; then
    HY2_HOP_V4=1
    if ipv6_enabled; then
      HY2_HOP_V6=1
    fi
  elif valid_ipv4 "$listen"; then
    HY2_HOP_V4=1
  elif valid_ipv6 "$listen"; then
    HY2_HOP_V6=1
  fi
  return 0
}

hy2_hop_is_loopback() {
  local addr="${1#[}"
  addr="${addr%]}"
  [[ "$addr" == 127.* || "$addr" == "::1" ]]
}

hy2_hop_validate_saved() {
  local ports="$1" min="$2" max="$3"
  [[ -n "$ports" ]] || return 0
  [[ "$ports" == "$(norm_hy2_hop_ports "$ports" 2>/dev/null || true)" ]] || return 1
  min="$(norm_socket_int "$min" 2147483647 2>/dev/null)" || return 1
  max="$(norm_socket_int "$max" 2147483647 2>/dev/null)" || return 1
  ((min >= 5 && min <= max))
}

hy2_hop_check_tools() {
  case "$1" in
    nftables)
      has_cmd nft || die err_hy2_hop_no_cmd nft
      ;;
    iptables)
      if [[ "$HY2_HOP_V4" == "1" ]]; then
        has_cmd iptables || die err_hy2_hop_no_cmd iptables
      fi
      if [[ "$HY2_HOP_V6" == "1" ]]; then
        has_cmd ip6tables || die err_hy2_hop_no_cmd ip6tables
      fi
      ;;
  esac
}

hy2_hop_preflight() {
  [[ "$CFG_HY2" == "1" && -n "$CFG_HY2_HOP_PORTS" ]] || return 0
  hy2_hop_is_loopback "$CFG_LISTEN" && die err_hy2_hop_loopback "$CFG_LISTEN"
  hy2_hop_families "$CFG_LISTEN"
  HY2_HOP_BACKEND="$(hy2_hop_detect_backend)" || die err_hy2_hop_no_backend
  hy2_hop_check_tools "$HY2_HOP_BACKEND"
}

hy2_hop_render_json() {
  local -a redirects=()
  local r
  hy2_hop_families "$CFG_LISTEN"
  HY2_HOP_BACKEND="${HY2_HOP_BACKEND:-$(hy2_hop_detect_backend)}"
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(hy2_hop_redirect_ranges "$CFG_HY2_HOP_PORTS" "$CFG_HY2_PORT")

  jq -n \
    --arg backend "$HY2_HOP_BACKEND" \
    --arg listen "$CFG_LISTEN" \
    --arg port "$CFG_HY2_PORT" \
    --arg ports "$CFG_HY2_HOP_PORTS" \
    --arg ipv4 "$HY2_HOP_V4" \
    --arg ipv6 "$HY2_HOP_V6" \
    --args '
    {
      schema: 1,
      backend: $backend,
      listen: $listen,
      port: ($port | tonumber),
      ports: $ports,
      redirects: $ARGS.positional,
      ipv4: ($ipv4 == "1"),
      ipv6: ($ipv6 == "1")
    }' "${redirects[@]}"
}

# ---------------------------------------------------------------------------
# Self-contained NAT apply/remove functions embedded into TB_HY2_HOP_HELPER.
# They rely solely on arguments, jq, and nft/iptables/ip6tables so systemd can
# invoke the helper cleanly after boot without needing the ToastBox source tree.
# ---------------------------------------------------------------------------

_hy2_hop_remove_nft() {
  command -v nft >/dev/null 2>&1 || return 0
  if nft list table ip toastbox_hy2 >/dev/null 2>&1; then
    nft delete table ip toastbox_hy2 || return 1
  fi
  if nft list table ip6 toastbox_hy2 >/dev/null 2>&1; then
    nft delete table ip6 toastbox_hy2 || return 1
  fi
}

_hy2_hop_remove_ipt_bin() {
  local bin="$1" num
  command -v "$bin" >/dev/null 2>&1 || return 0
  while IFS= read -r num; do
    [[ -n "$num" ]] || continue
    "$bin" -w -t nat -D PREROUTING "$num" || return 1
  done < <("$bin" -w -t nat -L PREROUTING -n --line-numbers 2>/dev/null |
    awk '$2 == "TOASTBOX-HY2" {print $1}' | sort -rn)
  if "$bin" -w -t nat -L TOASTBOX-HY2 -n >/dev/null 2>&1; then
    "$bin" -w -t nat -F TOASTBOX-HY2 || return 1
    "$bin" -w -t nat -X TOASTBOX-HY2 || return 1
  fi
}

_hy2_hop_remove_ipt() {
  local rc=0
  _hy2_hop_remove_ipt_bin iptables || rc=1
  _hy2_hop_remove_ipt_bin ip6tables || rc=1
  return "$rc"
}

_hy2_hop_remove_all() {
  local rc=0
  _hy2_hop_remove_nft || rc=1
  _hy2_hop_remove_ipt || rc=1
  return "$rc"
}

_hy2_hop_apply_nft() {
  local json_file="$1" listen port ipv4 ipv6 r script=""
  local -a redirects=()
  listen="$(jq -r '.listen // ""' "$json_file")" || return 1
  port="$(jq -r '.port' "$json_file")" || return 1
  ipv4="$(jq -r 'if .ipv4 then "1" else "0" end' "$json_file")" || return 1
  ipv6="$(jq -r 'if .ipv6 then "1" else "0" end' "$json_file")" || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(jq -r '.redirects[]' "$json_file") || return 1
  ((${#redirects[@]} > 0)) || return 1

  command -v nft >/dev/null 2>&1 || {
    echo "nft command not found" >&2
    return 1
  }

  if nft list table ip toastbox_hy2 >/dev/null 2>&1; then
    script+="delete table ip toastbox_hy2"$'\n'
  fi
  if nft list table ip6 toastbox_hy2 >/dev/null 2>&1; then
    script+="delete table ip6 toastbox_hy2"$'\n'
  fi

  if [[ "$ipv4" == "1" ]]; then
    script+="add table ip toastbox_hy2"$'\n'
    script+="add chain ip toastbox_hy2 prerouting { type nat hook prerouting priority -100; policy accept; }"$'\n'
    for r in "${redirects[@]}"; do
      if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
        script+="add rule ip toastbox_hy2 prerouting fib daddr type local udp dport $r redirect to :$port"$'\n'
      else
        script+="add rule ip toastbox_hy2 prerouting ip daddr $listen udp dport $r dnat to $listen:$port"$'\n'
      fi
    done
  fi

  if [[ "$ipv6" == "1" ]]; then
    script+="add table ip6 toastbox_hy2"$'\n'
    script+="add chain ip6 toastbox_hy2 prerouting { type nat hook prerouting priority -100; policy accept; }"$'\n'
    for r in "${redirects[@]}"; do
      if [[ -z "$listen" || "$listen" == "::" ]]; then
        script+="add rule ip6 toastbox_hy2 prerouting fib daddr type local udp dport $r redirect to :$port"$'\n'
      else
        script+="add rule ip6 toastbox_hy2 prerouting ip6 daddr $listen udp dport $r dnat to [$listen]:$port"$'\n'
      fi
    done
  fi

  nft -f - <<<"$script" || return 1
  _hy2_hop_remove_ipt || true
}

_hy2_hop_apply_ipt_family() {
  local bin="$1" family="$2" listen="$3" port="$4" r ipt_r
  shift 4
  local -a redirects=("$@")
  command -v "$bin" >/dev/null 2>&1 || {
    echo "$bin command not found" >&2
    return 1
  }

  _hy2_hop_remove_ipt_bin "$bin" || return 1
  "$bin" -w -t nat -N TOASTBOX-HY2 || return 1
  if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j REDIRECT --to-ports "$port" || return 1
  elif [[ "$family" == "ip6" ]]; then
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j DNAT --to-destination "[$listen]:$port" || return 1
  else
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j DNAT --to-destination "$listen:$port" || return 1
  fi

  for r in "${redirects[@]}"; do
    ipt_r="${r//-/:}"
    if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
      "$bin" -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p udp --dport "$ipt_r" -j TOASTBOX-HY2 || return 1
    else
      "$bin" -w -t nat -A PREROUTING -d "$listen" -p udp --dport "$ipt_r" -j TOASTBOX-HY2 || return 1
    fi
  done
}

_hy2_hop_apply_ipt() {
  local json_file="$1" listen port ipv4 ipv6 r
  local -a redirects=()
  listen="$(jq -r '.listen // ""' "$json_file")" || return 1
  port="$(jq -r '.port' "$json_file")" || return 1
  ipv4="$(jq -r 'if .ipv4 then "1" else "0" end' "$json_file")" || return 1
  ipv6="$(jq -r 'if .ipv6 then "1" else "0" end' "$json_file")" || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(jq -r '.redirects[]' "$json_file") || return 1
  ((${#redirects[@]} > 0)) || return 1

  if [[ "$ipv4" == "1" ]]; then
    if ! _hy2_hop_apply_ipt_family iptables ip "$listen" "$port" "${redirects[@]}"; then
      _hy2_hop_remove_ipt || true
      return 1
    fi
  else
    _hy2_hop_remove_ipt_bin iptables || true
  fi

  if [[ "$ipv6" == "1" ]]; then
    if ! _hy2_hop_apply_ipt_family ip6tables ip6 "$listen" "$port" "${redirects[@]}"; then
      _hy2_hop_remove_ipt || true
      return 1
    fi
  else
    _hy2_hop_remove_ipt_bin ip6tables || true
  fi

  _hy2_hop_remove_nft || true
}

_hy2_hop_helper_main() {
  local action="${1:-}" json_file="${2:-/etc/toastbox/hy2-hop.json}" backend
  case "$action" in
    apply)
      [[ -f "$json_file" ]] || {
        echo "missing hop state file: $json_file" >&2
        return 1
      }
      backend="$(jq -r '.backend // ""' "$json_file")" || return 1
      case "$backend" in
        nftables) _hy2_hop_apply_nft "$json_file" ;;
        iptables) _hy2_hop_apply_ipt "$json_file" ;;
        *)
          echo "unsupported hop backend: $backend" >&2
          return 1
          ;;
      esac
      ;;
    remove)
      _hy2_hop_remove_all
      ;;
    *)
      echo "usage: toastbox-hy2-hop apply|remove [FILE]" >&2
      return 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Installer / systemd integration
# ---------------------------------------------------------------------------

hy2_hop_write_helper() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-hy2-hop.XXXXXX")" || return 1
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '# Managed by ToastBox (hy2-hop-helper)\n\n'
    declare -f \
      _hy2_hop_remove_nft \
      _hy2_hop_remove_ipt_bin \
      _hy2_hop_remove_ipt \
      _hy2_hop_remove_all \
      _hy2_hop_apply_nft \
      _hy2_hop_apply_ipt_family \
      _hy2_hop_apply_ipt \
      _hy2_hop_helper_main
    printf '\n_hy2_hop_helper_main "$@"\n'
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$dest"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

hy2_hop_render_service() {
  local core_svc="$1"
  cat <<EOF
# Managed by ToastBox (hy2-hop)
[Unit]
Description=ToastBox Hysteria 2 UDP port hopping NAT rules
After=network-pre.target network.target ufw.service nftables.service netfilter-persistent.service
Before=${core_svc}.service
PartOf=${core_svc}.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$TB_HY2_HOP_HELPER apply $TB_HY2_HOP_STATE
ExecStop=$TB_HY2_HOP_HELPER remove
EOF
}

hy2_hop_render_dropin() {
  cat <<EOF
# Managed by ToastBox (hy2-hop)
[Unit]
Requires=$TB_HY2_HOP_SERVICE
After=$TB_HY2_HOP_SERVICE
EOF
}

hy2_hop_dropin_path() {
  printf '%s/%s.service.d/toastbox-hy2-hop.conf' "$TB_SYSTEMD_DIR" "$1"
}

hy2_hop_unit_path() {
  printf '%s/%s' "$TB_SYSTEMD_DIR" "$TB_HY2_HOP_SERVICE"
}

hy2_hop_write_file() {
  local mode="$1" dest="$2" dir tmp
  dir="$(dirname "$dest")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.tb.XXXXXX")" || return 1
  if ! cat >"$tmp" ||
    ! install_owned "$mode" root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$dest"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

hy2_hop_apply_rules() {
  _hy2_hop_helper_main apply "$1"
}

hy2_hop_remove_rules() {
  _hy2_hop_helper_main remove
}

hy2_hop_backup() {
  local dir="$1" svc file
  install -d -m 700 "$dir" || return 1
  [[ -f "$TB_HY2_HOP_STATE" ]] && cp -p "$TB_HY2_HOP_STATE" "$dir/hy2-hop.json"
  [[ -f "$TB_HY2_HOP_HELPER" ]] && cp -p "$TB_HY2_HOP_HELPER" "$dir/helper"
  file="$(hy2_hop_unit_path)"
  [[ -f "$file" ]] && cp -p "$file" "$dir/service"
  for svc in xray sing-box; do
    file="$(hy2_hop_dropin_path "$svc")"
    [[ -f "$file" ]] && cp -p "$file" "$dir/dropin-$svc"
  done
  return 0
}

hy2_hop_remove_dropins() {
  local svc file
  for svc in xray sing-box; do
    file="$(hy2_hop_dropin_path "$svc")"
    rm -f "$file"
    rmdir "$(dirname "$file")" 2>/dev/null || true
  done
}

hy2_hop_remove_files() {
  rm -f "$(hy2_hop_unit_path)"
  hy2_hop_remove_dropins
  rm -f "$TB_HY2_HOP_HELPER" "$TB_HY2_HOP_STATE"
}

hy2_hop_systemd_reload() {
  systemd_running || return 0
  systemctl daemon-reload >/dev/null 2>&1 || true
}

hy2_hop_systemd_stop_unit() {
  systemd_running || return 0
  systemctl stop "$TB_HY2_HOP_SERVICE" >/dev/null 2>&1 || true
}

hy2_hop_install_state() {
  local core_svc="$1" json_src="$2" other_svc="sing-box" dropin old_dropin
  [[ "$core_svc" == "sing-box" ]] && other_svc="xray"

  install -d -m 700 "$TB_STATE_DIR" || return 1
  install_owned 600 root root "$json_src" "$TB_HY2_HOP_STATE" || return 1
  hy2_hop_write_helper "$TB_HY2_HOP_HELPER" || return 1
  hy2_hop_render_service "$core_svc" | hy2_hop_write_file 644 "$(hy2_hop_unit_path)" || return 1

  dropin="$(hy2_hop_dropin_path "$core_svc")"
  hy2_hop_render_dropin | hy2_hop_write_file 644 "$dropin" || return 1

  old_dropin="$(hy2_hop_dropin_path "$other_svc")"
  rm -f "$old_dropin"
  rmdir "$(dirname "$old_dropin")" 2>/dev/null || true

  hy2_hop_systemd_reload
}

hy2_hop_disable() {
  hy2_hop_remove_dropins
  hy2_hop_systemd_reload
  hy2_hop_systemd_stop_unit
  hy2_hop_remove_rules || true
  hy2_hop_remove_files
  hy2_hop_systemd_reload
}

hy2_hop_restore() {
  local dir="$1" svc file dropin active_svc=""
  hy2_hop_remove_dropins
  hy2_hop_systemd_reload
  hy2_hop_systemd_stop_unit
  hy2_hop_remove_rules || true
  hy2_hop_remove_files

  if [[ -f "$dir/hy2-hop.json" ]]; then
    install -d -m 700 "$TB_STATE_DIR" || true
    install_owned 600 root root "$dir/hy2-hop.json" "$TB_HY2_HOP_STATE" || true
  fi
  if [[ -f "$dir/helper" ]]; then
    install -d -m 755 "$(dirname "$TB_HY2_HOP_HELPER")" || true
    install_owned 755 root root "$dir/helper" "$TB_HY2_HOP_HELPER" || true
  fi
  if [[ -f "$dir/service" ]]; then
    file="$(hy2_hop_unit_path)"
    install -d -m 755 "$(dirname "$file")" || true
    install_owned 644 root root "$dir/service" "$file" || true
  fi
  for svc in xray sing-box; do
    if [[ -f "$dir/dropin-$svc" ]]; then
      active_svc="$svc"
      dropin="$(hy2_hop_dropin_path "$svc")"
      install -d -m 755 "$(dirname "$dropin")" || true
      install_owned 644 root root "$dir/dropin-$svc" "$dropin" || true
    fi
  done
  hy2_hop_systemd_reload
  if [[ -f "$TB_HY2_HOP_STATE" ]]; then
    hy2_hop_apply_rules "$TB_HY2_HOP_STATE" || true
    if [[ -n "$active_svc" ]] && systemd_running && service_is_active "$active_svc"; then
      systemctl start "$TB_HY2_HOP_SERVICE" >/dev/null 2>&1 || true
    fi
  fi
}

# ===== src/lib/40-state.sh =====
#
# The node description (CFG_*) and its persistence in state.json.
#
# state.json is the single source of truth for a deployed node: the server
# configuration, the share links and the client configurations are all
# rendered from it, which is what makes re-runs idempotent and lets
# `toastbox show` reprint everything later.

TB_STATE_SCHEMA=1
TB_HAS_STATE=0

cfg_reset() {
  CFG_CORE=""
  CFG_SERVER_ADDR=""
  CFG_NODE_NAME=""
  CFG_LISTEN=""
  CFG_BLOCK_BT=0
  CFG_ALLOW_PRIVATE=0
  # Optional Xray TCP listener settings. Empty means core/system defaults.
  CFG_SOCKOPT='{}'

  CFG_VLESS=0
  CFG_VLESS_PORT=""
  CFG_VLESS_UUID=""
  CFG_REALITY_SNI=""
  CFG_REALITY_TARGET=""
  CFG_REALITY_PRIVATE_KEY=""
  CFG_REALITY_PUBLIC_KEY=""
  CFG_REALITY_SHORT_ID=""

  CFG_SS=0
  CFG_SS_PORT=""
  CFG_SS_METHOD=""
  CFG_SS_PASSWORD=""
  CFG_SS_NETWORK=""

  CFG_HY2=0
  CFG_HY2_PORT=""
  CFG_HY2_PASSWORD=""
  CFG_HY2_TLS=""
  CFG_HY2_SNI=""
  CFG_HY2_CERT=""
  CFG_HY2_KEY=""
  CFG_HY2_CERT_SHA256=""
  CFG_HY2_OBFS=""
  CFG_HY2_OBFS_PASSWORD=""
  CFG_HY2_MASQUERADE=""
  CFG_HY2_CERT_FILE=""
  CFG_HY2_KEY_FILE=""
  CFG_HY2_CERTBOT_HOOK=0
  CFG_HY2_ACME=0
  CFG_HY2_ACME_DOMAIN=""
  CFG_HY2_ACME_EMAIL=""
  CFG_HY2_ACME_LINEAGE=""
  CFG_HY2_HOP_PORTS=""
  CFG_HY2_HOP_INTERVAL_MIN=30
  CFG_HY2_HOP_INTERVAL_MAX=30

  CFG_FW_RULES=()
}
cfg_reset

# Prints the state document for the current CFG_* values.
state_json() {
  jq -n \
    --argjson schema "$TB_STATE_SCHEMA" \
    --arg core "$CFG_CORE" \
    --arg server_addr "$CFG_SERVER_ADDR" \
    --arg node_name "$CFG_NODE_NAME" \
    --arg listen "$CFG_LISTEN" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --argjson sockopt "$CFG_SOCKOPT" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg vless_uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target "$CFG_REALITY_TARGET" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg public_key "$CFG_REALITY_PUBLIC_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$CFG_SS_NETWORK" \
    --arg hy2 "$CFG_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_tls "$CFG_HY2_TLS" \
    --arg hy2_sni "$CFG_HY2_SNI" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_key "$CFG_HY2_KEY" \
    --arg hy2_cert_sha256 "$CFG_HY2_CERT_SHA256" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_masquerade "$CFG_HY2_MASQUERADE" \
    --arg hy2_cert_file "$CFG_HY2_CERT_FILE" \
    --arg hy2_key_file "$CFG_HY2_KEY_FILE" \
    --arg hy2_certbot_hook "$CFG_HY2_CERTBOT_HOOK" \
    --arg hy2_acme "$CFG_HY2_ACME" \
    --arg hy2_acme_domain "$CFG_HY2_ACME_DOMAIN" \
    --arg hy2_acme_email "$CFG_HY2_ACME_EMAIL" \
    --arg hy2_acme_lineage "$CFG_HY2_ACME_LINEAGE" \
    --arg hy2_hop_ports "$CFG_HY2_HOP_PORTS" \
    --arg hy2_hop_min "$CFG_HY2_HOP_INTERVAL_MIN" \
    --arg hy2_hop_max "$CFG_HY2_HOP_INTERVAL_MAX" \
    --args '
    def port: if . == "" then null else tonumber end;
    {
      schema: $schema,
      core: $core,
      server_addr: $server_addr,
      node_name: $node_name,
      listen: $listen,
      block_bt: ($block_bt == "1"),
      allow_private: ($allow_private == "1"),
      sockopt: $sockopt,
      vless: {
        enabled: ($vless == "1"),
        port: ($vless_port | port),
        uuid: $vless_uuid,
        sni: $sni,
        target: $target,
        private_key: $private_key,
        public_key: $public_key,
        short_id: $short_id
      },
      ss: {
        enabled: ($ss == "1"),
        port: ($ss_port | port),
        method: $ss_method,
        password: $ss_password,
        network: $ss_network
      },
      hy2: {
        enabled: ($hy2 == "1"),
        port: ($hy2_port | port),
        password: $hy2_password,
        tls: $hy2_tls,
        sni: $hy2_sni,
        cert: $hy2_cert,
        key: $hy2_key,
        cert_sha256: $hy2_cert_sha256,
        obfs: $hy2_obfs,
        obfs_password: $hy2_obfs_password,
        masquerade: $hy2_masquerade,
        cert_file: $hy2_cert_file,
        key_file: $hy2_key_file,
        certbot_hook: ($hy2_certbot_hook == "1"),
        acme: (if $hy2_acme == "1" then {
          enabled: true,
          domain: $hy2_acme_domain,
          email: $hy2_acme_email,
          lineage: $hy2_acme_lineage
        } else {
          enabled: false
        } end),
        hop: {
          ports: $hy2_hop_ports,
          interval_min: ($hy2_hop_min | tonumber),
          interval_max: ($hy2_hop_max | tonumber)
        }
      },
      firewall: {rules: $ARGS.positional}
    }' "${CFG_FW_RULES[@]}"
}

state_save() {
  local tmp
  install -d -m 700 "$TB_STATE_DIR" || return 1
  tmp="$(mktemp "$TB_STATE_DIR/.state.XXXXXX")" || return 1
  if ! chmod 600 "$tmp" || ! state_json >"$tmp" || ! mv -f "$tmp" "$TB_STATE_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

# Only these Linux TCP options are supported. Values are JSON integers;
# zero is represented by an absent key, not an explicit socket override.
sockopt_valid() {
  jq -e '
    type == "object" and all(to_entries[];
      (.key == "tcpKeepAliveIdle" or .key == "tcpKeepAliveInterval" or .key == "tcpUserTimeout")
      and (.value | type == "number")
      and (.value == (.value | floor)) and .value > 0
      and .value <= (if .key == "tcpUserTimeout" then 2147483647 else 32767 end)
    )' <<<"$1" >/dev/null 2>&1
}

check_sockopt_support() {
  if [[ "$1" != "xray" && "$CFG_SOCKOPT" != '{}' ]]; then
    die err_sockopt_core "$1"
  fi
}

# Loads state.json into CFG_*. Returns 1 when there is no state yet.
state_load() {
  local assignments sockopt
  TB_HAS_STATE=0
  [[ -f "$TB_STATE_FILE" ]] || return 1

  # Additive schema-1 field: older nodes have no custom sockopt. Reject
  # malformed options before any command can rewrite their configuration.
  if ! sockopt="$(jq -c 'if .sockopt == null then {} else .sockopt end' "$TB_STATE_FILE" 2>/dev/null)" ||
    ! sockopt_valid "$sockopt"; then
    die err_state_corrupt "$TB_STATE_FILE"
  fi

  # @sh quotes every value for the shell, so eval only ever sees literals.
  assignments="$(jq -r '
    def flag: if . == true then "1" else "0" end;
    def text: if . == null then "" else tostring end;
    def hop_int(defv):
      if . == null then defv
      elif (type == "number") and (. == floor) and . >= 5 and . <= 2147483647 then .
      else error("invalid hy2 hop interval")
      end;
    if (.schema | type) != "number" then error("missing schema") else . end
    | if (.hy2.hop != null) and ((.hy2.hop | type) != "object") then error("invalid hy2.hop") else . end
    | if (.hy2.hop.ports != null) and ((.hy2.hop.ports | type) != "string") then error("invalid hy2.hop.ports") else . end
    | if (.hy2.certbot_hook != null) and ((.hy2.certbot_hook | type) != "boolean") then error("invalid hy2.certbot_hook") else . end
    | if (.hy2.acme != null) and ((.hy2.acme | type) != "object") then error("invalid hy2.acme") else . end
    | if (.hy2.acme.enabled != null) and ((.hy2.acme.enabled | type) != "boolean") then error("invalid hy2.acme.enabled") else . end
    | ((.hy2.hop.interval_min | hop_int(30))) as $hmin
    | ((.hy2.hop.interval_max | hop_int(30))) as $hmax
    | if $hmin > $hmax then error("invalid hy2 hop interval range") else . end
    | @sh "CFG_CORE=\(.core | text)",
      @sh "CFG_SERVER_ADDR=\(.server_addr | text)",
      @sh "CFG_NODE_NAME=\(.node_name | text)",
      @sh "CFG_LISTEN=\(.listen | text)",
      @sh "CFG_BLOCK_BT=\(.block_bt | flag)",
      @sh "CFG_ALLOW_PRIVATE=\(.allow_private | flag)",
      @sh "CFG_VLESS=\(.vless.enabled | flag)",
      @sh "CFG_VLESS_PORT=\(.vless.port | text)",
      @sh "CFG_VLESS_UUID=\(.vless.uuid | text)",
      @sh "CFG_REALITY_SNI=\(.vless.sni | text)",
      @sh "CFG_REALITY_TARGET=\(.vless.target | text)",
      @sh "CFG_REALITY_PRIVATE_KEY=\(.vless.private_key | text)",
      @sh "CFG_REALITY_PUBLIC_KEY=\(.vless.public_key | text)",
      @sh "CFG_REALITY_SHORT_ID=\(.vless.short_id | text)",
      @sh "CFG_SS=\(.ss.enabled | flag)",
      @sh "CFG_SS_PORT=\(.ss.port | text)",
      @sh "CFG_SS_METHOD=\(.ss.method | text)",
      @sh "CFG_SS_PASSWORD=\(.ss.password | text)",
      @sh "CFG_SS_NETWORK=\(.ss.network | text)",
      @sh "CFG_HY2=\(.hy2.enabled | flag)",
      @sh "CFG_HY2_PORT=\(.hy2.port | text)",
      @sh "CFG_HY2_PASSWORD=\(.hy2.password | text)",
      @sh "CFG_HY2_TLS=\(.hy2.tls | text)",
      @sh "CFG_HY2_SNI=\(.hy2.sni | text)",
      @sh "CFG_HY2_CERT=\(.hy2.cert | text)",
      @sh "CFG_HY2_KEY=\(.hy2.key | text)",
      @sh "CFG_HY2_CERT_SHA256=\(.hy2.cert_sha256 | text)",
      @sh "CFG_HY2_OBFS=\(.hy2.obfs | text)",
      @sh "CFG_HY2_OBFS_PASSWORD=\(.hy2.obfs_password | text)",
      @sh "CFG_HY2_MASQUERADE=\(.hy2.masquerade | text)",
      @sh "CFG_HY2_CERT_FILE=\(.hy2.cert_file | text)",
      @sh "CFG_HY2_KEY_FILE=\(.hy2.key_file | text)",
      @sh "CFG_HY2_CERTBOT_HOOK=\(.hy2.certbot_hook | flag)",
      @sh "CFG_HY2_ACME=\(.hy2.acme.enabled | flag)",
      @sh "CFG_HY2_ACME_DOMAIN=\(.hy2.acme.domain | text)",
      @sh "CFG_HY2_ACME_EMAIL=\(.hy2.acme.email | text)",
      @sh "CFG_HY2_ACME_LINEAGE=\(.hy2.acme.lineage | text)",
      @sh "CFG_HY2_HOP_PORTS=\(.hy2.hop.ports | text)",
      @sh "CFG_HY2_HOP_INTERVAL_MIN=\($hmin | tostring)",
      @sh "CFG_HY2_HOP_INTERVAL_MAX=\($hmax | tostring)",
      "CFG_FW_RULES=(" + ((.firewall.rules // []) | map(@sh) | join(" ")) + ")"
  ' "$TB_STATE_FILE" 2>/dev/null)" || die err_state_corrupt "$TB_STATE_FILE"

  eval "$assignments"
  if ! hy2_hop_validate_saved "$CFG_HY2_HOP_PORTS" "$CFG_HY2_HOP_INTERVAL_MIN" "$CFG_HY2_HOP_INTERVAL_MAX"; then
    die err_state_corrupt "$TB_STATE_FILE"
  fi
  CFG_SOCKOPT="$sockopt"
  TB_HAS_STATE=1
}

state_remove() {
  rm -f "$TB_STATE_FILE"
}

# backup_file PATH PREFIX: copies PATH into the backup directory and keeps
# the five most recent copies for that prefix. Prints the backup path.
backup_file() {
  local src="$1" prefix="$2" dest old
  [[ -f "$src" ]] || return 0
  install -d -m 700 "$TB_STATE_DIR" "$TB_BACKUP_DIR" || return 1
  dest="$TB_BACKUP_DIR/$prefix-$(date +%Y%m%d-%H%M%S)-$$.json"
  if ! cp -p "$src" "$dest" || ! chmod 600 "$dest"; then
    rm -f "$dest"
    return 1
  fi
  # Newest first; drop everything after the fifth.
  find "$TB_BACKUP_DIR" -maxdepth 1 -type f -name "$prefix-*.json" -printf '%T@ %p\n' |
    sort -rn | awk 'NR > 5 {sub(/^[^ ]+ /, ""); print}' |
    while IFS= read -r old; do
      rm -f "$old"
    done || true
  printf '%s' "$dest"
}

# ===== src/lib/50-gen.sh =====
#
# Credential generation and validation.

valid_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# X25519 keys as both cores print and read them: 32 bytes, base64url
# without padding (43 characters).
valid_reality_key() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{43}$ ]]
}

# Up to 8 bytes of hex; the digit count must be even.
valid_short_id() {
  [[ "$1" =~ ^([0-9a-fA-F]{2}){0,8}$ ]]
}

valid_ss_method() { in_list "$1" "${TB_SS_METHODS[@]}"; }

ss_key_length() {
  case "$1" in
    2022-blake3-aes-128-gcm) printf '16' ;;
    *) printf '32' ;;
  esac
}

# A Shadowsocks 2022 password is a base64 pre-shared key whose decoded
# length is fixed by the method.
valid_ss_password() {
  local method="$1" password="$2" bytes
  [[ "$password" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  bytes="$(printf '%s' "$password" | openssl base64 -d -A 2>/dev/null | wc -c)"
  [[ "${bytes//[[:space:]]/}" == "$(ss_key_length "$method")" ]]
}

gen_ss_password() {
  openssl rand -base64 "$(ss_key_length "$1")"
}

gen_short_id() {
  openssl rand -hex 8
}

valid_hy2_password() {
  [[ -n "$1" && "$1" != *[[:space:]]* ]]
}

gen_hy2_password() {
  openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n'
}

gen_uuid() {
  local uuid=""
  case "$CFG_CORE" in
    xray) uuid="$("$TB_XRAY_BIN" uuid 2>/dev/null || true)" ;;
    sing-box) uuid="$("$TB_SINGBOX_BIN" generate uuid 2>/dev/null || true)" ;;
  esac
  if ! valid_uuid "$uuid"; then
    uuid="$(cat /proc/sys/kernel/random/uuid)"
  fi
  printf '%s' "$uuid"
}

GEN_PRIVATE_KEY=""
GEN_PUBLIC_KEY=""

# parse_keypair OUTPUT: extracts a key pair from `xray x25519` or
# `sing-box generate reality-keypair` output. The labels changed over time:
#   Private key: / Public key:               (older Xray)
#   PrivateKey: / Password:                  (Xray 25.x)
#   PrivateKey: / Password (PublicKey):      (current Xray)
#   PrivateKey: / PublicKey:                 (sing-box)
# so lines are matched by label rather than by position.
parse_keypair() {
  local output="$1"
  GEN_PRIVATE_KEY="$(printf '%s\n' "$output" |
    awk -F': *' 'tolower($1) ~ /^private ?key$/ {print $NF; exit}')"
  GEN_PUBLIC_KEY="$(printf '%s\n' "$output" |
    awk -F': *' 'tolower($1) ~ /^(public ?key|password)/ {print $NF; exit}')"
  valid_reality_key "$GEN_PRIVATE_KEY" && valid_reality_key "$GEN_PUBLIC_KEY"
}

# Generates a REALITY key pair with the active core, so the encoding always
# matches what that core expects. Result in GEN_PRIVATE_KEY / GEN_PUBLIC_KEY.
gen_reality_keypair() {
  local output=""
  case "$CFG_CORE" in
    xray) output="$("$TB_XRAY_BIN" x25519 2>/dev/null || true)" ;;
    sing-box) output="$("$TB_SINGBOX_BIN" generate reality-keypair 2>/dev/null || true)" ;;
  esac
  parse_keypair "$output"
}

# Fills in whatever credentials are still missing for the enabled protocols.
ensure_credentials() {
  if [[ "$CFG_VLESS" == "1" ]]; then
    valid_uuid "$CFG_VLESS_UUID" || CFG_VLESS_UUID="$(gen_uuid)"
    if ! valid_reality_key "$CFG_REALITY_PRIVATE_KEY" || ! valid_reality_key "$CFG_REALITY_PUBLIC_KEY"; then
      gen_reality_keypair || die err_keypair "$CFG_CORE"
      CFG_REALITY_PRIVATE_KEY="$GEN_PRIVATE_KEY"
      CFG_REALITY_PUBLIC_KEY="$GEN_PUBLIC_KEY"
    fi
    if [[ -z "$CFG_REALITY_SHORT_ID" ]] || ! valid_short_id "$CFG_REALITY_SHORT_ID"; then
      CFG_REALITY_SHORT_ID="$(gen_short_id)"
    fi
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    # Also catches a method change: the key length differs between methods.
    if ! valid_ss_password "$CFG_SS_METHOD" "$CFG_SS_PASSWORD"; then
      CFG_SS_PASSWORD="$(gen_ss_password "$CFG_SS_METHOD")"
    fi
  fi
  if [[ "$CFG_HY2" == "1" ]]; then
    valid_hy2_password "$CFG_HY2_PASSWORD" || CFG_HY2_PASSWORD="$(gen_hy2_password)"
    if [[ "$CFG_HY2_OBFS" == "salamander" ]]; then
      valid_hy2_password "$CFG_HY2_OBFS_PASSWORD" || CFG_HY2_OBFS_PASSWORD="$(gen_hy2_password)"
    else
      CFG_HY2_OBFS_PASSWORD=""
    fi
    if [[ "$CFG_HY2_TLS" == "self-signed" ]]; then
      if [[ -z "$CFG_HY2_CERT" || -z "$CFG_HY2_KEY" ]] ||
        ! tls_validate_pem_pair "$CFG_HY2_CERT" "$CFG_HY2_KEY"; then
        tls_generate_self_signed "$CFG_SERVER_ADDR" "$CFG_HY2_SNI" || die err_hy2_tls_gen
        CFG_HY2_CERT="$TLS_CERT_PEM"
        CFG_HY2_KEY="$TLS_KEY_PEM"
        CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"
      elif [[ -z "$CFG_HY2_CERT_SHA256" ]]; then
        CFG_HY2_CERT_SHA256="$(tls_cert_sha256_pem "$CFG_HY2_CERT")" || die err_hy2_tls_gen
      fi
    elif [[ -z "$CFG_HY2_CERT_SHA256" && -n "$CFG_HY2_CERT" ]]; then
      CFG_HY2_CERT_SHA256="$(tls_cert_sha256_pem "$CFG_HY2_CERT")" || die err_hy2_tls_invalid
    fi
  fi
}

clear_credentials() {
  CFG_VLESS_UUID=""
  CFG_REALITY_PRIVATE_KEY=""
  CFG_REALITY_PUBLIC_KEY=""
  CFG_REALITY_SHORT_ID=""
  CFG_SS_PASSWORD=""
  CFG_HY2_PASSWORD=""
  CFG_HY2_OBFS_PASSWORD=""
}

# ===== src/lib/55-tls.sh =====
#
# TLS certificate generation, import, validation and SHA-256 pinning for
# Hysteria 2. Certificates and keys are stored as PEM text in state.json and
# embedded directly in the core configurations.

TLS_CERT_PEM=""
TLS_KEY_PEM=""
TLS_CERT_SHA256=""

# Normalizes PATH to an absolute path without dereferencing symlinks (important
# for Certbot /etc/letsencrypt/live/<lineage> symlinks).
tls_abs_path() {
  local path="$1" dir base
  [[ -n "$path" ]] || return 1
  if has_cmd realpath && realpath -s / >/dev/null 2>&1; then
    realpath -s "$path" 2>/dev/null && return 0
  fi
  dir="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  dir="$(cd -L -- "$dir" 2>/dev/null && pwd -L)" || return 1
  printf '%s/%s' "${dir%/}" "$base"
}

# Prints the lowercase 64-hex SHA-256 fingerprint of the leaf certificate
# in CERT_FILE.
tls_cert_sha256_file() {
  local cert_file="$1" fp
  fp="$(openssl x509 -noout -fingerprint -sha256 -in "$cert_file" 2>/dev/null |
    sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$fp"
}

tls_cert_sha256_pem() {
  local cert_pem="$1" fp
  fp="$(openssl x509 -noout -fingerprint -sha256 <<<"$cert_pem" 2>/dev/null |
    sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$fp"
}

# tls_cert_matches_name CERT_FILE HOST_OR_IP: checks whether the leaf
# certificate is valid for the given domain name or IP literal.
tls_cert_matches_name() {
  local cert_file="$1" name="${2#[}" match_out=""
  name="${name%]}"
  [[ -n "$name" ]] || return 1
  if valid_ipv4 "$name" || valid_ipv6 "$name"; then
    match_out="$(openssl x509 -noout -checkip "$name" -in "$cert_file" 2>/dev/null || true)"
  else
    match_out="$(openssl x509 -noout -checkhost "$name" -in "$cert_file" 2>/dev/null || true)"
  fi
  [[ "$match_out" == *"does match certificate"* ]]
}

tls_pem_matches_name() {
  local cert_pem="$1" name="$2" tmp
  tb_mktemp_dir
  tmp="$TB_TMP/tls-check.crt"
  printf '%s\n' "$cert_pem" >"$tmp"
  tls_cert_matches_name "$tmp" "$name"
}

# Extracts the first concrete DNS name from SAN (or CN) in CERT_FILE.
tls_cert_first_dns_name() {
  local cert_file="$1" san="" cn=""
  san="$(openssl x509 -noout -ext subjectAltName -in "$cert_file" 2>/dev/null |
    grep -oE 'DNS:[^,[:space:]]+' | head -n1 | sed 's/^DNS://' || true)"
  if [[ -n "$san" ]] && valid_domain "$san"; then
    printf '%s' "${san,,}"
    return 0
  fi
  cn="$(openssl x509 -noout -subject -nameopt RFC2253 -in "$cert_file" 2>/dev/null |
    sed -n 's/^subject=.*CN=\([^,]*\).*/\1/p')"
  if [[ -n "$cn" ]] && valid_domain "$cn"; then
    printf '%s' "${cn,,}"
    return 0
  fi
  return 1
}

# Builds a comma-separated OpenSSL subjectAltName list from the server
# address and optional SNI, deduplicating identical entries.
tls_build_san() {
  local server_addr="${1#[}" sni="${2#[}" item entry
  local -a entries=()
  server_addr="${server_addr%]}"
  sni="${sni%]}"
  for item in "$sni" "$server_addr"; do
    [[ -n "$item" ]] || continue
    if valid_ipv4 "$item" || valid_ipv6 "$item"; then
      entry="IP:$item"
    else
      entry="DNS:$item"
    fi
    in_list "$entry" "${entries[@]}" || entries+=("$entry")
  done
  if ((${#entries[@]} == 0)); then
    entries+=("DNS:localhost")
  fi
  join_by , "${entries[@]}"
}

# tls_generate_self_signed SERVER_ADDR [SNI]: creates an ECDSA P-256
# self-signed certificate valid for 10 years, storing PEM text and leaf
# SHA-256 fingerprint in TLS_CERT_PEM / TLS_KEY_PEM / TLS_CERT_SHA256.
tls_generate_self_signed() {
  local server_addr="${1#[}" sni="${2#[}" cn san cnf key_file cert_file
  server_addr="${server_addr%]}"
  sni="${sni%]}"
  tb_mktemp_dir
  cnf="$TB_TMP/tls.cnf"
  key_file="$TB_TMP/tls-gen.key"
  cert_file="$TB_TMP/tls-gen.crt"
  rm -f "$cnf" "$key_file" "$cert_file"

  cn="${sni:-${server_addr:-localhost}}"
  san="$(tls_build_san "$server_addr" "$sni")"
  cat >"$cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no

[dn]
CN = $cn

[v3_ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = $san
EOF

  (
    umask 077
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$key_file" 2>/dev/null &&
      openssl req -new -x509 -sha256 -days 3650 -key "$key_file" -config "$cnf" -out "$cert_file" 2>/dev/null
  ) || {
    rm -f "$cnf" "$key_file" "$cert_file"
    return 1
  }

  TLS_CERT_PEM="$(tr -d '\r' <"$cert_file")"
  TLS_KEY_PEM="$(tr -d '\r' <"$key_file")"
  TLS_CERT_SHA256="$(tls_cert_sha256_file "$cert_file")" || {
    rm -f "$cnf" "$key_file" "$cert_file"
    return 1
  }
  rm -f "$cnf" "$key_file" "$cert_file"
}

# tls_validate_pair_files CERT_FILE KEY_FILE: checks that CERT_FILE is an
# unexpired PEM certificate chain, KEY_FILE is an unencrypted private key,
# and their public keys match. Populates TLS_CERT_PEM / TLS_KEY_PEM /
# TLS_CERT_SHA256.
tls_validate_pair_files() {
  local cert_file="$1" key_file="$2" tmp_cert tmp_key cert_pub key_pub
  tb_mktemp_dir
  tmp_cert="$TB_TMP/tls-import.crt"
  tmp_key="$TB_TMP/tls-import.key"
  [[ -f "$cert_file" && -r "$cert_file" ]] || return 1
  [[ -f "$key_file" && -r "$key_file" ]] || return 1

  tr -d '\r' <"$cert_file" >"$tmp_cert"
  (
    umask 077
    tr -d '\r' <"$key_file" >"$tmp_key"
  )

  if ! openssl x509 -noout -checkend 0 -in "$tmp_cert" >/dev/null 2>&1 ||
    ! openssl pkey -in "$tmp_key" -passin pass: -noout >/dev/null 2>&1; then
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  fi

  cert_pub="$(openssl x509 -noout -pubkey -in "$tmp_cert" 2>/dev/null || true)"
  key_pub="$(openssl pkey -pubout -in "$tmp_key" -passin pass: 2>/dev/null || true)"
  if [[ -z "$cert_pub" || "$cert_pub" != "$key_pub" ]]; then
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  fi

  TLS_CERT_SHA256="$(tls_cert_sha256_file "$tmp_cert")" || {
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  }
  TLS_CERT_PEM="$(<"$tmp_cert")"
  TLS_KEY_PEM="$(<"$tmp_key")"
  rm -f "$tmp_cert" "$tmp_key"
}

tls_validate_pem_pair() {
  local cert_pem="$1" key_pem="$2" tmp_cert tmp_key
  [[ -n "$cert_pem" && -n "$key_pem" ]] || return 1
  tb_mktemp_dir
  tmp_cert="$TB_TMP/tls-mem.crt"
  tmp_key="$TB_TMP/tls-mem.key"
  printf '%s\n' "$cert_pem" >"$tmp_cert"
  (
    umask 077
    printf '%s\n' "$key_pem" >"$tmp_key"
  )
  local rc=0
  tls_validate_pair_files "$tmp_cert" "$tmp_key" || rc=$?
  rm -f "$tmp_cert" "$tmp_key"
  return "$rc"
}

# ===== src/lib/56-cert-hook.sh =====
#
# Certbot deploy hook management for Hysteria 2 imported public certificates.

certbot_live_root() {
  local dir
  if [[ -d "$TB_CERTBOT_LIVE_DIR" ]]; then
    dir="$(tls_abs_path "$TB_CERTBOT_LIVE_DIR" || printf '%s' "${TB_CERTBOT_LIVE_DIR%/}")"
  else
    dir="${TB_CERTBOT_LIVE_DIR%/}"
  fi
  printf '%s' "${dir%/}"
}

# certbot_lineage_from_pair CERT_FILE KEY_FILE: validates that both files point
# to the same standard <live>/<lineage>/(fullchain|privkey).pem pair and prints
# the lineage name.
certbot_lineage_from_pair() {
  local cert_file="$1" key_file="$2" live rest lineage
  live="$(certbot_live_root)"
  [[ -n "$live" && "$cert_file" == "$live/"*"/fullchain.pem" ]] || return 1
  rest="${cert_file#"$live"/}"
  lineage="${rest%/fullchain.pem}"
  [[ -n "$lineage" && "$lineage" != "." && "$lineage" != ".." && "$lineage" != */* ]] || return 1
  [[ "$key_file" == "$live/$lineage/privkey.pem" ]] || return 1
  printf '%s' "$lineage"
}

certbot_hook_is_ours() {
  local path="${1:-$TB_CERTBOT_HOOK_PATH}"
  [[ -f "$path" ]] && grep -qF "$TB_CERTBOT_HOOK_MARKER" "$path"
}

certbot_can_install_entrypoint() {
  [[ -x "$TB_SELF_PATH" ]] && return 0
  [[ "${TB_BUILT:-0}" == "1" && -f "${BASH_SOURCE[0]:-}" ]] && return 0
  [[ -n "${TB_SRC_DIR:-}" && -f "$TB_SRC_DIR/../scripts/build.sh" ]] && return 0
  return 1
}

certbot_build_entrypoint() {
  local dir tmp
  dir="$(dirname "$TB_SELF_PATH")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-self.XXXXXX")" || return 1
  if ! bash "$TB_SRC_DIR/../scripts/build.sh" "$tmp" >/dev/null 2>&1 ||
    ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$TB_SELF_PATH"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
  log_ok ok_self_installed "$TB_SELF_PATH"
}

certbot_ensure_entrypoint() {
  local src="${BASH_SOURCE[0]:-}"
  if [[ "${TB_BUILT:-0}" == "1" && -f "$src" ]]; then
    self_install
    return $?
  fi
  if [[ -n "${TB_SRC_DIR:-}" && -f "$TB_SRC_DIR/../scripts/build.sh" ]]; then
    certbot_build_entrypoint
    return $?
  fi
  [[ -x "$TB_SELF_PATH" ]] && return 0
  return 1
}

certbot_hook_preflight() {
  if [[ -e "$TB_CERTBOT_HOOK_PATH" ]] && ! certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    die err_hy2_foreign_hook "$TB_CERTBOT_HOOK_PATH"
  fi
  certbot_can_install_entrypoint || die err_hy2_hook_needs_self "$TB_SELF_PATH"
}

certbot_hook_render() {
  cat <<EOF
#!/usr/bin/env bash
$TB_CERTBOT_HOOK_MARKER
set -euo pipefail

state_file="\${TOASTBOX_STATE_DIR:-/etc/toastbox}/state.json"
entry="\${TOASTBOX_SELF_PATH:-$TB_SELF_PATH}"
renewed="\${RENEWED_LINEAGE:-}"

[[ -n "\$renewed" ]] || exit 0
[[ -r "\$state_file" ]] || exit 0

eval "\$(jq -r '
  if (.hy2.enabled // false) == true and (.hy2.tls // "") == "files" and (.hy2.certbot_hook // false) == true
  then @sh "cert_file=\(.hy2.cert_file // "")"
  else "cert_file="
  end
' "\$state_file" 2>/dev/null || echo 'cert_file=')"

[[ -n "\${cert_file:-}" ]] || exit 0
expected_lineage="\$(dirname -- "\$cert_file")"
renewed="\${renewed%/}"
expected_lineage="\${expected_lineage%/}"

if [[ "\$renewed" != "\$expected_lineage" ]]; then
  exit 0
fi

if [[ ! -x "\$entry" ]]; then
  echo "ToastBox entrypoint is missing or not executable: \$entry" >&2
  exit 1
fi

exec "\$entry" refresh-cert
EOF
}

certbot_hook_install() {
  local dir tmp
  if [[ -e "$TB_CERTBOT_HOOK_PATH" ]] && ! certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    log_err err_hy2_foreign_hook "$TB_CERTBOT_HOOK_PATH"
    return 1
  fi
  dir="$(dirname "$TB_CERTBOT_HOOK_PATH")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-hook.XXXXXX")" || return 1
  if ! certbot_hook_render >"$tmp" ||
    ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$TB_CERTBOT_HOOK_PATH"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

certbot_hook_remove() {
  if certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    rm -f "$TB_CERTBOT_HOOK_PATH"
  fi
}

certbot_hook_backup() {
  local dir="$1"
  install -d -m 700 "$dir" || return 1
  if certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    cp -p "$TB_CERTBOT_HOOK_PATH" "$dir/toastbox-hy2.sh"
  fi
}

certbot_hook_restore() {
  local dir="$1" target_dir
  certbot_hook_remove
  if [[ -f "$dir/toastbox-hy2.sh" ]]; then
    target_dir="$(dirname "$TB_CERTBOT_HOOK_PATH")"
    install -d -m 755 "$target_dir" || true
    install_owned 755 root root "$dir/toastbox-hy2.sh" "$TB_CERTBOT_HOOK_PATH" || true
  fi
}

# ===== src/lib/57-acme.sh =====
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

# ===== src/lib/60-xray.sh =====
#
# Xray: installation through the official XTLS/Xray-install script and
# server configuration rendering.
#
# Field names follow the current documentation (xtls.github.io):
#   inbound settings      users        (was: clients)
#   streamSettings        method: raw  (was: network: tcp)
#   realitySettings       target       (was: dest)
# which is why TB_XRAY_MIN_VERSION exists.

xray_service() { printf 'xray'; }
xray_process() { printf 'xray'; }
xray_config_path() { printf '%s' "$TB_XRAY_CONFIG"; }
xray_min_version() { printf '%s' "$TB_XRAY_MIN_VERSION"; }

xray_is_installed() { [[ -x "$TB_XRAY_BIN" ]]; }

# "Xray 26.11.9 (Xray, Penetrates Everything.) ..." -> 26.11.9
xray_version() {
  "$TB_XRAY_BIN" version 2>/dev/null | awk 'NR == 1 {print $2}'
}

xray_run_installer() {
  local script="$TB_TMP/xray-install.sh"
  if [[ ! -s "$script" ]]; then
    tb_download "$TB_XRAY_INSTALLER_URL" "$script" || die err_download "$TB_XRAY_INSTALLER_URL"
  fi
  bash "$script" "$@" >&2
}

# xray_install [VERSION]: installs or upgrades. The official installer
# creates the dedicated `xray` user, the systemd units and the directories
# with the permissions it expects.
xray_install() {
  local version="${1:-}"
  local -a args=(install)
  if [[ -n "$version" ]]; then
    args+=(--version "v${version#v}")
  fi
  xray_run_installer "${args[@]}"
}

xray_remove() {
  local purge="$1"
  local -a args=(remove)
  [[ "$purge" == "1" ]] && args+=(--purge)
  xray_run_installer "${args[@]}"
}

xray_validate() {
  "$TB_XRAY_BIN" run -test -c "$1"
}

XRAY_CFG_OWNER="root"
XRAY_CFG_GROUP="root"
XRAY_CFG_MODE="600"

xray_is_dedicated_group() {
  case "$1" in
    "" | root | nogroup | nobody | users) return 1 ;;
    *) getent group "$1" >/dev/null 2>&1 ;;
  esac
}

xray_first_dedicated_group() {
  local -a groups=()
  local grp
  [[ -n "$1" ]] || return 1
  IFS=' ' read -r -a groups <<<"$1"
  for grp in "${groups[@]}"; do
    if xray_is_dedicated_group "$grp"; then
      printf '%s' "$grp"
      return 0
    fi
  done
  return 1
}

# Resolves owner, group and mode for TB_XRAY_CONFIG from the xray systemd
# unit so credentials are never exposed world-readable (0644).
xray_config_perms() {
  local svc svc_user="" svc_group="" supp_groups="" dyn_user=""
  local primary_gid="" primary_grp="" grp=""
  XRAY_CFG_OWNER="root"
  XRAY_CFG_GROUP="root"
  XRAY_CFG_MODE="600"

  svc="$(xray_service)"
  if service_unit_exists "$svc"; then
    svc_user="$(service_unit_prop "$svc" User)"
    svc_group="$(service_unit_prop "$svc" Group)"
    supp_groups="$(service_unit_prop "$svc" SupplementaryGroups)"
    dyn_user="$(service_unit_prop "$svc" DynamicUser)"

    # When the unit runs as root, keep the configuration strictly root-only.
    if [[ "$dyn_user" != "yes" ]] &&
      [[ -z "$svc_user" || "$svc_user" == "root" || "$svc_user" == "0" ]]; then
      return 0
    fi

    if xray_is_dedicated_group "$svc_group"; then
      XRAY_CFG_GROUP="$svc_group"
      XRAY_CFG_MODE="640"
      return 0
    fi

    if [[ "$dyn_user" == "yes" ]]; then
      if grp="$(xray_first_dedicated_group "$supp_groups")"; then
        XRAY_CFG_GROUP="$grp"
        XRAY_CFG_MODE="640"
        return 0
      fi
      log_err err_xray_dynamic_user "$svc" "$TB_XRAY_CONFIG"
      return 1
    fi

    primary_gid="$(getent passwd "$svc_user" 2>/dev/null | awk -F: 'NR == 1 {print $4}')"
    if [[ -z "$primary_gid" ]]; then
      log_err err_xray_service_user "$svc" "$svc_user"
      return 1
    fi
    primary_grp="$(getent group "$primary_gid" 2>/dev/null | awk -F: 'NR == 1 {print $1}')"
    if [[ -z "$svc_group" ]] && xray_is_dedicated_group "$primary_grp"; then
      XRAY_CFG_GROUP="$primary_grp"
      XRAY_CFG_MODE="640"
      return 0
    fi

    if grp="$(xray_first_dedicated_group "$supp_groups")"; then
      XRAY_CFG_GROUP="$grp"
      XRAY_CFG_MODE="640"
      return 0
    fi

    # Service runs as an unprivileged user without a dedicated group (e.g.
    # nobody or a system account in nogroup): restrict reads to that UID only.
    XRAY_CFG_OWNER="$svc_user"
    XRAY_CFG_GROUP="root"
    XRAY_CFG_MODE="600"
    return 0
  fi

  # Fallback when systemd is unavailable or the unit is not installed yet.
  if getent group xray >/dev/null 2>&1; then
    XRAY_CFG_GROUP="xray"
    XRAY_CFG_MODE="640"
  elif getent passwd xray >/dev/null 2>&1; then
    XRAY_CFG_OWNER="xray"
    XRAY_CFG_GROUP="root"
    XRAY_CFG_MODE="600"
  fi
  return 0
}

# The service usually runs as the unprivileged `xray` user: the configuration
# holds the REALITY private key, so access is restricted to root and the
# service identity (never world-readable).
xray_install_config() {
  local src="$1" dir tmp
  dir="$(dirname "$TB_XRAY_CONFIG")"
  tmp="$TB_XRAY_CONFIG.toastbox-new"
  xray_config_perms || return 1
  if [[ ! -d "$dir" ]]; then
    install -d -m 755 "$dir" || return 1
  fi
  if ! install_owned "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP" "$src" "$tmp" ||
    ! mv -f "$tmp" "$TB_XRAY_CONFIG"; then
    rm -f "$tmp"
    return 1
  fi
}

# Xray loads exactly one file, so nothing else can leak into the node.
xray_extra_configs() { :; }

xray_render() {
  local ss_network
  case "$CFG_SS_NETWORK" in
    tcp) ss_network="tcp" ;;
    udp) ss_network="udp" ;;
    *) ss_network="tcp,udp" ;;
  esac

  jq -n \
    --arg listen "$CFG_LISTEN" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --argjson sockopt "$CFG_SOCKOPT" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target "$CFG_REALITY_TARGET" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$ss_network" \
    --arg hy2 "$CFG_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_key "$CFG_HY2_KEY" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_masquerade "$CFG_HY2_MASQUERADE" \
    --args '
    def with_listen: if $listen == "" then . else {listen: $listen} + . end;
    # routeOnly: the sniffed protocol is used for routing only, the
    # destination of the connection is left untouched.
    def with_sniffing:
      if $block_bt == "1"
      then . + {sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}
      else . end;
    def pem_lines: sub("\n+$"; "") | split("\n");

    {
      log: {access: "none", logLevel: "warning"},
      inbounds: [
        (if $vless == "1" then
          {
            tag: "vless-reality",
            port: ($vless_port | tonumber),
            protocol: "vless",
            settings: {
              users: [{id: $uuid, flow: "xtls-rprx-vision"}],
              decryption: "none"
            },
            streamSettings: ({
              method: "raw",
              security: "reality",
              realitySettings: {
                target: $target,
                serverNames: [$sni],
                privateKey: $private_key,
                shortIds: [$short_id]
              }
            } + (if $sockopt == {} then {} else {sockopt: $sockopt} end))
          } | with_listen | with_sniffing
        else empty end),
        (if $ss == "1" then
          {
            tag: "ss-2022",
            port: ($ss_port | tonumber),
            protocol: "shadowsocks",
            settings: {
              network: $ss_network,
              method: $ss_method,
              password: $ss_password
            }
          }
          # Socket overrides affect the TCP listener only, never UDP.
          + (if $sockopt != {} and $ss_network != "udp"
             then {streamSettings: {sockopt: $sockopt}} else {} end)
          | with_listen | with_sniffing
        else empty end),
        (if $hy2 == "1" then
          {
            tag: "hysteria2",
            port: ($hy2_port | tonumber),
            protocol: "hysteria",
            settings: {
              version: 2,
              users: [{auth: $hy2_password}]
            },
            streamSettings: ({
              method: "hysteria",
              security: "tls",
              tlsSettings: {
                alpn: ["h3"],
                certificates: [
                  {
                    certificate: ($hy2_cert | pem_lines),
                    key: ($hy2_key | pem_lines)
                  }
                ]
              },
              hysteriaSettings: ({
                version: 2
              } + (if $hy2_masquerade != "" then {
                masquerade: {
                  type: "proxy",
                  url: $hy2_masquerade,
                  rewriteHost: true
                }
              } else {} end))
            } + (if $hy2_obfs == "salamander" then {
              finalmask: {
                udp: [
                  {
                    type: "salamander",
                    settings: {password: $hy2_obfs_password}
                  }
                ]
              }
            } else {} end))
          } | with_listen | with_sniffing
        else empty end)
      ],
      outbounds: [
        ({tag: "direct", protocol: "freedom"}
         + (if $allow_private == "1"
            then {settings: {finalRules: [{action: "allow"}]}}
            else {} end)),
        {tag: "block", protocol: "blackhole"}
      ],
      routing: {
        rules: [
          (if $block_bt == "1"
           then {protocol: ["bittorrent"], outboundTag: "block"} else empty end),
          (if $allow_private == "1"
           then empty else {ip: $ARGS.positional, outboundTag: "block"} end)
        ]
      }
    }' "${TB_PRIVATE_CIDRS[@]}"
}

# ===== src/lib/61-singbox.sh =====
#
# sing-box: installation from the official APT repository and server
# configuration rendering.
#
# Only the current configuration format is written (sing-box.sagernet.org):
# no legacy inbound fields (`sniff`, `domain_strategy`) and no special
# outbounds (`block`, `dns`), which were replaced by rule actions in 1.11.

singbox_service() { printf 'sing-box'; }
singbox_process() { printf 'sing-box'; }
singbox_config_path() { printf '%s' "$TB_SINGBOX_CONFIG"; }
singbox_min_version() { printf '%s' "$TB_SINGBOX_MIN_VERSION"; }

singbox_is_installed() { [[ -x "$TB_SINGBOX_BIN" ]]; }

# "sing-box version 1.14.4" -> 1.14.4
singbox_version() {
  "$TB_SINGBOX_BIN" version 2>/dev/null | awk 'NR == 1 {print $3}'
}

singbox_setup_repo() {
  install -d -m 755 /etc/apt/keyrings || return 1
  tb_download "$TB_SINGBOX_KEY_URL" "$TB_SINGBOX_KEYRING" || die err_download "$TB_SINGBOX_KEY_URL"
  chmod a+r "$TB_SINGBOX_KEYRING" || return 1
  cat >"$TB_SINGBOX_APT_SOURCE" <<EOF || return 1
Types: deb
URIs: $TB_SINGBOX_APT_URL
Suites: *
Components: *
Enabled: yes
Signed-By: $TB_SINGBOX_KEYRING
EOF
}

# singbox_install [VERSION]: installs or upgrades the `sing-box` package.
#
# The package ships /etc/sing-box/config.json as a sample (a Shadowsocks
# inbound with a published password) but does not start the service, so
# nothing is exposed until ToastBox has replaced that file.
singbox_install() {
  local version="${1:-}" package="sing-box"
  singbox_setup_repo || return 1
  apt-get update >&2 || die err_apt_update
  if [[ -n "$version" ]]; then
    # Debian versions use "~" where the release tag has "-".
    version="${version#v}"
    package="sing-box=${version//-/\~}"
  fi
  apt_install --allow-downgrades "$package" || die err_apt_install "$package"
}

singbox_remove() {
  local purge="$1"
  if [[ "$purge" == "1" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sing-box >&2 || return 1
    rm -rf "$(dirname "$TB_SINGBOX_CONFIG")" /var/lib/sing-box
    rm -f "$TB_SINGBOX_APT_SOURCE" "$TB_SINGBOX_KEYRING"
  else
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sing-box >&2 || return 1
  fi
}

singbox_validate() {
  "$TB_SINGBOX_BIN" check -c "$1"
}

# The packaged unit runs sing-box as root, so root-only permissions work.
singbox_install_config() {
  local src="$1" dir tmp
  dir="$(dirname "$TB_SINGBOX_CONFIG")"
  # The temporary name must not end in .json: the service merges every
  # *.json file in this directory.
  tmp="$TB_SINGBOX_CONFIG.toastbox-new"
  install -d "$dir" || return 1
  if ! install_owned 600 root root "$src" "$tmp" ||
    ! mv -f "$tmp" "$TB_SINGBOX_CONFIG"; then
    rm -f "$tmp"
    return 1
  fi
}

# The unit starts sing-box with `-C /etc/sing-box`, which merges all JSON
# files in that directory. Lists the ones ToastBox does not manage.
singbox_extra_configs() {
  local dir file
  dir="$(dirname "$TB_SINGBOX_CONFIG")"
  [[ -d "$dir" ]] || return 0
  for file in "$dir"/*.json; do
    [[ -e "$file" && "$file" != "$TB_SINGBOX_CONFIG" ]] && printf '%s\n' "$file"
  done
  return 0
}

singbox_render() {
  local listen="$CFG_LISTEN"
  # Xray sockopt names are not sing-box listen fields; never drop them
  # silently when switching cores or rendering directly.
  check_sockopt_support sing-box
  if [[ -z "$listen" ]]; then
    # `listen` is required. "::" is dual-stack, but fails to bind on hosts
    # where IPv6 is disabled.
    if ipv6_enabled; then listen="::"; else listen="0.0.0.0"; fi
  fi

  jq -n \
    --arg listen "$listen" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target_host "$(host_of "$CFG_REALITY_TARGET")" \
    --arg target_port "$(port_of "$CFG_REALITY_TARGET")" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$CFG_SS_NETWORK" \
    --arg hy2 "$CFG_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_key "$CFG_HY2_KEY" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_masquerade "$CFG_HY2_MASQUERADE" '
    def pem_lines: sub("\n+$"; "") | split("\n");
    {
      log: {level: "warn", timestamp: true},
      inbounds: [
        (if $vless == "1" then
          {
            type: "vless",
            tag: "vless-reality",
            listen: $listen,
            listen_port: ($vless_port | tonumber),
            users: [{name: "toastbox", uuid: $uuid, flow: "xtls-rprx-vision"}],
            tls: {
              enabled: true,
              server_name: $sni,
              reality: {
                enabled: true,
                handshake: {server: $target_host, server_port: ($target_port | tonumber)},
                private_key: $private_key,
                short_id: [$short_id]
              }
            }
          }
        else empty end),
        (if $ss == "1" then
          {
            type: "shadowsocks",
            tag: "ss-2022",
            listen: $listen,
            listen_port: ($ss_port | tonumber)
          }
          # An absent `network` means TCP and UDP.
          + (if $ss_network == "tcp" or $ss_network == "udp" then {network: $ss_network} else {} end)
          + {method: $ss_method, password: $ss_password}
        else empty end),
        (if $hy2 == "1" then
          {
            type: "hysteria2",
            tag: "hysteria2",
            listen: $listen,
            listen_port: ($hy2_port | tonumber),
            users: [{name: "toastbox", password: $hy2_password}],
            tls: {
              enabled: true,
              certificate: ($hy2_cert | pem_lines),
              key: ($hy2_key | pem_lines)
            }
          }
          + (if $hy2_obfs == "salamander" then {
            obfs: {
              type: "salamander",
              password: $hy2_obfs_password
            }
          } else {} end)
          + (if $hy2_masquerade != "" then {
            masquerade: {
              type: "proxy",
              url: $hy2_masquerade,
              rewrite_host: true
            }
          } else {} end)
        else empty end)
      ],
      outbounds: [
        {type: "direct", tag: "direct"}
      ],
      route: {
        rules: [
          (if $block_bt == "1" then
            {action: "sniff"},
            {protocol: "bittorrent", action: "reject"}
          else empty end),
          (if $allow_private == "1"
           then empty else {ip_is_private: true, action: "reject"} end)
        ],
        final: "direct"
      }
    }'
}

# ===== src/lib/70-output.sh =====
#
# Everything a client needs: share links, ready-to-run client
# configurations for both cores, and the human-readable summary.

urlencode() {
  jq -rn --arg v "$1" '$v | @uri'
}

link_label() {
  printf '%s-%s' "${CFG_NODE_NAME:-ToastBox}" "$1"
}

# Share link in the format understood by v2rayN / v2rayNG / NekoBox /
# Shadowrocket and friends. `type=tcp` is the name clients use for what
# Xray now calls the RAW transport.
vless_link() {
  local query
  query="encryption=none&flow=xtls-rprx-vision&security=reality"
  query+="&sni=$(urlencode "$CFG_REALITY_SNI")&fp=chrome"
  query+="&pbk=$(urlencode "$CFG_REALITY_PUBLIC_KEY")"
  query+="&sid=$(urlencode "$CFG_REALITY_SHORT_ID")"
  query+="&type=tcp&headerType=none"
  printf 'vless://%s@%s:%s?%s#%s\n' \
    "$CFG_VLESS_UUID" "$(uri_host "$CFG_SERVER_ADDR")" "$CFG_VLESS_PORT" \
    "$query" "$(urlencode "$(link_label vless)")"
}

# SIP002. For the 2022 methods the user info is "method:password" in
# percent-encoded plain text, not base64.
ss_link() {
  printf 'ss://%s:%s@%s:%s#%s\n' \
    "$(urlencode "$CFG_SS_METHOD")" "$(urlencode "$CFG_SS_PASSWORD")" \
    "$(uri_host "$CFG_SERVER_ADDR")" "$CFG_SS_PORT" \
    "$(urlencode "$(link_label ss)")"
}

# Official Hysteria 2 share link:
# hysteria2://[auth@]hostname[:port]/?[key=value]#name
hy2_link() {
  local -a params=()
  local query="" port_part="${CFG_HY2_HOP_PORTS:-$CFG_HY2_PORT}"
  if [[ "$CFG_HY2_OBFS" == "salamander" ]]; then
    params+=("obfs=salamander" "obfs-password=$(urlencode "$CFG_HY2_OBFS_PASSWORD")")
  fi
  if [[ "$CFG_HY2_TLS" == "self-signed" ]]; then
    params+=("insecure=1" "pinSHA256=$(urlencode "$CFG_HY2_CERT_SHA256")")
  fi
  if [[ -n "$CFG_HY2_SNI" ]]; then
    params+=("sni=$(urlencode "$CFG_HY2_SNI")")
  fi
  if ((${#params[@]} > 0)); then
    query="?$(join_by '&' "${params[@]}")"
  fi
  printf 'hysteria2://%s@%s:%s/%s#%s\n' \
    "$(urlencode "$CFG_HY2_PASSWORD")" "$(uri_host "$CFG_SERVER_ADDR")" "$port_part" \
    "$query" "$(urlencode "$(link_label hy2)")"
}

# client_jq FILTER: runs a jq filter with the arguments shared by both
# client renderers. OUT_VLESS / OUT_SS / OUT_HY2 select which outbounds are emitted.
client_jq() {
  jq -n \
    --arg server "$CFG_SERVER_ADDR" \
    --arg vless "$OUT_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg public_key "$CFG_REALITY_PUBLIC_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$OUT_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg hy2 "$OUT_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_tls "$CFG_HY2_TLS" \
    --arg hy2_sni "$CFG_HY2_SNI" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_sha256 "$CFG_HY2_CERT_SHA256" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_hop_ports "$CFG_HY2_HOP_PORTS" \
    --arg hy2_hop_min "$CFG_HY2_HOP_INTERVAL_MIN" \
    --arg hy2_hop_max "$CFG_HY2_HOP_INTERVAL_MAX" \
    "$1"
}

# A complete Xray client configuration: SOCKS5 on 127.0.0.1:1080. The first
# outbound is the default one.
client_xray_json() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  client_jq '
    {
      log: {logLevel: "warning"},
      inbounds: [
        {
          tag: "socks-in",
          listen: "127.0.0.1",
          port: 1080,
          protocol: "socks",
          settings: {udp: true}
        }
      ],
      outbounds: [
        (if $vless == "1" then
          {
            tag: "vless-reality",
            protocol: "vless",
            settings: {
              address: $server,
              port: ($vless_port | tonumber),
              id: $uuid,
              encryption: "none",
              flow: "xtls-rprx-vision"
            },
            streamSettings: {
              method: "raw",
              security: "reality",
              realitySettings: {
                serverName: $sni,
                fingerprint: "chrome",
                password: $public_key,
                shortId: $short_id
              }
            }
          }
        else empty end),
        (if $ss == "1" then
          {
            tag: "ss-2022",
            protocol: "shadowsocks",
            settings: {
              address: $server,
              port: ($ss_port | tonumber),
              method: $ss_method,
              password: $ss_password
            }
          }
        else empty end),
        (if $hy2 == "1" then
          {
            tag: "hysteria2",
            protocol: "hysteria",
            settings: {
              version: 2,
              address: $server,
              port: ($hy2_port | tonumber)
            },
            streamSettings: ({
              method: "hysteria",
              security: "tls",
              tlsSettings: ({
                alpn: ["h3"]
              }
              + (if $hy2_sni != "" then {serverName: $hy2_sni} else {} end)
              + (if $hy2_tls == "self-signed"
                 then {pinnedPeerCertSha256: $hy2_sha256}
                 else {useSystemCA: true} end)),
              hysteriaSettings: {
                version: 2,
                auth: $hy2_password
              }
            }
            + (
              [
                (if $hy2_obfs == "salamander" then {
                  type: "salamander",
                  settings: {password: $hy2_obfs_password}
                } else empty end),
                (if $hy2_hop_ports != "" then {
                  type: "udphop",
                  settings: {
                    mode: "intervallocal,intervalremote",
                    interval: (
                      if $hy2_hop_min == $hy2_hop_max
                      then $hy2_hop_min
                      else "\($hy2_hop_min)-\($hy2_hop_max)"
                      end
                    ),
                    remotePorts: $hy2_hop_ports
                  }
                } else empty end)
              ]
              | if length > 0 then {finalmask: {udp: .}} else {} end
            ))
          }
        else empty end)
      ]
    }'
}

# A complete sing-box client configuration: mixed (SOCKS5 + HTTP) proxy on
# 127.0.0.1:1080. REALITY on the client side needs uTLS.
client_singbox_json() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  client_jq '
    def pem_lines: sub("\n+$"; "") | split("\n");
    {
      log: {level: "warn"},
      inbounds: [
        {
          type: "mixed",
          tag: "mixed-in",
          listen: "127.0.0.1",
          listen_port: 1080
        }
      ],
      outbounds: [
        (if $vless == "1" then
          {
            type: "vless",
            tag: "vless-reality",
            server: $server,
            server_port: ($vless_port | tonumber),
            uuid: $uuid,
            flow: "xtls-rprx-vision",
            tls: {
              enabled: true,
              server_name: $sni,
              utls: {enabled: true, fingerprint: "chrome"},
              reality: {enabled: true, public_key: $public_key, short_id: $short_id}
            }
          }
        else empty end),
        (if $ss == "1" then
          {
            type: "shadowsocks",
            tag: "ss-2022",
            server: $server,
            server_port: ($ss_port | tonumber),
            method: $ss_method,
            password: $ss_password
          }
        else empty end),
        (if $hy2 == "1" then
          ({
            type: "hysteria2",
            tag: "hysteria2",
            server: $server
          }
          + (if $hy2_hop_ports != "" then
              ({
                server_ports: (
                  $hy2_hop_ports | split(",") | map(
                    if contains("-") then split("-") | join(":") else "\(.):\(.)" end
                  )
                ),
                hop_interval: "\($hy2_hop_min)s"
              }
              + (if $hy2_hop_min != $hy2_hop_max then {hop_interval_max: "\($hy2_hop_max)s"} else {} end))
            else
              {server_port: ($hy2_port | tonumber)}
            end)
          + {
            password: $hy2_password,
            tls: ({
              enabled: true
            }
            + (if $hy2_sni != "" then {server_name: $hy2_sni} else {} end)
            + (if $hy2_tls == "self-signed" then {
              certificate: ($hy2_cert | pem_lines)
            } else {} end))
          }
          + (if $hy2_obfs == "salamander" then {
            obfs: {
              type: "salamander",
              password: $hy2_obfs_password
            }
          } else {} end))
        else empty end)
      ],
      route: {
        final: (
          if $vless == "1" then "vless-reality"
          elif $ss == "1" then "ss-2022"
          else "hysteria2"
          end
        )
      }
    }'
}

# Official Hysteria 2 client configuration: SOCKS5 on 127.0.0.1:1080.
client_hysteria2_json() {
  local port_part="${CFG_HY2_HOP_PORTS:-$CFG_HY2_PORT}"
  [[ "$OUT_HY2" == "1" ]] || die err_format_requires_hy2
  # shellcheck disable=SC2016  # jq variables, not shell ones
  jq -n \
    --arg server "$(uri_host "$CFG_SERVER_ADDR"):$port_part" \
    --arg auth "$CFG_HY2_PASSWORD" \
    --arg tls_mode "$CFG_HY2_TLS" \
    --arg sni "$CFG_HY2_SNI" \
    --arg pin "$CFG_HY2_CERT_SHA256" \
    --arg obfs "$CFG_HY2_OBFS" \
    --arg obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hop_ports "$CFG_HY2_HOP_PORTS" \
    --arg hop_min "$CFG_HY2_HOP_INTERVAL_MIN" \
    --arg hop_max "$CFG_HY2_HOP_INTERVAL_MAX" '
    {
      server: $server,
      auth: $auth,
      socks5: {listen: "127.0.0.1:1080"}
    }
    + (if $hop_ports != "" then {
      transport: {
        udp: (
          if $hop_min == $hop_max
          then {hopInterval: "\($hop_min)s"}
          else {minHopInterval: "\($hop_min)s", maxHopInterval: "\($hop_max)s"}
          end
        )
      }
    } else {} end)
    + (
      ({}
      + (if $sni != "" then {sni: $sni} else {} end)
      + (if $tls_mode == "self-signed" then {insecure: true, pinSHA256: $pin} else {} end))
      | if . == {} then {} else {tls: .} end
    )
    + (if $obfs == "salamander" then {
      obfs: {
        type: "salamander",
        salamander: {password: $obfs_password}
      }
    } else {} end)'
}

# Machine-readable description: the state plus the share links. Private keys
# are left out: no client needs them, and this output tends to get pasted into
# issues and chats.
show_json() {
  local vless_uri="" ss_uri="" hy2_uri=""
  [[ "$OUT_VLESS" == "1" ]] && vless_uri="$(vless_link)"
  [[ "$OUT_SS" == "1" ]] && ss_uri="$(ss_link)"
  [[ "$OUT_HY2" == "1" ]] && hy2_uri="$(hy2_link)"
  state_json | jq --arg vless "$vless_uri" --arg ss "$ss_uri" --arg hy2 "$hy2_uri" \
    --arg version "$TB_VERSION" '
    del(.firewall, .schema, .vless.private_key, .hy2.key)
    + {toastbox_version: $version}
    + {links: ({} + (if $vless != "" then {vless: $vless} else {} end)
                  + (if $ss != "" then {ss: $ss} else {} end)
                  + (if $hy2 != "" then {hy2: $hy2} else {} end))}'
}

show_links() {
  if [[ "$OUT_VLESS" == "1" ]]; then vless_link; fi
  if [[ "$OUT_SS" == "1" ]]; then ss_link; fi
  if [[ "$OUT_HY2" == "1" ]]; then hy2_link; fi
}

show_qr() {
  local link="$1"
  if ! has_cmd qrencode; then
    log_info info_install_deps "qrencode"
    apt_install qrencode >/dev/null 2>&1 || {
      log_warn warn_no_qrencode
      return 0
    }
  fi
  qrencode -t ANSIUTF8 -m 1 "$link"
}

kv() {
  printf '  %s: %s\n' "$(msg "$1")" "$2"
}

show_text() {
  local svc status version link interval_label="" sg_udp="" udp_list=""
  svc="$(core_call service)"
  if service_is_active "$svc"; then
    status="${TB_C_GREEN}$(msg word_running)${TB_C_RESET}"
  else
    status="${TB_C_RED}$(msg word_stopped)${TB_C_RESET}"
  fi
  version="$(core_call version || true)"

  printf '\n%s== ToastBox ==%s\n' "$TB_C_BOLD" "$TB_C_RESET"
  kv label_core "$CFG_CORE ${version:-?} ($status)"
  kv label_server "$CFG_SERVER_ADDR"
  kv label_config "$(core_call config_path)"
  if [[ "$CFG_SOCKOPT" != '{}' ]]; then kv label_sockopt "$CFG_SOCKOPT"; fi

  if [[ "$OUT_VLESS" == "1" ]]; then
    link="$(vless_link)"
    printf '\n%s-- VLESS + TCP + REALITY + Vision --%s\n' "$TB_C_BOLD" "$TB_C_RESET"
    kv label_port "$CFG_VLESS_PORT/tcp"
    kv label_uuid "$CFG_VLESS_UUID"
    kv label_flow "xtls-rprx-vision"
    kv label_sni "$CFG_REALITY_SNI"
    kv label_target "$CFG_REALITY_TARGET"
    kv label_public_key "$CFG_REALITY_PUBLIC_KEY"
    kv label_short_id "$CFG_REALITY_SHORT_ID"
    kv label_fingerprint "chrome"
    printf '\n  %s\n  %s\n' "$(msg label_link)" "$link"
    if [[ "${OPT_QR:-0}" == "1" ]]; then show_qr "$link"; fi
  fi

  if [[ "$OUT_SS" == "1" ]]; then
    link="$(ss_link)"
    printf '\n%s-- Shadowsocks 2022 --%s\n' "$TB_C_BOLD" "$TB_C_RESET"
    case "$CFG_SS_NETWORK" in
      tcp) kv label_port "$CFG_SS_PORT/tcp" ;;
      udp) kv label_port "$CFG_SS_PORT/udp" ;;
      *) kv label_port "$CFG_SS_PORT/tcp+udp" ;;
    esac
    kv label_method "$CFG_SS_METHOD"
    kv label_password "$CFG_SS_PASSWORD"
    printf '\n  %s\n  %s\n' "$(msg label_link)" "$link"
    if [[ "${OPT_QR:-0}" == "1" ]]; then show_qr "$link"; fi
    printf '\n  %s\n' "$(msg note_ss_landing)"
  fi

  if [[ "$OUT_HY2" == "1" ]]; then
    link="$(hy2_link)"
    printf '\n%s-- Hysteria 2 --%s\n' "$TB_C_BOLD" "$TB_C_RESET"
    kv label_port "$CFG_HY2_PORT/udp"
    kv label_password "$CFG_HY2_PASSWORD"
    kv label_tls "$CFG_HY2_TLS"
    if [[ -n "$CFG_HY2_SNI" ]]; then kv label_sni "$CFG_HY2_SNI"; fi
    if [[ "$CFG_HY2_TLS" == "self-signed" ]]; then
      kv label_pin_sha256 "$CFG_HY2_CERT_SHA256"
    elif [[ -n "$CFG_HY2_CERT_FILE" ]]; then
      kv label_cert_file "$CFG_HY2_CERT_FILE"
      if [[ "$CFG_HY2_ACME" == "1" ]]; then
        kv label_acme_domain "$CFG_HY2_ACME_DOMAIN"
        kv label_acme_lineage "$CFG_HY2_ACME_LINEAGE"
      fi
      if [[ "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
        kv label_cert_hook "certbot"
      fi
    fi
    if [[ "$CFG_HY2_OBFS" == "salamander" ]]; then
      kv label_obfs "salamander"
      kv label_obfs_password "$CFG_HY2_OBFS_PASSWORD"
    fi
    if [[ -n "$CFG_HY2_MASQUERADE" ]]; then
      kv label_masquerade "$CFG_HY2_MASQUERADE"
    fi
    if [[ -n "$CFG_HY2_HOP_PORTS" ]]; then
      interval_label="${CFG_HY2_HOP_INTERVAL_MIN}s"
      if [[ "$CFG_HY2_HOP_INTERVAL_MIN" != "$CFG_HY2_HOP_INTERVAL_MAX" ]]; then
        interval_label="${CFG_HY2_HOP_INTERVAL_MIN}-${CFG_HY2_HOP_INTERVAL_MAX}s"
      fi
      kv label_hop_ports "$CFG_HY2_HOP_PORTS/udp"
      kv label_hop_interval "$interval_label"
    fi
    printf '\n  %s\n  %s\n' "$(msg label_link)" "$link"
    if [[ "${OPT_QR:-0}" == "1" ]]; then show_qr "$link"; fi
    if [[ -n "$CFG_HY2_HOP_PORTS" ]]; then
      if [[ "$CFG_HY2_HOP_INTERVAL_MIN" == "$CFG_HY2_HOP_INTERVAL_MAX" ]]; then
        printf '\n  %s\n' "$(msg note_hy2_hop_clients)"
      else
        printf '\n  %s\n' "$(msg note_hy2_hop_random_clients)"
      fi
    fi
  fi

  if [[ "$CFG_HY2" == "1" && -n "$CFG_HY2_HOP_PORTS" ]]; then
    udp_list="$CFG_HY2_PORT,$CFG_HY2_HOP_PORTS"
    if [[ "$CFG_SS" == "1" && "$CFG_SS_NETWORK" != "tcp" ]]; then
      udp_list="$CFG_SS_PORT,$udp_list"
    fi
    sg_udp="$(norm_hy2_hop_ports "$udp_list")"
  fi
  printf '\n%s\n%s\n' "$(msg note_client_configs)" "$(msg note_firewall)"
  if [[ "$CFG_HY2" == "1" && "$CFG_HY2_ACME" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
    printf '%s\n' "$(msg note_hy2_acme_firewall "$CFG_CORE")"
  fi
  if [[ -n "$sg_udp" ]]; then
    printf '%s\n' "$(msg note_security_group_udp "$sg_udp")"
  fi
  printf '\n'
}

# Decides which protocols `show` prints: every enabled one, optionally
# narrowed down by --protocols.
select_output_protocols() {
  OUT_VLESS="$CFG_VLESS"
  OUT_SS="$CFG_SS"
  OUT_HY2="$CFG_HY2"
  if [[ -n "${OPT_PROTOCOLS:-}" ]]; then
    local want_vless=0 want_ss=0 want_hy2=0
    parse_protocols "$OPT_PROTOCOLS" || die err_protocols "$OPT_PROTOCOLS"
    want_vless="$PARSED_VLESS"
    want_ss="$PARSED_SS"
    want_hy2="$PARSED_HY2"
    [[ "$want_vless" == "1" && "$CFG_VLESS" != "1" ]] && die err_protocol_disabled "vless"
    [[ "$want_ss" == "1" && "$CFG_SS" != "1" ]] && die err_protocol_disabled "ss"
    [[ "$want_hy2" == "1" && "$CFG_HY2" != "1" ]] && die err_protocol_disabled "hy2"
    OUT_VLESS="$want_vless"
    OUT_SS="$want_ss"
    OUT_HY2="$want_hy2"
  fi
  return 0
}

show_node() {
  select_output_protocols
  case "${OPT_FORMAT:-text}" in
    text) show_text ;;
    json) show_json ;;
    links) show_links ;;
    xray) client_xray_json ;;
    sing-box) client_singbox_json ;;
    hysteria2) client_hysteria2_json ;;
    *) die err_format "$OPT_FORMAT" ;;
  esac
}

# ===== src/lib/80-commands.sh =====
#
# Command line parsing, parameter resolution and the commands themselves.

# ---------------------------------------------------------------------------
# Core dispatch
# ---------------------------------------------------------------------------

# core_fn CORE OPERATION [ARGS...] -> xray_OPERATION / singbox_OPERATION
core_fn() {
  local core="$1" op="$2"
  shift 2
  case "$core" in
    xray) "xray_$op" "$@" ;;
    sing-box) "singbox_$op" "$@" ;;
    *) die err_core "$core" ;;
  esac
}

core_call() { core_fn "$CFG_CORE" "$@"; }

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

opt_reset() {
  OPT_COMMAND=""
  OPT_CORE=""
  OPT_PROTOCOLS=""
  OPT_SERVER_ADDR=""
  OPT_NAME=""
  OPT_LISTEN=""
  OPT_VLESS_PORT=""
  OPT_REALITY_SNI=""
  OPT_REALITY_TARGET=""
  OPT_SKIP_TARGET_CHECK=0
  OPT_SS_PORT=""
  OPT_SS_METHOD=""
  OPT_SS_NETWORK=""
  OPT_HY2_PORT=""
  OPT_HY2_SNI=""
  OPT_HY2_TLS=""
  OPT_HY2_CERT=""
  OPT_HY2_KEY=""
  OPT_HY2_OBFS=""
  OPT_HY2_MASQUERADE=""
  OPT_HY2_RENEW_CERT=0
  OPT_HY2_CERT_HOOK=""
  OPT_HY2_ACME_DOMAIN=""
  OPT_HY2_ACME_EMAIL=""
  OPT_HY2_ACME_AGREE_TOS=0
  OPT_HY2_HOP_PORTS=""
  OPT_HY2_HOP_INTERVAL=""
  OPT_BLOCK_BT=""
  OPT_ALLOW_PRIVATE=""
  OPT_TCP_KEEPALIVE_IDLE=""
  OPT_TCP_KEEPALIVE_INTERVAL=""
  OPT_TCP_USER_TIMEOUT=""
  OPT_RESET_SOCKOPT=0
  OPT_CORE_VERSION=""
  OPT_NO_FIREWALL=0
  OPT_OVERWRITE_CONFIG=0
  OPT_FORMAT=""
  OPT_QR=0
  OPT_PURGE=0
  # shellcheck disable=SC2034  # consumed by parse_args, read by tb_init_lang
  OPT_LANG=""
  OPT_YES=0
}

parse_args() {
  local arg var
  while (($# > 0)); do
    arg="$1"
    shift
    # --option=value -> --option value
    if [[ "$arg" == --*=* ]]; then
      set -- "${arg#*=}" "$@"
      arg="${arg%%=*}"
    fi

    var=""
    case "$arg" in
      --core) var=OPT_CORE ;;
      --protocols | --protocol) var=OPT_PROTOCOLS ;;
      --server-addr) var=OPT_SERVER_ADDR ;;
      --name) var=OPT_NAME ;;
      --listen) var=OPT_LISTEN ;;
      --vless-port) var=OPT_VLESS_PORT ;;
      --reality-sni) var=OPT_REALITY_SNI ;;
      --reality-target) var=OPT_REALITY_TARGET ;;
      --ss-port) var=OPT_SS_PORT ;;
      --ss-method) var=OPT_SS_METHOD ;;
      --ss-network) var=OPT_SS_NETWORK ;;
      --hy2-port) var=OPT_HY2_PORT ;;
      --hy2-sni) var=OPT_HY2_SNI ;;
      --hy2-tls) var=OPT_HY2_TLS ;;
      --hy2-cert) var=OPT_HY2_CERT ;;
      --hy2-key) var=OPT_HY2_KEY ;;
      --hy2-obfs) var=OPT_HY2_OBFS ;;
      --hy2-masquerade) var=OPT_HY2_MASQUERADE ;;
      --hy2-cert-hook) var=OPT_HY2_CERT_HOOK ;;
      --hy2-acme-domain) var=OPT_HY2_ACME_DOMAIN ;;
      --hy2-acme-email) var=OPT_HY2_ACME_EMAIL ;;
      --hy2-hop-ports) var=OPT_HY2_HOP_PORTS ;;
      --hy2-hop-interval) var=OPT_HY2_HOP_INTERVAL ;;
      --tcp-keepalive-idle) var=OPT_TCP_KEEPALIVE_IDLE ;;
      --tcp-keepalive-interval) var=OPT_TCP_KEEPALIVE_INTERVAL ;;
      --tcp-user-timeout) var=OPT_TCP_USER_TIMEOUT ;;
      --core-version) var=OPT_CORE_VERSION ;;
      --format) var=OPT_FORMAT ;;
      # Already handled by tb_init_lang; parsed here only to consume it.
      --lang) var=OPT_LANG ;;
    esac
    if [[ -n "$var" ]]; then
      (($# > 0)) || die err_missing_value "$arg"
      if [[ -z "$1" ]] && [[ "$var" == OPT_TCP_* || "$var" == OPT_HY2_* ]]; then
        die err_invalid_option "$arg" "$1"
      fi
      printf -v "$var" '%s' "$1"
      shift
      continue
    fi

    case "$arg" in
      install | show | update | rotate | refresh-cert | uninstall | menu | help | version)
        [[ -z "$OPT_COMMAND" ]] || die err_unknown_arg "$arg"
        OPT_COMMAND="$arg"
        ;;
      -h | --help) OPT_COMMAND="help" ;;
      -V | --version) OPT_COMMAND="version" ;;
      -y | --yes) OPT_YES=1 ;;
      --skip-target-check) OPT_SKIP_TARGET_CHECK=1 ;;
      --hy2-renew-cert) OPT_HY2_RENEW_CERT=1 ;;
      --hy2-acme-agree-tos) OPT_HY2_ACME_AGREE_TOS=1 ;;
      --block-bt) OPT_BLOCK_BT=1 ;;
      --no-block-bt) OPT_BLOCK_BT=0 ;;
      --allow-private) OPT_ALLOW_PRIVATE=1 ;;
      --no-allow-private) OPT_ALLOW_PRIVATE=0 ;;
      --reset-sockopt) OPT_RESET_SOCKOPT=1 ;;
      --no-firewall) OPT_NO_FIREWALL=1 ;;
      --overwrite-config) OPT_OVERWRITE_CONFIG=1 ;;
      --qr) OPT_QR=1 ;;
      --purge) OPT_PURGE=1 ;;
      *) die err_unknown_arg "$arg" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Normalizers: print the canonical form of a value, fail when it is invalid.
# They double as validators for both flags and interactive answers.
# ---------------------------------------------------------------------------

norm_core() {
  case "$1" in
    1 | xray | Xray) printf 'xray' ;;
    2 | sing-box | singbox) printf 'sing-box' ;;
    *) return 1 ;;
  esac
}

PARSED_VLESS=0
PARSED_SS=0
PARSED_HY2=0

# parse_protocols "vless,ss,hy2": result in PARSED_VLESS / PARSED_SS / PARSED_HY2.
parse_protocols() {
  local item
  local -a items=()
  PARSED_VLESS=0
  PARSED_SS=0
  PARSED_HY2=0
  IFS=',+ ' read -r -a items <<<"$1"
  ((${#items[@]} > 0)) || return 1
  for item in "${items[@]}"; do
    case "$item" in
      1 | both) PARSED_VLESS=1 PARSED_SS=1 ;;
      2 | vless | reality | vless-reality) PARSED_VLESS=1 ;;
      3 | ss | ss2022 | shadowsocks | shadowsocks-2022) PARSED_SS=1 ;;
      4 | hy2 | hysteria2 | hysteria) PARSED_HY2=1 ;;
      5 | all) PARSED_VLESS=1 PARSED_SS=1 PARSED_HY2=1 ;;
      *) return 1 ;;
    esac
  done
}

norm_protocols() {
  local -a protos=()
  parse_protocols "$1" || return 1
  [[ "$PARSED_VLESS" == "1" ]] && protos+=(vless)
  [[ "$PARSED_SS" == "1" ]] && protos+=(ss)
  [[ "$PARSED_HY2" == "1" ]] && protos+=(hy2)
  join_by , "${protos[@]}"
}

norm_port() {
  valid_port "$1" && printf '%d' "$((10#$1))"
}

# Bound the string length before arithmetic to avoid overflow. Keepalive
# seconds are limited by Linux; TCP_USER_TIMEOUT must fit Xray's int32.
norm_socket_int() {
  local value="$1" max="$2"
  [[ "$value" =~ ^[0-9]+$ && ${#value} -le 10 ]] || return 1
  value="$((10#$value))"
  ((value <= max)) && printf '%d' "$value"
}

norm_tcp_keepalive() { norm_socket_int "$1" 32767; }
norm_tcp_user_timeout() { norm_socket_int "$1" 2147483647; }

norm_domain() {
  valid_domain "$1" && printf '%s' "${1,,}"
}

norm_host() {
  local host="$1"
  host="${host#[}"
  host="${host%]}"
  valid_host "$host" && printf '%s' "$host"
}

norm_host_port() {
  valid_host_port "$1" && printf '%s' "$1"
}

norm_listen() {
  local addr="$1"
  addr="${addr#[}"
  addr="${addr%]}"
  { valid_ipv4 "$addr" || valid_ipv6 "$addr" || [[ "$addr" == "::" ]]; } && printf '%s' "$addr"
}

norm_ss_method() {
  case "$1" in
    1) printf '%s' "${TB_SS_METHODS[0]}" ;;
    2) printf '%s' "${TB_SS_METHODS[1]}" ;;
    3) printf '%s' "${TB_SS_METHODS[2]}" ;;
    *) valid_ss_method "$1" && printf '%s' "$1" ;;
  esac
}

norm_ss_network() {
  case "$1" in
    both | tcp,udp | udp,tcp | all) printf 'both' ;;
    tcp | udp) printf '%s' "$1" ;;
    *) return 1 ;;
  esac
}

norm_format() {
  case "$1" in
    text | json | links | xray) printf '%s' "$1" ;;
    sing-box | singbox) printf 'sing-box' ;;
    hysteria2 | hy2) printf 'hysteria2' ;;
    *) return 1 ;;
  esac
}

norm_hy2_sni() {
  local host="${1#[}"
  host="${host%]}"
  if valid_domain "$host"; then
    printf '%s' "${host,,}"
  elif valid_ipv4 "$host" || valid_ipv6 "$host"; then
    printf '%s' "$host"
  else
    return 1
  fi
}

norm_hy2_tls() {
  case "$1" in
    1 | self-signed | selfsigned) printf 'self-signed' ;;
    2 | files | file | import) printf 'files' ;;
    3 | acme | certbot | letsencrypt) printf 'acme' ;;
    *) return 1 ;;
  esac
}

norm_email() {
  local email="$1"
  [[ -n "$email" && ${#email} -le 254 && "$email" != *[[:space:]]* &&
    "$email" =~ ^[^@]+@[^.@]+\.[^@]+$ && "$email" != *..* ]] && printf '%s' "$email"
}

norm_hy2_obfs() {
  case "$1" in
    1 | none | off) printf 'none' ;;
    2 | salamander) printf 'salamander' ;;
    *) return 1 ;;
  esac
}

norm_hy2_masquerade() {
  case "$1" in
    none | off) printf 'none' ;;
    *) valid_http_url "$1" && printf '%s' "$1" ;;
  esac
}

norm_hy2_cert_hook() {
  case "$1" in
    certbot) printf 'certbot' ;;
    none | off) printf 'none' ;;
    *) return 1 ;;
  esac
}

norm_readable_file() {
  [[ -f "$1" && -r "$1" ]] && printf '%s' "$1"
}

norm_version() {
  [[ "$1" =~ ^v?[0-9]+(\.[0-9]+){1,2}([-~][0-9A-Za-z.]+)?$ ]] && printf '%s' "${1#v}"
}

norm_name() {
  [[ -n "$1" && ${#1} -le 64 && "$1" != *$'\n'* ]] && printf '%s' "$1"
}

# normalize_opt VAR NORMALIZER FLAG: canonicalizes a flag value in place.
normalize_opt() {
  local var="$1" normalizer="$2" flag="$3" value
  [[ -n "${!var}" ]] || return 0
  value="$("$normalizer" "${!var}")" || die err_invalid_option "$flag" "${!var}"
  printf -v "$var" '%s' "$value"
}

validate_options() {
  normalize_opt OPT_CORE norm_core --core
  normalize_opt OPT_PROTOCOLS norm_protocols --protocols
  normalize_opt OPT_SERVER_ADDR norm_host --server-addr
  normalize_opt OPT_NAME norm_name --name
  normalize_opt OPT_LISTEN norm_listen --listen
  normalize_opt OPT_VLESS_PORT norm_port --vless-port
  normalize_opt OPT_REALITY_SNI norm_domain --reality-sni
  normalize_opt OPT_REALITY_TARGET norm_host_port --reality-target
  normalize_opt OPT_SS_PORT norm_port --ss-port
  normalize_opt OPT_SS_METHOD norm_ss_method --ss-method
  normalize_opt OPT_SS_NETWORK norm_ss_network --ss-network
  normalize_opt OPT_HY2_PORT norm_port --hy2-port
  normalize_opt OPT_HY2_SNI norm_hy2_sni --hy2-sni
  normalize_opt OPT_HY2_TLS norm_hy2_tls --hy2-tls
  normalize_opt OPT_HY2_OBFS norm_hy2_obfs --hy2-obfs
  normalize_opt OPT_HY2_MASQUERADE norm_hy2_masquerade --hy2-masquerade
  normalize_opt OPT_HY2_CERT_HOOK norm_hy2_cert_hook --hy2-cert-hook
  normalize_opt OPT_HY2_ACME_DOMAIN norm_domain --hy2-acme-domain
  normalize_opt OPT_HY2_ACME_EMAIL norm_email --hy2-acme-email
  normalize_opt OPT_HY2_HOP_PORTS norm_hy2_hop_ports --hy2-hop-ports
  normalize_opt OPT_HY2_HOP_INTERVAL norm_hy2_hop_interval --hy2-hop-interval
  if [[ -n "$OPT_HY2_PORT$OPT_HY2_SNI$OPT_HY2_TLS$OPT_HY2_CERT$OPT_HY2_KEY$OPT_HY2_OBFS$OPT_HY2_MASQUERADE$OPT_HY2_CERT_HOOK$OPT_HY2_ACME_DOMAIN$OPT_HY2_ACME_EMAIL$OPT_HY2_HOP_PORTS$OPT_HY2_HOP_INTERVAL" ||
    "$OPT_HY2_RENEW_CERT" == "1" || "$OPT_HY2_ACME_AGREE_TOS" == "1" ]]; then
    [[ "$OPT_COMMAND" == "install" ]] || die err_hy2_command
  fi
  if [[ "$OPT_HY2_TLS" == "self-signed" && -n "$OPT_HY2_CERT$OPT_HY2_KEY" ]]; then
    die err_hy2_cert_with_self_signed
  fi
  if [[ -n "$OPT_HY2_CERT" && -z "$OPT_HY2_KEY" ]] || [[ -z "$OPT_HY2_CERT" && -n "$OPT_HY2_KEY" ]]; then
    die err_hy2_cert_pair_required
  fi
  if [[ "$OPT_HY2_TLS" == "acme" || -n "$OPT_HY2_ACME_DOMAIN$OPT_HY2_ACME_EMAIL" || "$OPT_HY2_ACME_AGREE_TOS" == "1" ]]; then
    if [[ -n "$OPT_HY2_CERT$OPT_HY2_KEY" ]]; then
      die err_hy2_acme_with_files
    fi
  fi
  if [[ -n "$OPT_HY2_ACME_DOMAIN$OPT_HY2_ACME_EMAIL" || "$OPT_HY2_ACME_AGREE_TOS" == "1" ]]; then
    if [[ -n "$OPT_HY2_TLS" && "$OPT_HY2_TLS" != "acme" ]]; then
      die err_hy2_acme_tls_conflict
    fi
    [[ -n "$OPT_HY2_TLS" ]] || OPT_HY2_TLS="acme"
  fi
  if [[ "$OPT_HY2_RENEW_CERT" == "1" ]] && [[ "$OPT_HY2_TLS" == "files" || "$OPT_HY2_TLS" == "acme" || -n "$OPT_HY2_CERT$OPT_HY2_KEY" ]]; then
    die err_hy2_renew_not_self_signed
  fi
  if [[ "$OPT_HY2_CERT_HOOK" == "certbot" ]] && [[ "$OPT_HY2_TLS" == "self-signed" || "$OPT_HY2_RENEW_CERT" == "1" ]]; then
    die err_hy2_hook_not_self_signed
  fi
  if [[ "$OPT_HY2_TLS" == "acme" && "$OPT_HY2_CERT_HOOK" == "none" ]]; then
    die err_hy2_acme_requires_hook
  fi
  if [[ "$OPT_HY2_HOP_PORTS" == "none" && -n "$OPT_HY2_HOP_INTERVAL" ]]; then
    die err_hy2_hop_interval_requires_ports
  fi
  normalize_opt OPT_TCP_KEEPALIVE_IDLE norm_tcp_keepalive --tcp-keepalive-idle
  normalize_opt OPT_TCP_KEEPALIVE_INTERVAL norm_tcp_keepalive --tcp-keepalive-interval
  normalize_opt OPT_TCP_USER_TIMEOUT norm_tcp_user_timeout --tcp-user-timeout
  if [[ -n "$OPT_TCP_KEEPALIVE_IDLE$OPT_TCP_KEEPALIVE_INTERVAL$OPT_TCP_USER_TIMEOUT" || "$OPT_RESET_SOCKOPT" == "1" ]]; then
    [[ "$OPT_COMMAND" == "install" ]] || die err_sockopt_command
  fi
  normalize_opt OPT_CORE_VERSION norm_version --core-version
  normalize_opt OPT_FORMAT norm_format --format
  if [[ "$OPT_COMMAND" == "refresh-cert" ]]; then
    if [[ -n "$OPT_CORE$OPT_PROTOCOLS$OPT_SERVER_ADDR$OPT_NAME$OPT_LISTEN$OPT_VLESS_PORT$OPT_REALITY_SNI$OPT_REALITY_TARGET$OPT_SS_PORT$OPT_SS_METHOD$OPT_SS_NETWORK$OPT_BLOCK_BT$OPT_ALLOW_PRIVATE$OPT_CORE_VERSION$OPT_FORMAT" ||
      "$OPT_SKIP_TARGET_CHECK" == "1" || "$OPT_NO_FIREWALL" == "1" ||
      "$OPT_OVERWRITE_CONFIG" == "1" || "$OPT_QR" == "1" || "$OPT_PURGE" == "1" ]]; then
      die err_refresh_options
    fi
  fi
}

# ask_valid VAR DEFAULT NORMALIZER MSG_KEY [ARGS...]
# Prompts until NORMALIZER accepts the answer. Without a terminal the
# default is used as-is and must already be valid.
ask_valid() {
  local var="$1" default="$2" normalizer="$3" reply value
  shift 3
  while :; do
    reply="$(ask "$default" "$@")"
    if value="$("$normalizer" "$reply")"; then
      printf -v "$var" '%s' "$value"
      return 0
    fi
    [[ "$TB_INTERACTIVE" == "1" ]] || die err_invalid_value "$reply"
    log_warn warn_invalid_input "$reply"
  done
}

# ---------------------------------------------------------------------------
# Parameter resolution for `install`
# Precedence: command line flag > interactive answer > saved state > default.
# ---------------------------------------------------------------------------

resolve_core() {
  if [[ -n "$OPT_CORE" ]]; then
    CFG_CORE="$OPT_CORE"
  else
    ask_valid CFG_CORE "${CFG_CORE:-xray}" norm_core prompt_core
  fi
  check_requested_core_version "$CFG_CORE"
}

resolve_protocols() {
  local current="vless,ss" chosen
  local -a active=()
  if [[ "$TB_HAS_STATE" == "1" ]]; then
    [[ "$CFG_VLESS" == "1" ]] && active+=(vless)
    [[ "$CFG_SS" == "1" ]] && active+=(ss)
    [[ "$CFG_HY2" == "1" ]] && active+=(hy2)
    ((${#active[@]} > 0)) && current="$(join_by , "${active[@]}")"
  fi
  if [[ -n "$OPT_PROTOCOLS" ]]; then
    chosen="$OPT_PROTOCOLS"
  else
    ask_valid chosen "$current" norm_protocols prompt_protocols
  fi
  parse_protocols "$chosen"
  CFG_VLESS="$PARSED_VLESS"
  CFG_SS="$PARSED_SS"
  CFG_HY2="$PARSED_HY2"
}

resolve_server_addr() {
  local default="$CFG_SERVER_ADDR"
  if [[ -n "$OPT_SERVER_ADDR" ]]; then
    CFG_SERVER_ADDR="$OPT_SERVER_ADDR"
    return 0
  fi
  if [[ -z "$default" ]]; then
    log_info info_detect_addr
    default="$(detect_server_addr || true)"
  fi
  if [[ "$TB_INTERACTIVE" != "1" && -z "$default" ]]; then
    die err_server_addr_required
  fi
  ask_valid CFG_SERVER_ADDR "$default" norm_host prompt_server_addr
}

# Runs the target probe and reports the outcome. Returns 0 when the target
# is fine or the user decided to keep it.
accept_reality_target() {
  local sni="$1" target="$2" rc=0
  if [[ "$OPT_SKIP_TARGET_CHECK" == "1" ]]; then
    return 0
  fi
  log_info info_probing_target "$target" "$sni"
  probe_reality_target "$sni" "$target" || rc=$?
  case "$rc" in
    0)
      [[ "$TB_TARGET_H2" == "1" ]] || log_warn warn_target_no_h2 "$target"
      log_ok ok_target "$target"
      return 0
      ;;
    1) log_err err_target_unreachable "$target" ;;
    2) log_err err_target_no_tls13 "$target" ;;
    *) log_err err_target_cert "$target" "$sni" ;;
  esac
  # --yes must not wave a broken target through: that needs the explicit
  # --skip-target-check.
  [[ "$TB_INTERACTIVE" == "1" ]] && confirm n prompt_target_anyway
}

resolve_vless() {
  local sni target old_sni="$CFG_REALITY_SNI" old_target="$CFG_REALITY_TARGET"

  if [[ -n "$OPT_VLESS_PORT" ]]; then
    CFG_VLESS_PORT="$OPT_VLESS_PORT"
  else
    ask_valid CFG_VLESS_PORT "${CFG_VLESS_PORT:-443}" norm_port prompt_vless_port
  fi

  if [[ "$TB_INTERACTIVE" == "1" && -z "$OPT_REALITY_SNI" ]]; then
    printf '%s\n' "$(msg help_reality_sni)" >&2
  fi
  while :; do
    if [[ -n "$OPT_REALITY_SNI" ]]; then
      sni="$OPT_REALITY_SNI"
    else
      [[ "$TB_INTERACTIVE" == "1" || -n "$old_sni" ]] || die err_sni_required
      ask_valid sni "$old_sni" norm_domain prompt_reality_sni
    fi

    if [[ -n "$OPT_REALITY_TARGET" ]]; then
      target="$OPT_REALITY_TARGET"
    elif [[ "$sni" == "$old_sni" && -n "$old_target" ]]; then
      target="$old_target"
    else
      target="$sni:443"
    fi

    if accept_reality_target "$sni" "$target"; then
      break
    fi
    # Only an interactively typed name can be corrected by asking again.
    [[ "$TB_INTERACTIVE" == "1" && -z "$OPT_REALITY_SNI" ]] || die err_target_rejected
  done
  CFG_REALITY_SNI="$sni"
  CFG_REALITY_TARGET="$target"
}

resolve_ss() {
  local default_port="$CFG_SS_PORT"
  if [[ -n "$OPT_SS_PORT" ]]; then
    CFG_SS_PORT="$OPT_SS_PORT"
  else
    if [[ -z "$default_port" ]]; then
      for _ in 1 2 3 4 5; do
        default_port="$(random_free_port)" || die err_no_free_port
        if [[ "$default_port" != "$CFG_VLESS_PORT" && "$default_port" != "$CFG_HY2_PORT" ]] &&
          ! { [[ "$CFG_SS_NETWORK" != "tcp" ]] && hy2_hop_contains_port "$CFG_HY2_HOP_PORTS" "$default_port"; }; then
          break
        fi
        default_port=""
      done
      [[ -n "$default_port" ]] || die err_no_free_port
    fi
    ask_valid CFG_SS_PORT "$default_port" norm_port prompt_ss_port
  fi

  if [[ -n "$OPT_SS_METHOD" ]]; then
    CFG_SS_METHOD="$OPT_SS_METHOD"
  else
    ask_valid CFG_SS_METHOD "${CFG_SS_METHOD:-${TB_SS_METHODS[0]}}" norm_ss_method prompt_ss_method
  fi

  if [[ -n "$OPT_SS_NETWORK" ]]; then
    CFG_SS_NETWORK="$OPT_SS_NETWORK"
  elif [[ -z "$CFG_SS_NETWORK" ]]; then
    CFG_SS_NETWORK="both"
  fi
}

resolve_hy2() {
  local prev_tls="$CFG_HY2_TLS" cert_file="" key_file="" detected_sni="" verify_name=""
  local abs_cert="" abs_key="" acme_domain="" default_acme_domain="" acme_email="" acme_lineage=""

  TB_HY2_ACME_NEED_ISSUE=0
  TB_HY2_ACME_DOMAIN=""
  TB_HY2_ACME_EMAIL=""
  TB_HY2_ACME_LINEAGE=""

  if [[ -n "$OPT_HY2_PORT" ]]; then
    CFG_HY2_PORT="$OPT_HY2_PORT"
  else
    ask_valid CFG_HY2_PORT "${CFG_HY2_PORT:-443}" norm_port prompt_hy2_port
  fi

  if [[ -n "$OPT_HY2_TLS" ]]; then
    CFG_HY2_TLS="$OPT_HY2_TLS"
  elif [[ -n "$OPT_HY2_CERT" ]]; then
    CFG_HY2_TLS="files"
  else
    ask_valid CFG_HY2_TLS "${CFG_HY2_TLS:-self-signed}" norm_hy2_tls prompt_hy2_tls
  fi

  if [[ "$OPT_HY2_RENEW_CERT" == "1" && "$CFG_HY2_TLS" != "self-signed" ]]; then
    die err_hy2_renew_not_self_signed
  fi
  if [[ "$OPT_HY2_CERT_HOOK" == "certbot" && "$CFG_HY2_TLS" != "files" && "$CFG_HY2_TLS" != "acme" ]]; then
    die err_hy2_hook_not_self_signed
  fi

  if [[ "$CFG_HY2_TLS" == "acme" ]]; then
    if [[ -n "$OPT_HY2_ACME_DOMAIN" ]]; then
      acme_domain="$OPT_HY2_ACME_DOMAIN"
    elif [[ -n "$OPT_HY2_SNI" ]] && valid_domain "$OPT_HY2_SNI"; then
      acme_domain="$OPT_HY2_SNI"
    elif [[ -n "$CFG_HY2_ACME_DOMAIN" ]]; then
      acme_domain="$CFG_HY2_ACME_DOMAIN"
    elif valid_domain "$CFG_SERVER_ADDR"; then
      acme_domain="$CFG_SERVER_ADDR"
    fi

    if [[ -z "$acme_domain" ]]; then
      if [[ "$TB_INTERACTIVE" == "1" ]]; then
        if valid_domain "$CFG_HY2_SNI"; then
          default_acme_domain="$CFG_HY2_SNI"
        fi
        ask_valid acme_domain "$default_acme_domain" norm_domain prompt_hy2_acme_domain
      else
        die err_hy2_acme_domain_required
      fi
    fi

    verify_name="${OPT_HY2_SNI:-$acme_domain}"
    CFG_HY2_SNI="$verify_name"
    acme_lineage="$(acme_lineage_for_domain "$acme_domain")"
    cert_file="$(acme_live_cert_path "$acme_lineage")"
    key_file="$(acme_live_key_path "$acme_lineage")"

    if acme_reusable_pair "$acme_domain" "$cert_file" "$key_file"; then
      acme_email="${OPT_HY2_ACME_EMAIL:-$CFG_HY2_ACME_EMAIL}"
      acme_import_live_pair "$acme_domain" "$acme_email" "$acme_lineage" "$verify_name"
      log_info info_hy2_acme_reuse_cert "$acme_domain" "$cert_file"
    else
      if [[ -n "$OPT_HY2_ACME_EMAIL" ]]; then
        acme_email="$OPT_HY2_ACME_EMAIL"
      elif [[ -n "$CFG_HY2_ACME_EMAIL" ]]; then
        acme_email="$CFG_HY2_ACME_EMAIL"
      elif [[ "$TB_INTERACTIVE" == "1" ]]; then
        ask_valid acme_email "" norm_email prompt_hy2_acme_email
      else
        die err_hy2_acme_email_required
      fi

      if [[ "$OPT_HY2_ACME_AGREE_TOS" != "1" ]]; then
        if [[ "$TB_INTERACTIVE" == "1" ]]; then
          confirm n prompt_hy2_acme_tos || die err_hy2_acme_tos_required
          OPT_HY2_ACME_AGREE_TOS=1
        else
          die err_hy2_acme_tos_required
        fi
      fi

      TB_HY2_ACME_NEED_ISSUE=1
      TB_HY2_ACME_DOMAIN="$acme_domain"
      TB_HY2_ACME_EMAIL="$acme_email"
      TB_HY2_ACME_LINEAGE="$acme_lineage"
      CFG_HY2_CERTBOT_HOOK=1
    fi
  elif [[ "$CFG_HY2_TLS" == "files" ]]; then
    if [[ -n "$OPT_HY2_CERT" ]]; then
      cert_file="$OPT_HY2_CERT"
      key_file="$OPT_HY2_KEY"
      CFG_HY2_ACME=0
      CFG_HY2_ACME_DOMAIN=""
      CFG_HY2_ACME_EMAIL=""
      CFG_HY2_ACME_LINEAGE=""
    elif [[ "$prev_tls" != "files" || -z "$CFG_HY2_CERT" || -z "$CFG_HY2_KEY" ]]; then
      if [[ "$TB_INTERACTIVE" == "1" ]]; then
        ask_valid cert_file "" norm_readable_file prompt_hy2_cert
        ask_valid key_file "" norm_readable_file prompt_hy2_key
        CFG_HY2_ACME=0
        CFG_HY2_ACME_DOMAIN=""
        CFG_HY2_ACME_EMAIL=""
        CFG_HY2_ACME_LINEAGE=""
      else
        die err_hy2_files_required
      fi
    fi

    if [[ -n "$cert_file" ]]; then
      tls_validate_pair_files "$cert_file" "$key_file" || die err_hy2_cert_pair "$cert_file" "$key_file"
      abs_cert="$(tls_abs_path "$cert_file")" || die err_hy2_cert_pair "$cert_file" "$key_file"
      abs_key="$(tls_abs_path "$key_file")" || die err_hy2_cert_pair "$cert_file" "$key_file"
      if [[ -n "$OPT_HY2_SNI" ]]; then
        CFG_HY2_SNI="$OPT_HY2_SNI"
      elif [[ -z "$CFG_HY2_SNI" || "$prev_tls" != "files" ]]; then
        if valid_domain "$CFG_SERVER_ADDR" && tls_cert_matches_name "$cert_file" "$CFG_SERVER_ADDR"; then
          CFG_HY2_SNI="$CFG_SERVER_ADDR"
        else
          detected_sni="$(tls_cert_first_dns_name "$cert_file" || true)"
          if [[ "$TB_INTERACTIVE" == "1" ]]; then
            ask_valid CFG_HY2_SNI "$detected_sni" norm_hy2_sni prompt_hy2_sni
          elif [[ -n "$detected_sni" ]]; then
            CFG_HY2_SNI="$detected_sni"
          elif tls_cert_matches_name "$cert_file" "$CFG_SERVER_ADDR"; then
            CFG_HY2_SNI=""
          else
            die err_hy2_sni_required
          fi
        fi
      fi
      verify_name="${CFG_HY2_SNI:-$CFG_SERVER_ADDR}"
      tls_cert_matches_name "$cert_file" "$verify_name" || die err_hy2_cert_sni_mismatch "$verify_name"
      CFG_HY2_CERT="$TLS_CERT_PEM"
      CFG_HY2_KEY="$TLS_KEY_PEM"
      CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"
      CFG_HY2_CERT_FILE="$abs_cert"
      CFG_HY2_KEY_FILE="$abs_key"
    else
      [[ -n "$OPT_HY2_SNI" ]] && CFG_HY2_SNI="$OPT_HY2_SNI"
      verify_name="${CFG_HY2_SNI:-$CFG_SERVER_ADDR}"
      tls_validate_pem_pair "$CFG_HY2_CERT" "$CFG_HY2_KEY" || die err_hy2_tls_invalid
      CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"
      tls_pem_matches_name "$CFG_HY2_CERT" "$verify_name" || die err_hy2_cert_sni_mismatch "$verify_name"
    fi

    case "$OPT_HY2_CERT_HOOK" in
      certbot) CFG_HY2_CERTBOT_HOOK=1 ;;
      none) CFG_HY2_CERTBOT_HOOK=0 ;;
    esac
    if [[ "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
      if [[ -z "$CFG_HY2_CERT_FILE" || -z "$CFG_HY2_KEY_FILE" ]]; then
        die err_hy2_cert_sources_missing
      fi
      certbot_lineage_from_pair "$CFG_HY2_CERT_FILE" "$CFG_HY2_KEY_FILE" >/dev/null ||
        die err_hy2_hook_certbot_paths "$(certbot_live_root)"
    fi
  else
    CFG_HY2_CERT_FILE=""
    CFG_HY2_KEY_FILE=""
    CFG_HY2_CERTBOT_HOOK=0
    CFG_HY2_ACME=0
    CFG_HY2_ACME_DOMAIN=""
    CFG_HY2_ACME_EMAIL=""
    CFG_HY2_ACME_LINEAGE=""
    if [[ -n "$OPT_HY2_SNI" ]]; then
      CFG_HY2_SNI="$OPT_HY2_SNI"
    elif [[ "$prev_tls" == "files" && "$CFG_HY2_SNI" != "$CFG_SERVER_ADDR" ]]; then
      CFG_HY2_SNI=""
    fi
    if [[ -z "$CFG_HY2_SNI" ]] && valid_domain "$CFG_SERVER_ADDR"; then
      CFG_HY2_SNI="$CFG_SERVER_ADDR"
    fi
    if [[ "$prev_tls" != "self-signed" || "$OPT_HY2_RENEW_CERT" == "1" ]]; then
      CFG_HY2_CERT=""
      CFG_HY2_KEY=""
      CFG_HY2_CERT_SHA256=""
    elif [[ -n "$CFG_HY2_CERT" ]]; then
      if ! tls_pem_matches_name "$CFG_HY2_CERT" "$CFG_SERVER_ADDR" ||
        { [[ -n "$CFG_HY2_SNI" ]] && ! tls_pem_matches_name "$CFG_HY2_CERT" "$CFG_HY2_SNI"; }; then
        CFG_HY2_CERT=""
        CFG_HY2_KEY=""
        CFG_HY2_CERT_SHA256=""
      fi
    fi
  fi

  if [[ -n "$OPT_HY2_OBFS" ]]; then
    CFG_HY2_OBFS="$OPT_HY2_OBFS"
  else
    ask_valid CFG_HY2_OBFS "${CFG_HY2_OBFS:-none}" norm_hy2_obfs prompt_hy2_obfs
  fi
  if [[ "$CFG_HY2_OBFS" != "salamander" ]]; then
    CFG_HY2_OBFS_PASSWORD=""
  fi

  if [[ "$OPT_HY2_MASQUERADE" == "none" ]]; then
    CFG_HY2_MASQUERADE=""
  elif [[ -n "$OPT_HY2_MASQUERADE" ]]; then
    CFG_HY2_MASQUERADE="$OPT_HY2_MASQUERADE"
  fi

  if [[ "$OPT_HY2_HOP_PORTS" == "none" ]]; then
    CFG_HY2_HOP_PORTS=""
    CFG_HY2_HOP_INTERVAL_MIN=30
    CFG_HY2_HOP_INTERVAL_MAX=30
  elif [[ -n "$OPT_HY2_HOP_PORTS" ]]; then
    CFG_HY2_HOP_PORTS="$OPT_HY2_HOP_PORTS"
  fi

  if [[ -n "$OPT_HY2_HOP_INTERVAL" ]]; then
    [[ -n "$CFG_HY2_HOP_PORTS" ]] || die err_hy2_hop_interval_requires_ports
    hy2_hop_parse_interval "$OPT_HY2_HOP_INTERVAL"
    CFG_HY2_HOP_INTERVAL_MIN="$PARSED_HOP_MIN"
    CFG_HY2_HOP_INTERVAL_MAX="$PARSED_HOP_MAX"
  fi
}

resolve_sockopt() {
  local key var value
  # Reset first, then apply explicitly supplied overrides, regardless of
  # argument order. Unspecified fields otherwise keep their saved value.
  [[ "$OPT_RESET_SOCKOPT" == "1" ]] && CFG_SOCKOPT='{}'
  for key in tcpKeepAliveIdle tcpKeepAliveInterval tcpUserTimeout; do
    case "$key" in
      tcpKeepAliveIdle) var=OPT_TCP_KEEPALIVE_IDLE ;;
      tcpKeepAliveInterval) var=OPT_TCP_KEEPALIVE_INTERVAL ;;
      tcpUserTimeout) var=OPT_TCP_USER_TIMEOUT ;;
    esac
    value="${!var}"
    [[ -n "$value" ]] || continue
    CFG_SOCKOPT="$(jq -c --arg key "$key" --argjson value "$value" '
      if $value == 0 then del(.[$key]) else .[$key] = $value end
    ' <<<"$CFG_SOCKOPT")" || die err_render
  done
  check_sockopt_support "$CFG_CORE"
}

resolve_params() {
  resolve_core
  resolve_sockopt
  resolve_protocols
  resolve_server_addr

  [[ -n "$OPT_NAME" ]] && CFG_NODE_NAME="$OPT_NAME"
  [[ -n "$CFG_NODE_NAME" ]] || CFG_NODE_NAME="ToastBox"
  [[ -n "$OPT_LISTEN" ]] && CFG_LISTEN="$OPT_LISTEN"
  [[ -n "$OPT_BLOCK_BT" ]] && CFG_BLOCK_BT="$OPT_BLOCK_BT"
  [[ -n "$OPT_ALLOW_PRIVATE" ]] && CFG_ALLOW_PRIVATE="$OPT_ALLOW_PRIVATE"

  if [[ "$CFG_VLESS" == "1" ]]; then resolve_vless; fi
  if [[ "$CFG_HY2" == "1" ]]; then
    resolve_hy2
  else
    if [[ -n "$OPT_HY2_PORT$OPT_HY2_SNI$OPT_HY2_TLS$OPT_HY2_CERT$OPT_HY2_KEY$OPT_HY2_OBFS$OPT_HY2_MASQUERADE$OPT_HY2_CERT_HOOK$OPT_HY2_ACME_DOMAIN$OPT_HY2_ACME_EMAIL$OPT_HY2_HOP_PORTS$OPT_HY2_HOP_INTERVAL" ||
      "$OPT_HY2_RENEW_CERT" == "1" || "$OPT_HY2_ACME_AGREE_TOS" == "1" ]]; then
      die err_hy2_not_enabled
    fi
    CFG_HY2_CERT_FILE=""
    CFG_HY2_KEY_FILE=""
    CFG_HY2_CERTBOT_HOOK=0
    CFG_HY2_ACME=0
    CFG_HY2_ACME_DOMAIN=""
    CFG_HY2_ACME_EMAIL=""
    CFG_HY2_ACME_LINEAGE=""
    CFG_HY2_HOP_PORTS=""
    CFG_HY2_HOP_INTERVAL_MIN=30
    CFG_HY2_HOP_INTERVAL_MAX=30
  fi
  if [[ "$CFG_SS" == "1" ]]; then resolve_ss; fi

  if [[ "$CFG_VLESS" == "1" && "$CFG_SS" == "1" &&
    "$CFG_VLESS_PORT" == "$CFG_SS_PORT" && "$CFG_SS_NETWORK" != "udp" ]]; then
    die err_port_same "$CFG_VLESS_PORT"
  fi
  if [[ "$CFG_HY2" == "1" && "$CFG_SS" == "1" &&
    "$CFG_HY2_PORT" == "$CFG_SS_PORT" && "$CFG_SS_NETWORK" != "tcp" ]]; then
    die err_port_same_udp "$CFG_HY2_PORT"
  fi
  if [[ "$CFG_HY2" == "1" && -n "$CFG_HY2_HOP_PORTS" &&
    "$CFG_SS" == "1" && "$CFG_SS_NETWORK" != "tcp" ]] &&
    hy2_hop_contains_port "$CFG_HY2_HOP_PORTS" "$CFG_SS_PORT"; then
    die err_hy2_hop_ss_conflict "$CFG_SS_PORT" "$CFG_HY2_HOP_PORTS"
  fi
  if [[ "$CFG_HY2" == "1" && ("$TB_HY2_ACME_NEED_ISSUE" == "1" || ("$CFG_HY2_ACME" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1")) ]]; then
    if [[ "$CFG_VLESS" == "1" && "$CFG_VLESS_PORT" == "80" ]] ||
      { [[ "$CFG_SS" == "1" && "$CFG_SS_PORT" == "80" && "$CFG_SS_NETWORK" != "udp" ]]; }; then
      die err_hy2_acme_port80_conflict
    fi
  fi
  return 0
}

print_plan() {
  local interval_label="" hook_cert_label=""
  printf '\n%s\n' "$(msg plan_title)" >&2
  printf '  %s: %s\n' "$(msg label_core)" "$CFG_CORE" >&2
  printf '  %s: %s\n' "$(msg label_server)" "$CFG_SERVER_ADDR" >&2
  if [[ "$CFG_SOCKOPT" != '{}' ]]; then
    printf '  %s: %s\n' "$(msg label_sockopt)" "$CFG_SOCKOPT" >&2
  fi
  if [[ "$CFG_VLESS" == "1" ]]; then
    printf '  VLESS-REALITY-Vision: %s/tcp, SNI %s, %s %s\n' \
      "$CFG_VLESS_PORT" "$CFG_REALITY_SNI" "$(msg label_target)" "$CFG_REALITY_TARGET" >&2
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    printf '  Shadowsocks 2022: %s (%s), %s\n' \
      "$CFG_SS_PORT" "$CFG_SS_NETWORK" "$CFG_SS_METHOD" >&2
  fi
  if [[ "$CFG_HY2" == "1" ]]; then
    printf '  Hysteria 2: %s/udp, TLS %s, %s %s\n' \
      "$CFG_HY2_PORT" "$CFG_HY2_TLS" "$(msg label_obfs)" "$CFG_HY2_OBFS" >&2
    if [[ "$TB_HY2_ACME_NEED_ISSUE" == "1" ]]; then
      printf '  %s: %s (Certbot standalone HTTP-01, 80/tcp)\n' "$(msg label_acme_domain)" "$TB_HY2_ACME_DOMAIN" >&2
      printf '  %s: %s\n' "$(msg label_acme_lineage)" "$TB_HY2_ACME_LINEAGE" >&2
    elif [[ "$CFG_HY2_ACME" == "1" ]]; then
      printf '  %s: %s\n' "$(msg label_acme_domain)" "$CFG_HY2_ACME_DOMAIN" >&2
    fi
    if [[ "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
      hook_cert_label="$CFG_HY2_CERT_FILE"
      if [[ -z "$hook_cert_label" && -n "$TB_HY2_ACME_LINEAGE" ]]; then
        hook_cert_label="$(acme_live_cert_path "$TB_HY2_ACME_LINEAGE")"
      fi
      printf '  %s: certbot (%s)\n' "$(msg label_cert_hook)" "$hook_cert_label" >&2
    fi
    if [[ -n "$CFG_HY2_HOP_PORTS" ]]; then
      interval_label="${CFG_HY2_HOP_INTERVAL_MIN}s"
      if [[ "$CFG_HY2_HOP_INTERVAL_MIN" != "$CFG_HY2_HOP_INTERVAL_MAX" ]]; then
        interval_label="${CFG_HY2_HOP_INTERVAL_MIN}-${CFG_HY2_HOP_INTERVAL_MAX}s"
      fi
      printf '  %s: %s/udp (%s)\n' "$(msg label_hop_ports)" "$CFG_HY2_HOP_PORTS" "$interval_label" >&2
      if [[ "$OPT_NO_FIREWALL" == "1" ]]; then
        printf '  %s\n' "$(msg note_hop_no_firewall)" >&2
      fi
    fi
  fi
  printf '\n' >&2
}

# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

# preflight_ports [EXTRA_PROCESS]: fails when a wanted port is held by
# another program. Our own core is fine, and so is the core that is about
# to be replaced (EXTRA_PROCESS): it is stopped before the new one starts.
preflight_ports() {
  local procs
  local -a own=("$(core_call process)")
  [[ -n "${1:-}" ]] && own+=("$1")
  if [[ "$CFG_VLESS" == "1" ]]; then
    if procs="$(port_conflict tcp "$CFG_VLESS_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_VLESS_PORT/tcp" "$procs"
    fi
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    if [[ "$CFG_SS_NETWORK" != "udp" ]] && procs="$(port_conflict tcp "$CFG_SS_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_SS_PORT/tcp" "$procs"
    fi
    if [[ "$CFG_SS_NETWORK" != "tcp" ]] && procs="$(port_conflict udp "$CFG_SS_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_SS_PORT/udp" "$procs"
    fi
  fi
  if [[ "$CFG_HY2" == "1" ]]; then
    if procs="$(port_conflict udp "$CFG_HY2_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_HY2_PORT/udp" "$procs"
    fi
    if [[ -n "$CFG_HY2_HOP_PORTS" ]] && procs="$(hy2_hop_port_conflicts "$CFG_HY2_HOP_PORTS" "${own[@]}")"; then
      die err_hy2_hop_ports_in_use "$procs"
    fi
  fi
  return 0
}

TB_PREV_CORE_BIN=""
TB_PREV_CORE_ACTIVE=0

check_requested_core_version() {
  local core="$1" min
  [[ -n "$OPT_CORE_VERSION" ]] || return 0
  min="$(core_fn "$core" min_version)"
  if ! ver_ge "$OPT_CORE_VERSION" "$min"; then
    die err_core_version_too_old "$core" "$OPT_CORE_VERSION" "$min"
  fi
}

restore_core_bin() {
  local prev_bin="$1" was_active="$2" svc="$3" tmp
  [[ -n "$prev_bin" && -f "$prev_bin" && "$CFG_CORE" == "xray" ]] || return 0
  tmp="$TB_XRAY_BIN.toastbox-restore"
  if cp -p "$prev_bin" "$tmp" && mv -f "$tmp" "$TB_XRAY_BIN"; then
    log_warn warn_core_rolled_back "$CFG_CORE"
    if [[ "$was_active" == "1" ]]; then
      service_restart_checked "$svc" || true
    fi
  else
    rm -f "$tmp"
  fi
}

# ensure_core [force]: installs the core when it is missing, when a specific
# version was requested or when forced (update), then checks that it is
# recent enough for the configuration we write.
ensure_core() {
  local force="${1:-0}" version min prev_bin="" was_active=0 svc=""
  TB_PREV_CORE_BIN=""
  TB_PREV_CORE_ACTIVE=0
  check_sockopt_support "$CFG_CORE"
  check_requested_core_version "$CFG_CORE"
  min="$(core_call min_version)"
  if [[ "$force" == "1" || -n "$OPT_CORE_VERSION" ]] || ! core_call is_installed; then
    svc="$(core_call service)"
    service_is_active "$svc" && was_active=1
    if [[ "$CFG_CORE" == "xray" && -f "$TB_XRAY_BIN" ]]; then
      prev_bin="$TB_TMP/prev-xray"
      cp -p "$TB_XRAY_BIN" "$prev_bin" || prev_bin=""
    fi
    log_info info_installing_core "$CFG_CORE"
    if ! core_call install "$OPT_CORE_VERSION"; then
      restore_core_bin "$prev_bin" "$was_active" "$svc"
      die err_core_install "$CFG_CORE"
    fi
  fi
  if ! core_call is_installed; then
    restore_core_bin "$prev_bin" "$was_active" "$svc"
    die err_core_install "$CFG_CORE"
  fi
  version="$(core_call version || true)"
  if [[ -z "$version" ]] || ! ver_ge "$version" "$min"; then
    restore_core_bin "$prev_bin" "$was_active" "$svc"
    die err_core_too_old "$CFG_CORE" "${version:-?}" "$min"
  fi
  TB_PREV_CORE_BIN="$prev_bin"
  TB_PREV_CORE_ACTIVE="$was_active"
  log_ok ok_core_ready "$CFG_CORE" "$version"
}

TB_APPLY_BACKUP=""
TB_APPLY_WAS_ACTIVE=0

rollback_applied_config() {
  local old_svc="${1:-}" path svc
  path="$(core_call config_path)"
  svc="$(core_call service)"
  if [[ -n "$TB_APPLY_BACKUP" ]]; then
    if core_call install_config "$TB_APPLY_BACKUP"; then
      log_warn warn_rolled_back "$TB_APPLY_BACKUP"
      if [[ "$TB_APPLY_WAS_ACTIVE" == "1" ]]; then
        service_restart_checked "$svc" || true
      else
        service_stop_disable "$svc"
        log_warn warn_service_stopped "$svc"
      fi
    else
      log_err err_rollback_config "$path" "$TB_APPLY_BACKUP"
      service_stop_disable "$svc"
      log_warn warn_service_stopped "$svc"
    fi
  else
    service_stop_disable "$svc"
    log_warn warn_service_stopped "$svc"
  fi
  if [[ -n "$old_svc" ]]; then
    service_restart_checked "$old_svc" || true
    log_warn warn_old_core_restored "$old_svc"
  fi
}

# apply_config [OLD_SERVICE [ACTIVATION]]: renders, validates, installs and
# activates the configuration. ACTIVATION is "restart" (default) or
# "if-active" (restarts only when the core service was already running).
#
# OLD_SERVICE is the service of a core that is being replaced. It is only
# stopped once the new configuration has passed validation and been written,
# and it is started again if the new core does not come up.
#
# On failure the previous configuration file is restored, but the service
# is only restarted on it if it was running before: a configuration that
# was merely lying around (such as the sample shipped in the sing-box
# package) must never be put into service by a rollback.
apply_config() {
  local old_svc="${1:-}" activation="${2:-restart}"
  local new="$TB_TMP/config.json" path svc backup="" output was_active=0
  TB_APPLY_BACKUP=""
  TB_APPLY_WAS_ACTIVE=0
  path="$(core_call config_path)"
  svc="$(core_call service)"
  check_sockopt_support "$CFG_CORE"

  if ! core_call render >"$new"; then
    log_err err_render
    return 1
  fi
  if ! output="$(core_call validate "$new" 2>&1)"; then
    printf '%s\n' "$output" >&2
    log_err err_validate "$CFG_CORE"
    return 1
  fi

  service_is_active "$svc" && was_active=1
  TB_APPLY_WAS_ACTIVE="$was_active"
  if ! backup="$(backup_file "$path" "$CFG_CORE-config")"; then
    log_err err_backup_config "$path"
    return 1
  fi
  TB_APPLY_BACKUP="$backup"
  if ! core_call install_config "$new"; then
    log_err err_install_config "$path"
    if [[ -n "$backup" ]] && ! cmp -s "$backup" "$path" 2>/dev/null; then
      if core_call install_config "$backup"; then
        log_warn warn_rolled_back "$backup"
      else
        log_err err_rollback_config "$path" "$backup"
      fi
    fi
    return 1
  fi
  if [[ "$activation" == "if-active" && "$was_active" != "1" ]]; then
    log_info info_service_kept_stopped "$svc"
    return 0
  fi
  if [[ -n "$old_svc" ]]; then
    service_stop_disable "$old_svc"
  fi
  log_info info_restarting "$svc"
  if service_restart_checked "$svc"; then
    log_ok ok_service_running "$svc"
    return 0
  fi

  log_err err_service_start "$svc"
  service_show_log "$svc"
  rollback_applied_config "$old_svc"
  return 1
}

sync_firewall() {
  local -a rules=()
  if [[ "$OPT_NO_FIREWALL" == "1" ]]; then
    return 0
  fi
  [[ "$CFG_VLESS" == "1" ]] && rules+=("$CFG_VLESS_PORT/tcp")
  if [[ "$CFG_SS" == "1" ]]; then
    [[ "$CFG_SS_NETWORK" != "udp" ]] && rules+=("$CFG_SS_PORT/tcp")
    [[ "$CFG_SS_NETWORK" != "tcp" ]] && rules+=("$CFG_SS_PORT/udp")
  fi
  [[ "$CFG_HY2" == "1" ]] && rules+=("$CFG_HY2_PORT/udp")
  if [[ "$CFG_HY2" == "1" && "$CFG_HY2_ACME" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
    rules+=("80/tcp")
  fi
  fw_sync "${rules[@]}"
}

post_install_notes() {
  local extra
  extra="$(core_call extra_configs)"
  if [[ -n "$extra" ]]; then
    log_warn warn_extra_configs "$(printf '%s' "$extra" | tr '\n' ' ')"
  fi
  # Shadowsocks 2022 rejects packets whose timestamp is too far off.
  if [[ "$CFG_SS" == "1" ]] && ! clock_synchronized; then
    log_warn warn_clock
  fi
}

require_state() {
  state_load || die err_no_state
}

# Keeps a copy of the single-file release as `toastbox`, so the node can be
# managed later without downloading the script again. Skipped when running
# from the source tree or from a pipe.
self_install() {
  local src="${BASH_SOURCE[0]:-}" dir
  [[ "${TB_BUILT:-0}" == "1" && -f "$src" ]] || return 0
  [[ "$(readlink -f "$src")" != "$(readlink -f "$TB_SELF_PATH")" ]] || return 0
  dir="$(dirname "$TB_SELF_PATH")"
  install -d -m 755 "$dir" || return 1
  install -m 755 "$src" "$TB_SELF_PATH" || return 1
  log_ok ok_self_installed "$TB_SELF_PATH"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_install() {
  local prev_core path old_svc="" old_proc="" compact="" output="" svc=""
  local hop_backup="$TB_TMP/hop-backup" hook_backup="$TB_TMP/hook-backup" acme_backup="$TB_TMP/acme-backup"

  require_root
  detect_os
  require_supported_arch
  require_systemd
  tb_mktemp_dir
  hop_backup="$TB_TMP/hop-backup"
  hook_backup="$TB_TMP/hook-backup"
  acme_backup="$TB_TMP/acme-backup"
  install_deps
  tb_acquire_lock

  state_load || true
  prev_core="$CFG_CORE"

  resolve_params
  if [[ "$TB_INTERACTIVE" == "1" ]]; then
    print_plan
    confirm y prompt_proceed || die err_aborted
  fi

  if [[ -n "$prev_core" && "$prev_core" != "$CFG_CORE" ]]; then
    log_warn warn_core_switch "$prev_core" "$CFG_CORE" "$prev_core"
    old_svc="$(core_fn "$prev_core" service)"
    old_proc="$(core_fn "$prev_core" process)"
  fi

  # A configuration already on disk (from another installer, manual setup, or
  # a previous uninstall without --purge) may be in use or worth preserving.
  # Replacing it takes an explicit answer at the prompt or --overwrite-config;
  # --yes alone is not enough. (A backup is made either way.)
  path="$(core_call config_path)"
  if [[ "$prev_core" != "$CFG_CORE" && -s "$path" && "$OPT_OVERWRITE_CONFIG" != "1" ]]; then
    compact="$(tr -d '[:space:]' <"$path")"
    if [[ -n "$compact" && "$compact" != "{}" ]]; then
      if [[ "$TB_INTERACTIVE" != "1" ]] || ! confirm n prompt_overwrite_config "$path"; then
        die err_foreign_config "$path"
      fi
    fi
  fi

  preflight_ports "$old_proc"
  hy2_hop_preflight
  if [[ "$CFG_HY2" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
    certbot_hook_preflight
  fi
  if [[ "$CFG_HY2" == "1" && "$TB_HY2_ACME_NEED_ISSUE" == "1" ]]; then
    acme_check_dns "$TB_HY2_ACME_DOMAIN" "$CFG_SERVER_ADDR"
    acme_check_port_80
    acme_provision_cert "$TB_HY2_ACME_DOMAIN" "$TB_HY2_ACME_EMAIL" "$TB_HY2_ACME_LINEAGE" "$CFG_HY2_SNI"
  fi

  ensure_core
  ensure_credentials

  # Pre-check generated core config before altering NAT or systemd units.
  core_call render >"$TB_TMP/pre-check.json" || die err_render
  if ! output="$(core_call validate "$TB_TMP/pre-check.json" 2>&1)"; then
    printf '%s\n' "$output" >&2
    restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
    die err_validate "$CFG_CORE"
  fi

  hy2_hop_backup "$hop_backup" || die err_apply
  certbot_hook_backup "$hook_backup" || die err_apply
  acme_timer_backup "$acme_backup" || die err_apply

  if [[ "$CFG_HY2" == "1" && -n "$CFG_HY2_HOP_PORTS" ]]; then
    svc="$(core_call service)"
    hy2_hop_render_json >"$TB_TMP/hy2-hop.json" || die err_apply
    if ! hy2_hop_apply_rules "$TB_TMP/hy2-hop.json"; then
      hy2_hop_restore "$hop_backup"
      restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$svc"
      die err_hy2_hop_apply
    fi
    if ! hy2_hop_install_state "$svc" "$TB_TMP/hy2-hop.json"; then
      hy2_hop_restore "$hop_backup"
      restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$svc"
      die err_hy2_hop_apply
    fi
  else
    hy2_hop_disable
  fi

  if ! apply_config "$old_svc"; then
    hy2_hop_restore "$hop_backup"
    restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
    die err_apply
  fi

  if [[ "$CFG_HY2" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
    if ! certbot_ensure_entrypoint || ! certbot_hook_install; then
      certbot_hook_restore "$hook_backup"
      hy2_hop_restore "$hop_backup"
      rollback_applied_config "$old_svc"
      restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
      die err_hy2_hook_install "$TB_CERTBOT_HOOK_PATH"
    fi
  else
    certbot_hook_remove
    self_install || true
  fi

  if [[ "$CFG_HY2" == "1" && "$CFG_HY2_ACME" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1" ]]; then
    if ! acme_timer_sync "$CFG_HY2_ACME_LINEAGE"; then
      acme_timer_restore "$acme_backup"
      certbot_hook_restore "$hook_backup"
      hy2_hop_restore "$hop_backup"
      rollback_applied_config "$old_svc"
      restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
      die err_hy2_acme_timer
    fi
  else
    acme_timer_remove
  fi

  local -a old_fw_rules=("${CFG_FW_RULES[@]}")
  sync_firewall

  if ! state_save; then
    if [[ "$OPT_NO_FIREWALL" != "1" ]]; then
      fw_sync "${old_fw_rules[@]}"
    fi
    acme_timer_restore "$acme_backup"
    certbot_hook_restore "$hook_backup"
    hy2_hop_restore "$hop_backup"
    rollback_applied_config "$old_svc"
    restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
    die err_state_save "$TB_STATE_FILE"
  fi

  log_ok ok_installed
  post_install_notes

  OPT_FORMAT="text"
  OPT_PROTOCOLS=""
  show_node
}

cmd_show() {
  require_root
  require_state
  show_node
}

cmd_update() {
  require_root
  require_systemd
  tb_mktemp_dir
  tb_acquire_lock
  require_state

  check_sockopt_support "$CFG_CORE"
  core_call render >"$TB_TMP/pre-check.json" || die err_render
  ensure_core 1
  # Re-render with the current templates and restart on the new binary.
  if ! apply_config; then
    restore_core_bin "$TB_PREV_CORE_BIN" "$TB_PREV_CORE_ACTIVE" "$(core_call service)"
    die err_apply
  fi
  state_save || die err_state_save "$TB_STATE_FILE"
  log_ok ok_updated "$CFG_CORE" "$(core_call version || true)"
}

cmd_rotate() {
  require_root
  require_systemd
  tb_mktemp_dir
  tb_acquire_lock
  require_state
  core_call is_installed || die err_core_install "$CFG_CORE"

  confirm n prompt_rotate || die err_aborted
  clear_credentials
  ensure_credentials
  apply_config || die err_apply
  if ! state_save; then
    rollback_applied_config
    die err_state_save "$TB_STATE_FILE"
  fi
  log_ok ok_rotated

  OPT_FORMAT="${OPT_FORMAT:-text}"
  show_node
}

cmd_refresh_cert() {
  local verify_name old_cert old_key old_sha

  require_root
  require_systemd
  tb_mktemp_dir
  tb_acquire_lock
  require_state

  [[ "$CFG_HY2" == "1" ]] || die err_refresh_requires_hy2
  [[ "$CFG_HY2_TLS" == "files" ]] || die err_refresh_requires_files
  if [[ -z "$CFG_HY2_CERT_FILE" || -z "$CFG_HY2_KEY_FILE" ]]; then
    die err_hy2_cert_sources_missing
  fi

  tls_validate_pair_files "$CFG_HY2_CERT_FILE" "$CFG_HY2_KEY_FILE" ||
    die err_hy2_cert_pair "$CFG_HY2_CERT_FILE" "$CFG_HY2_KEY_FILE"
  verify_name="${CFG_HY2_SNI:-$CFG_SERVER_ADDR}"
  tls_cert_matches_name "$CFG_HY2_CERT_FILE" "$verify_name" ||
    die err_hy2_cert_sni_mismatch "$verify_name"

  if [[ "$TLS_CERT_PEM" == "$CFG_HY2_CERT" && "$TLS_KEY_PEM" == "$CFG_HY2_KEY" ]]; then
    log_info info_hy2_cert_unchanged
    return 0
  fi

  core_call is_installed || die err_core_install "$CFG_CORE"
  old_cert="$CFG_HY2_CERT"
  old_key="$CFG_HY2_KEY"
  old_sha="$CFG_HY2_CERT_SHA256"
  CFG_HY2_CERT="$TLS_CERT_PEM"
  CFG_HY2_KEY="$TLS_KEY_PEM"
  CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"

  apply_config "" "if-active" || die err_apply
  if ! state_save; then
    CFG_HY2_CERT="$old_cert"
    CFG_HY2_KEY="$old_key"
    CFG_HY2_CERT_SHA256="$old_sha"
    rollback_applied_config
    die err_state_save "$TB_STATE_FILE"
  fi
  log_ok ok_hy2_cert_refreshed
}

cmd_uninstall() {
  local core
  require_root
  require_systemd
  tb_mktemp_dir
  tb_acquire_lock
  state_load || true
  core="${OPT_CORE:-$CFG_CORE}"
  [[ -n "$core" ]] || die err_no_state

  if [[ "$OPT_PURGE" == "1" ]]; then
    confirm n prompt_uninstall_purge "$core" || die err_aborted
  else
    confirm n prompt_uninstall "$core" || die err_aborted
  fi

  service_stop_disable "$(core_fn "$core" service)"
  if core_fn "$core" is_installed; then
    core_fn "$core" remove "$OPT_PURGE" || die err_remove_failed "$core"
  fi
  # --core can name a core the node does not run on (a leftover from before
  # a switch): then only that core goes, the node itself stays.
  if [[ "$TB_HAS_STATE" == "1" && "$core" != "$CFG_CORE" ]]; then
    log_ok ok_core_removed "$core" "$CFG_CORE"
    return 0
  fi
  hy2_hop_disable
  certbot_hook_remove
  acme_timer_remove
  fw_close_all
  if [[ "$OPT_PURGE" == "1" ]]; then
    rm -rf "$TB_STATE_DIR"
  else
    state_remove
  fi
  rm -f "$TB_SELF_PATH"
  log_ok ok_uninstalled "$core"
}

cmd_menu() {
  local reply
  printf '\n%sToastBox %s%s\n\n' "$TB_C_BOLD" "$TB_VERSION" "$TB_C_RESET" >&2
  printf '%s\n' "$(msg menu_items)" >&2
  reply="$(tb_readline "$(msg prompt_menu): ")"
  case "$reply" in
    1) cmd_install ;;
    2) cmd_show ;;
    3) cmd_update ;;
    4) cmd_rotate ;;
    5) cmd_uninstall ;;
    *) exit 0 ;;
  esac
}

usage() {
  msg usage "$TB_VERSION"
}

tb_main() {
  opt_reset
  tb_init_lang "$@"
  trap tb_cleanup EXIT
  parse_args "$@"
  validate_options
  tb_detect_interactive

  case "$OPT_COMMAND" in
    install) cmd_install ;;
    show) cmd_show ;;
    update) cmd_update ;;
    rotate) cmd_rotate ;;
    refresh-cert) cmd_refresh_cert ;;
    uninstall) cmd_uninstall ;;
    help) usage ;;
    version) printf 'ToastBox %s\n' "$TB_VERSION" ;;
    menu | "")
      if [[ "$TB_INTERACTIVE" != "1" ]]; then
        usage >&2
        exit 2
      fi
      tb_choose_lang
      cmd_menu
      ;;
  esac
}

# ===== src/main.sh =====

# Everything above only defines functions and constants, so a truncated
# download (curl | bash) cannot run half of an installation.
if [[ "${TOASTBOX_SOURCE_ONLY:-0}" != "1" ]]; then
  tb_main "$@"
fi
