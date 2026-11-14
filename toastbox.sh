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
TB_XRAY_BIN="${TOASTBOX_XRAY_BIN:-/usr/local/bin/xray}"
TB_XRAY_CONFIG="${TOASTBOX_XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
TB_SINGBOX_BIN="${TOASTBOX_SINGBOX_BIN:-/usr/bin/sing-box}"
TB_SINGBOX_CONFIG="${TOASTBOX_SINGBOX_CONFIG:-/etc/sing-box/config.json}"
TB_SINGBOX_KEYRING="/etc/apt/keyrings/sagernet.asc"
TB_SINGBOX_APT_SOURCE="/etc/apt/sources.list.d/sagernet.sources"
TB_SELF_PATH="${TOASTBOX_SELF_PATH:-/usr/local/bin/toastbox}"

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

# install_owned MODE GROUP SRC DEST: like install(1), owned by root:GROUP.
# Ownership is only set when running as root, which is always the case in
# production; the test-suite runs unprivileged.
install_owned() {
  local mode="$1" group="$2" src="$3" dest="$4"
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m "$mode" -o root -g "$group" "$src" "$dest"
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
TB_MSG_EN[err_protocols]='Invalid protocol list "%s". Use vless, ss or vless,ss.'
TB_MSG_EN[err_protocol_disabled]='Protocol "%s" is not enabled on this node.'
TB_MSG_EN[err_format]='Unknown format "%s". Use text, links, json, xray or sing-box.'
TB_MSG_EN[err_aborted]='Aborted. Nothing was changed. (Use --yes to confirm without a prompt.)'
TB_MSG_EN[err_sockopt_core]='Custom TCP sockopt is supported only by Xray, not %s. Use install --reset-sockopt to clear it before switching cores.'
TB_MSG_EN[err_sockopt_command]='TCP sockopt options are only accepted with install; update and rotate reuse the saved settings.'

TB_MSG_EN[prompt_core]='Core: 1) xray  2) sing-box'
TB_MSG_EN[prompt_protocols]='Protocols: 1) both  2) VLESS-REALITY-Vision only  3) Shadowsocks 2022 only'
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
TB_MSG_EN[err_no_free_port]='Could not find a free port. Pass one with --ss-port.'
TB_MSG_EN[err_port_same]='VLESS and Shadowsocks cannot both listen on TCP port %s.'
TB_MSG_EN[err_port_in_use]='Port %s is already in use by: %s'
TB_MSG_EN[plan_title]='About to deploy:'
TB_MSG_EN[prompt_proceed]='Proceed?'

TB_MSG_EN[warn_core_switch]='Switching core from %s to %s. The %s service is stopped and disabled once the new core is ready.'
TB_MSG_EN[prompt_overwrite_config]='%s already holds a configuration that ToastBox did not write. Replace it? (A backup is kept.)'
TB_MSG_EN[err_foreign_config]='Kept the existing configuration %s. Re-run with --overwrite-config to replace it.'
TB_MSG_EN[info_installing_core]='Installing %s from its official source...'
TB_MSG_EN[err_core_install]='Installing %s failed.'
TB_MSG_EN[err_core_too_old]='%s %s is too old: ToastBox needs %s or newer. Run "update" to upgrade it.'
TB_MSG_EN[ok_core_ready]='%s %s is installed.'
TB_MSG_EN[err_render]='Could not generate the configuration.'
TB_MSG_EN[err_validate]='%s rejected the generated configuration. Nothing was changed.'
TB_MSG_EN[info_restarting]='Restarting %s...'
TB_MSG_EN[ok_service_running]='%s is running.'
TB_MSG_EN[err_service_start]='%s failed to start with the new configuration. Recent log:'
TB_MSG_EN[warn_rolled_back]='Restored the previous configuration from %s.'
TB_MSG_EN[warn_service_stopped]='%s was not running before this change and has been left stopped.'
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
TB_MSG_EN[warn_remove_failed]='Removing %s reported an error; check the output above.'
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
TB_MSG_EN[label_link]='Share link:'
TB_MSG_EN[note_ss_landing]='Note: Shadowsocks has no TLS camouflage. Use it as a landing node behind a relay, not for connections that cross a censoring firewall directly.'
TB_MSG_EN[note_client_configs]='Client configurations: "show --format xray" or "show --format sing-box". Links only: "show --format links". QR codes: "show --qr".'
TB_MSG_EN[note_firewall]='If the provider has its own firewall / security group, open the ports above there as well.'

TB_MSG_EN[menu_items]='  1) Install or reconfigure a node
  2) Show connection details
  3) Update the core
  4) Rotate credentials
  5) Uninstall
  0) Exit'
