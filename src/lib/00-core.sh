# shellcheck shell=bash
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
