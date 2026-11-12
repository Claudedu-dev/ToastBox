# shellcheck shell=bash
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