TB_MSG_EN[prompt_menu]='Choose'

TB_MSG_EN[usage]='ToastBox %s - VLESS-TCP-REALITY-Vision and Shadowsocks 2022 nodes on Xray or sing-box

Usage: toastbox.sh [command] [options]

Run without a command for the interactive menu.

Commands:
  install      Deploy a node, or change the settings of an existing one
  show         Print connection details, share links or client configs
  update       Upgrade the core and restart the node
  rotate       Generate new UUID / keys / passwords
  uninstall    Remove the core and the node
  help, version

Options for install:
  --core xray|sing-box        Core to use (default: xray)
  --protocols LIST            vless, ss or vless,ss (default: vless,ss)
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
  --tcp-keepalive-idle SEC    Xray TCP keepalive idle (1..32767 seconds)
  --tcp-keepalive-interval SEC  Xray TCP keepalive interval (1..32767 seconds)
  --tcp-user-timeout MS       Xray TCP user timeout (1..2147483647 milliseconds)
                              0 clears one override; unset values keep defaults
  --reset-sockopt             Clear all saved TCP overrides before applying flags
  --block-bt                  Reject BitTorrent traffic (--no-block-bt to undo)
  --allow-private             Allow relaying to private / loopback addresses
                              (--no-allow-private to undo)
  --core-version VERSION      Install this core version instead of the latest
  --no-firewall               Do not touch ufw
  --overwrite-config          Replace a configuration ToastBox did not write
                              (--yes alone never does)

Options for show:
  --format FORMAT             text (default), links, json, xray, sing-box
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
TB_MSG_ZH[err_protocols]='协议列表“%s”无效，可选 vless、ss 或 vless,ss。'
TB_MSG_ZH[err_protocol_disabled]='此节点未启用协议“%s”。'
TB_MSG_ZH[err_format]='未知格式“%s”，可选 text、links、json、xray 或 sing-box。'
TB_MSG_ZH[err_aborted]='已取消，未做任何更改。（使用 --yes 可跳过确认。）'
TB_MSG_ZH[err_sockopt_core]='自定义 TCP sockopt 仅支持 Xray，不支持 %s。切换内核前请用 install --reset-sockopt 清除。'
TB_MSG_ZH[err_sockopt_command]='TCP sockopt 选项仅可用于 install；update 和 rotate 会复用已保存的设置。'

TB_MSG_ZH[prompt_core]='内核：1) xray  2) sing-box'
TB_MSG_ZH[prompt_protocols]='协议：1) 两者都部署  2) 仅 VLESS-REALITY-Vision  3) 仅 Shadowsocks 2022'
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
TB_MSG_ZH[err_no_free_port]='找不到空闲端口，请用 --ss-port 指定。'
TB_MSG_ZH[err_port_same]='VLESS 和 Shadowsocks 不能同时监听 TCP 端口 %s。'
TB_MSG_ZH[err_port_in_use]='端口 %s 已被占用：%s'
TB_MSG_ZH[plan_title]='即将部署：'
TB_MSG_ZH[prompt_proceed]='继续？'

TB_MSG_ZH[warn_core_switch]='内核将由 %s 切换为 %s，新内核就绪后 %s 服务会被停止并禁用。'
TB_MSG_ZH[prompt_overwrite_config]='%s 中已有一份并非由 ToastBox 生成的配置。是否替换？（会保留备份。）'
TB_MSG_ZH[err_foreign_config]='已保留现有配置 %s。如需替换，请加上 --overwrite-config 重新运行。'
TB_MSG_ZH[info_installing_core]='正在从官方渠道安装 %s……'
TB_MSG_ZH[err_core_install]='安装 %s 失败。'
TB_MSG_ZH[err_core_too_old]='%s %s 版本过旧：ToastBox 需要 %s 或更高版本。请执行 update 升级。'
TB_MSG_ZH[ok_core_ready]='%s %s 已安装。'
TB_MSG_ZH[err_render]='无法生成配置。'
TB_MSG_ZH[err_validate]='%s 未通过对生成配置的校验，未做任何更改。'
TB_MSG_ZH[info_restarting]='正在重启 %s……'
TB_MSG_ZH[ok_service_running]='%s 正在运行。'
TB_MSG_ZH[err_service_start]='%s 使用新配置启动失败。最近的日志：'
TB_MSG_ZH[warn_rolled_back]='已从 %s 恢复之前的配置。'
TB_MSG_ZH[warn_service_stopped]='%s 在本次更改之前并未运行，现已保持停止状态。'
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
TB_MSG_ZH[warn_remove_failed]='移除 %s 时出现错误，请查看上方输出。'
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
TB_MSG_ZH[label_link]='分享链接：'
TB_MSG_ZH[note_ss_landing]='注意：Shadowsocks 没有 TLS 伪装，适合作为中转之后的落地节点，不适合直接穿越审查防火墙。'
TB_MSG_ZH[note_client_configs]='客户端配置：show --format xray 或 show --format sing-box；仅链接：show --format links；二维码：show --qr。'
TB_MSG_ZH[note_firewall]='如果服务商另有防火墙 / 安全组，请在那里同样放行上述端口。'

TB_MSG_ZH[menu_items]='  1) 安装或重新配置节点
  2) 查看连接信息
  3) 更新内核
  4) 重新生成凭据
  5) 卸载
  0) 退出'
TB_MSG_ZH[prompt_menu]='请选择'

TB_MSG_ZH[usage]='ToastBox %s - 基于 Xray 或 sing-box 部署 VLESS-TCP-REALITY-Vision 与 Shadowsocks 2022 节点

用法：toastbox.sh [命令] [选项]

不带命令运行将进入交互菜单。

命令：
  install      部署节点，或修改现有节点的设置
  show         显示连接信息、分享链接或客户端配置
  update       升级内核并重启节点
  rotate       重新生成 UUID / 密钥 / 密码
  uninstall    移除内核和节点
  help, version

install 的选项：
  --core xray|sing-box        使用的内核（默认：xray）
  --protocols LIST            vless、ss 或 vless,ss（默认：vless,ss）
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
  --tcp-keepalive-idle SEC    Xray TCP 保活空闲时间（1..32767 秒）
  --tcp-keepalive-interval SEC  Xray TCP 保活探测间隔（1..32767 秒）
  --tcp-user-timeout MS       Xray TCP 用户超时（1..2147483647 毫秒）
                              0 清除单项覆盖；未设置时沿用默认值
  --reset-sockopt             清除已保存的 TCP 覆盖，再应用本次显式参数
  --block-bt                  拒绝 BitTorrent 流量（--no-block-bt 取消）
  --allow-private             允许转发到私有 / 回环地址
                              （--no-allow-private 取消）
  --core-version VERSION      安装指定版本的内核，而不是最新版
  --no-firewall               不修改 ufw
  --overwrite-config          替换并非由 ToastBox 生成的现有配置
                              （仅有 --yes 不会替换）

show 的选项：
  --format FORMAT             text（默认）、links、json、xray、sing-box
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

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die err_root
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

service_is_active() { systemctl -q is-active "$1" 2>/dev/null; }

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
      firewall: {rules: $ARGS.positional}
    }' "${CFG_FW_RULES[@]}"
}

state_save() {
  local tmp
  install -d -m 700 "$TB_STATE_DIR"
  tmp="$(mktemp "$TB_STATE_DIR/.state.XXXXXX")"
  chmod 600 "$tmp"
  state_json >"$tmp"
  mv -f "$tmp" "$TB_STATE_FILE"
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
    if (.schema | type) != "number" then error("missing schema") else . end
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
      "CFG_FW_RULES=(" + ((.firewall.rules // []) | map(@sh) | join(" ")) + ")"
  ' "$TB_STATE_FILE" 2>/dev/null)" || die err_state_corrupt "$TB_STATE_FILE"

  eval "$assignments"
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
  install -d -m 700 "$TB_STATE_DIR" "$TB_BACKUP_DIR"
  dest="$TB_BACKUP_DIR/$prefix-$(date +%Y%m%d-%H%M%S)-$$.json"
  cp -p "$src" "$dest"
  chmod 600 "$dest"
  # Newest first; drop everything after the fifth.
  find "$TB_BACKUP_DIR" -maxdepth 1 -type f -name "$prefix-*.json" -printf '%T@ %p\n' |
    sort -rn | awk 'NR > 5 {sub(/^[^ ]+ /, ""); print}' |
    while IFS= read -r old; do
      rm -f "$old"
    done
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
}

clear_credentials() {
  CFG_VLESS_UUID=""
  CFG_REALITY_PRIVATE_KEY=""
  CFG_REALITY_PUBLIC_KEY=""
  CFG_REALITY_SHORT_ID=""
  CFG_SS_PASSWORD=""
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

# The service runs as the unprivileged `xray` user: the configuration holds
# the REALITY private key, so it is readable by root and that group only.
xray_install_config() {
  local src="$1" dir tmp mode="644" group="root"
  dir="$(dirname "$TB_XRAY_CONFIG")"
  tmp="$TB_XRAY_CONFIG.toastbox-new"
  # Without the dedicated group (Xray not installed by the official script)
  # the file has to stay world-readable for the service user.
  if getent group xray >/dev/null 2>&1; then
    mode="640"
    group="xray"
  fi
  install -d "$dir"
  install_owned "$mode" "$group" "$src" "$tmp"
  mv -f "$tmp" "$TB_XRAY_CONFIG"
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
    --args '
    def with_listen: if $listen == "" then . else {listen: $listen} + . end;
    # routeOnly: the sniffed protocol is used for routing only, the
    # destination of the connection is left untouched.
    def with_sniffing:
      if $block_bt == "1"
      then . + {sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}
      else . end;

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
            streamSettings: {
              method: "raw",
              security: "reality",
              realitySettings: {
                target: $target,
                serverNames: [$sni],
                privateKey: $private_key,
                shortIds: [$short_id]
              }
            } + (if $sockopt == {} then {} else {sockopt: $sockopt} end)
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
        else empty end)
      ],
      outbounds: [
        {tag: "direct", protocol: "freedom"},
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
  install -d -m 755 /etc/apt/keyrings
  tb_download "$TB_SINGBOX_KEY_URL" "$TB_SINGBOX_KEYRING" || die err_download "$TB_SINGBOX_KEY_URL"
  chmod a+r "$TB_SINGBOX_KEYRING"
  cat >"$TB_SINGBOX_APT_SOURCE" <<EOF
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
  singbox_setup_repo
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
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sing-box >&2 || true
    rm -rf "$(dirname "$TB_SINGBOX_CONFIG")" /var/lib/sing-box
    rm -f "$TB_SINGBOX_APT_SOURCE" "$TB_SINGBOX_KEYRING"
  else
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sing-box >&2 || true
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
  install -d "$dir"
  install_owned 600 root "$src" "$tmp"
  mv -f "$tmp" "$TB_SINGBOX_CONFIG"
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
    --arg ss_network "$CFG_SS_NETWORK" '
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

# client_jq FILTER: runs a jq filter with the arguments shared by both
# client renderers. OUT_VLESS / OUT_SS select which outbounds are emitted.
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
        else empty end)
      ]
    }'
}

# A complete sing-box client configuration: mixed (SOCKS5 + HTTP) proxy on
# 127.0.0.1:1080. REALITY on the client side needs uTLS.
client_singbox_json() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  client_jq '
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
        else empty end)
      ],
      route: {final: (if $vless == "1" then "vless-reality" else "ss-2022" end)}
    }'
}

# Machine-readable description: the state plus the share links. The REALITY
# private key is left out: no client needs it, and this output tends to get
# pasted into issues and chats.
show_json() {
  local vless_uri="" ss_uri=""
  [[ "$OUT_VLESS" == "1" ]] && vless_uri="$(vless_link)"
  [[ "$OUT_SS" == "1" ]] && ss_uri="$(ss_link)"
  state_json | jq --arg vless "$vless_uri" --arg ss "$ss_uri" \
    --arg version "$TB_VERSION" '
    del(.firewall, .schema, .vless.private_key)
    + {toastbox_version: $version}
    + {links: ({} + (if $vless != "" then {vless: $vless} else {} end)
                  + (if $ss != "" then {ss: $ss} else {} end))}'
}

show_links() {
  if [[ "$OUT_VLESS" == "1" ]]; then vless_link; fi
  if [[ "$OUT_SS" == "1" ]]; then ss_link; fi
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
  local svc status version link
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

  printf '\n%s\n%s\n\n' "$(msg note_client_configs)" "$(msg note_firewall)"
}

# Decides which protocols `show` prints: every enabled one, optionally
# narrowed down by --protocols.
select_output_protocols() {
  OUT_VLESS="$CFG_VLESS"
  OUT_SS="$CFG_SS"
  if [[ -n "${OPT_PROTOCOLS:-}" ]]; then
    local want_vless=0 want_ss=0
    parse_protocols "$OPT_PROTOCOLS" || die err_protocols "$OPT_PROTOCOLS"
    want_vless="$PARSED_VLESS"
    want_ss="$PARSED_SS"
    [[ "$want_vless" == "1" && "$CFG_VLESS" != "1" ]] && die err_protocol_disabled "vless"
    [[ "$want_ss" == "1" && "$CFG_SS" != "1" ]] && die err_protocol_disabled "ss"
    OUT_VLESS="$want_vless"
    OUT_SS="$want_ss"
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
      if [[ "$var" == OPT_TCP_* && -z "$1" ]]; then
        die err_invalid_option "$arg" "$1"
      fi
      printf -v "$var" '%s' "$1"
      shift
      continue
    fi

    case "$arg" in
      install | show | update | rotate | uninstall | menu | help | version)
        [[ -z "$OPT_COMMAND" ]] || die err_unknown_arg "$arg"
        OPT_COMMAND="$arg"
        ;;
      -h | --help) OPT_COMMAND="help" ;;
      -V | --version) OPT_COMMAND="version" ;;
      -y | --yes) OPT_YES=1 ;;
      --skip-target-check) OPT_SKIP_TARGET_CHECK=1 ;;
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

# parse_protocols "vless,ss": result in PARSED_VLESS / PARSED_SS.
parse_protocols() {
  local item
  local -a items=()
  PARSED_VLESS=0
  PARSED_SS=0
  IFS=',+ ' read -r -a items <<<"$1"
  ((${#items[@]} > 0)) || return 1
  for item in "${items[@]}"; do
    case "$item" in
      1 | all | both) PARSED_VLESS=1 PARSED_SS=1 ;;
      2 | vless | reality | vless-reality) PARSED_VLESS=1 ;;
      3 | ss | ss2022 | shadowsocks | shadowsocks-2022) PARSED_SS=1 ;;
      *) return 1 ;;
    esac
  done
}

norm_protocols() {
  local -a out=()
  parse_protocols "$1" || return 1
  [[ "$PARSED_VLESS" == "1" ]] && out+=(vless)
  [[ "$PARSED_SS" == "1" ]] && out+=(ss)
  join_by , "${out[@]}"
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
    *) return 1 ;;
  esac
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
  normalize_opt OPT_TCP_KEEPALIVE_IDLE norm_tcp_keepalive --tcp-keepalive-idle
  normalize_opt OPT_TCP_KEEPALIVE_INTERVAL norm_tcp_keepalive --tcp-keepalive-interval
  normalize_opt OPT_TCP_USER_TIMEOUT norm_tcp_user_timeout --tcp-user-timeout
  if [[ -n "$OPT_TCP_KEEPALIVE_IDLE$OPT_TCP_KEEPALIVE_INTERVAL$OPT_TCP_USER_TIMEOUT" || "$OPT_RESET_SOCKOPT" == "1" ]]; then
    [[ "$OPT_COMMAND" == "install" ]] || die err_sockopt_command
  fi
  normalize_opt OPT_CORE_VERSION norm_version --core-version
  normalize_opt OPT_FORMAT norm_format --format
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
}

resolve_protocols() {
  local current="vless,ss" chosen
  if [[ "$TB_HAS_STATE" == "1" ]]; then
    case "$CFG_VLESS$CFG_SS" in
      10) current="vless" ;;
      01) current="ss" ;;
    esac
  fi
  if [[ -n "$OPT_PROTOCOLS" ]]; then
    chosen="$OPT_PROTOCOLS"
  else
    ask_valid chosen "$current" norm_protocols prompt_protocols
  fi
  parse_protocols "$chosen"
  CFG_VLESS="$PARSED_VLESS"
  CFG_SS="$PARSED_SS"
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
      default_port="$(random_free_port)" || die err_no_free_port
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
  if [[ "$CFG_SS" == "1" ]]; then resolve_ss; fi

  if [[ "$CFG_VLESS" == "1" && "$CFG_SS" == "1" &&
    "$CFG_VLESS_PORT" == "$CFG_SS_PORT" && "$CFG_SS_NETWORK" != "udp" ]]; then
    die err_port_same "$CFG_VLESS_PORT"
  fi
  return 0
}

print_plan() {
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
  return 0
}

# ensure_core [force]: installs the core when it is missing, when a specific
# version was requested or when forced (update), then checks that it is
# recent enough for the configuration we write.
ensure_core() {
  local force="${1:-0}" version min
  check_sockopt_support "$CFG_CORE"
  if [[ "$force" == "1" || -n "$OPT_CORE_VERSION" ]] || ! core_call is_installed; then
    log_info info_installing_core "$CFG_CORE"
    core_call install "$OPT_CORE_VERSION" || die err_core_install "$CFG_CORE"
  fi
  core_call is_installed || die err_core_install "$CFG_CORE"
  version="$(core_call version || true)"
  min="$(core_call min_version)"
  if [[ -z "$version" ]] || ! ver_ge "$version" "$min"; then
    die err_core_too_old "$CFG_CORE" "${version:-?}" "$min"
  fi
  log_ok ok_core_ready "$CFG_CORE" "$version"
}

# apply_config [OLD_SERVICE]: renders, validates, installs and activates
# the configuration.
#
# OLD_SERVICE is the service of a core that is being replaced. It is only
# stopped once the new configuration has passed validation, and it is
# started again if the new core does not come up.
#
# On failure the previous configuration file is restored, but the service
# is only restarted on it if it was running before: a configuration that
# was merely lying around (such as the sample shipped in the sing-box
# package) must never be put into service by a rollback.
apply_config() {
  local old_svc="${1:-}"
  local new="$TB_TMP/config.json" path svc backup="" output was_active=0
  path="$(core_call config_path)"
  svc="$(core_call service)"
  check_sockopt_support "$CFG_CORE"

  core_call render >"$new" || die err_render
  if ! output="$(core_call validate "$new" 2>&1)"; then
    printf '%s\n' "$output" >&2
    die err_validate "$CFG_CORE"
  fi

  service_is_active "$svc" && was_active=1
  if [[ -n "$old_svc" ]]; then
    service_stop_disable "$old_svc"
  fi
  backup="$(backup_file "$path" "$CFG_CORE-config")"
  core_call install_config "$new"
  log_info info_restarting "$svc"
  if service_restart_checked "$svc"; then
    log_ok ok_service_running "$svc"
    return 0
  fi

  log_err err_service_start "$svc"
  service_show_log "$svc"
  if [[ -n "$backup" ]]; then
    core_call install_config "$backup"
    log_warn warn_rolled_back "$backup"
  fi
  if [[ "$was_active" == "1" && -n "$backup" ]]; then
    service_restart_checked "$svc" || true
  else
    service_stop_disable "$svc"
    log_warn warn_service_stopped "$svc"
  fi
  if [[ -n "$old_svc" ]]; then
    service_restart_checked "$old_svc" || true
    log_warn warn_old_core_restored "$old_svc"
  fi
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
  local src="${BASH_SOURCE[0]:-}"
  [[ "${TB_BUILT:-0}" == "1" && -f "$src" ]] || return 0
  [[ "$(readlink -f "$src")" != "$(readlink -f "$TB_SELF_PATH")" ]] || return 0
  install -m 755 "$src" "$TB_SELF_PATH" && log_ok ok_self_installed "$TB_SELF_PATH"
  return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_install() {
  local prev_core core_preinstalled=0 path old_svc="" old_proc=""

  require_root
  detect_os
  require_supported_arch
  require_systemd
  tb_mktemp_dir
  install_deps

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

  # A core that was installed by someone else (a panel, a hand-made node)
  # may carry a configuration that is in use. Replacing it takes an explicit
  # answer at the prompt or --overwrite-config; --yes alone is not enough.
  # (A backup is made either way.)
  core_call is_installed && core_preinstalled=1
  path="$(core_call config_path)"
  if [[ "$core_preinstalled" == "1" && "$prev_core" != "$CFG_CORE" && -s "$path" ]] &&
    [[ "$(tr -d '[:space:]' <"$path")" != "{}" && "$OPT_OVERWRITE_CONFIG" != "1" ]]; then
    if [[ "$TB_INTERACTIVE" != "1" ]] || ! confirm n prompt_overwrite_config "$path"; then
      die err_foreign_config "$path"
    fi
  fi

  preflight_ports "$old_proc"
  ensure_core
  ensure_credentials
  apply_config "$old_svc" || die err_apply
  sync_firewall
  state_save
  self_install
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
  require_state

  ensure_core 1
  # Re-render with the current templates and restart on the new binary.
  apply_config || die err_apply
  state_save
  log_ok ok_updated "$CFG_CORE" "$(core_call version || true)"
}

cmd_rotate() {
  require_root
  require_systemd
  tb_mktemp_dir
  require_state
  core_call is_installed || die err_core_install "$CFG_CORE"

  confirm n prompt_rotate || die err_aborted
  clear_credentials
  ensure_credentials
  apply_config || die err_apply
  state_save
  log_ok ok_rotated

  OPT_FORMAT="${OPT_FORMAT:-text}"
  show_node
}

cmd_uninstall() {
  local core
  require_root
  require_systemd
  tb_mktemp_dir
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
    core_fn "$core" remove "$OPT_PURGE" || log_warn warn_remove_failed "$core"
  fi
  # --core can name a core the node does not run on (a leftover from before
  # a switch): then only that core goes, the node itself stays.
  if [[ "$TB_HAS_STATE" == "1" && "$core" != "$CFG_CORE" ]]; then
    log_ok ok_core_removed "$core" "$CFG_CORE"
    return 0
  fi
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
