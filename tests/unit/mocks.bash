# shellcheck shell=bash
#
# Replaces everything that would touch the host (root check, apt, systemd,
# network, firewall) so the command flow can be exercised end to end.
# Calls are recorded in $MOCK_LOG; behaviour is steered through MOCK_*.

MOCK_LOG="${MOCK_LOG:-/dev/null}"
MOCK_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
MOCK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_root() { :; }
detect_os() { :; }
require_supported_arch() { :; }
require_systemd() { :; }
install_deps() { :; }
self_install() { :; }
certbot_build_entrypoint() {
  [[ -x "$TB_SELF_PATH" ]] && return 0
  install -d -m 755 "$(dirname "$TB_SELF_PATH")"
  cat >"$TB_SELF_PATH" <<EOF
#!/usr/bin/env bash
export TOASTBOX_SOURCE_ONLY=1
source "$MOCK_REPO_ROOT/src/main.sh"
source "$MOCK_REPO_ROOT/tests/unit/mocks.bash"
tb_main "\$@"
EOF
  chmod 755 "$TB_SELF_PATH"
}

systemctl() {
  echo "systemctl $*" >>"$MOCK_LOG"
  case "${1:-}" in
    enable) [[ -z "${MOCK_SYSTEMCTL_ENABLE_FAILS:-}" ]] ;;
    daemon-reload | disable | start | stop | restart) return 0 ;;
    *) return 1 ;;
  esac
}

service_restart_checked() {
  echo "restart $1" >>"$MOCK_LOG"
  [[ -z "${MOCK_RESTART_FAILS:-}" ]]
}
service_stop_disable() { echo "stop $1" >>"$MOCK_LOG"; }
service_is_active() { [[ -z "${MOCK_SERVICE_INACTIVE:-}" ]]; }
service_unit_exists() { return 1; }
service_show_log() { :; }

xray_install() {
  echo "install xray ${1:-latest}" >>"$MOCK_LOG"
  cp "$MOCK_FIXTURES/fake-xray" "$TB_XRAY_BIN"
}
xray_remove() {
  echo "remove xray purge=$1" >>"$MOCK_LOG"
  [[ -z "${MOCK_REMOVE_FAILS:-}" ]] || return 1
  rm -f "$TB_XRAY_BIN"
}
singbox_install() {
  echo "install sing-box ${1:-latest}" >>"$MOCK_LOG"
  cp "$MOCK_FIXTURES/fake-sing-box" "$TB_SINGBOX_BIN"
}
singbox_remove() {
  echo "remove sing-box purge=$1" >>"$MOCK_LOG"
  [[ -z "${MOCK_REMOVE_FAILS:-}" ]] || return 1
  rm -f "$TB_SINGBOX_BIN"
}

# MOCK_BUSY_PORT="tcp:443:nginx" marks one port as taken.
port_owners() {
  if [[ "${MOCK_BUSY_PORT:-}" == "$1:$2:"* ]]; then
    printf '%s\n' "${MOCK_BUSY_PORT##*:}"
  fi
}

udp_listening_ports() {
  if [[ "${MOCK_BUSY_PORT:-}" == udp:*:* ]]; then
    local rest="${MOCK_BUSY_PORT#udp:}"
    printf '%s %s\n' "${rest%%:*}" "${rest#*:}"
  fi
}

hy2_hop_detect_backend() {
  [[ -z "${MOCK_HY2_HOP_NO_BACKEND:-}" ]] || return 1
  printf '%s' "${TOASTBOX_HY2_HOP_BACKEND:-nftables}"
}
hy2_hop_check_tools() {
  if [[ -n "${MOCK_HY2_HOP_NO_CMD:-}" ]]; then
    die err_hy2_hop_no_cmd "$MOCK_HY2_HOP_NO_CMD"
  fi
  return 0
}
hy2_hop_apply_rules() {
  echo "hy2_hop_apply $1" >>"$MOCK_LOG"
  [[ -z "${MOCK_HY2_HOP_FAILS:-}" ]]
}
hy2_hop_remove_rules() {
  echo "hy2_hop_remove" >>"$MOCK_LOG"
}

# MOCK_PROBE_RC fails every probe; MOCK_PROBE_FAIL_SNI only that name.
probe_reality_target() {
  echo "probe $1 $2" >>"$MOCK_LOG"
  TB_TARGET_H2=1
  if [[ "$1" == "${MOCK_PROBE_FAIL_SNI:-}" ]]; then
    return 3
  fi
  return "${MOCK_PROBE_RC:-0}"
}

detect_server_addr() { printf '%s' "${MOCK_DETECTED_ADDR:-}"; }
clock_synchronized() { [[ -z "${MOCK_CLOCK_UNSYNCED:-}" ]]; }
ipv6_enabled() { [[ -z "${MOCK_NO_IPV6:-}" ]]; }
acme_system_timer_active() { [[ -n "${MOCK_CERTBOT_SYSTEM_TIMER:-}" ]]; }
acme_install_certbot() {
  if ! has_cmd certbot; then
    echo "install_certbot" >>"$MOCK_LOG"
  fi
  has_cmd certbot || die err_hy2_acme_certbot_install
}

fw_backend() { printf '%s' "${MOCK_FW_BACKEND:-}"; }
fw_open() {
  echo "fw_open $1" >>"$MOCK_LOG"
  return 0
}
fw_close() { echo "fw_close $1" >>"$MOCK_LOG"; }

# MOCK_ANSWERS=FILE simulates a terminal: every prompt consumes one line of
# FILE (an empty line is "just press Enter") and is recorded in the log.
if [[ -n "${MOCK_ANSWERS:-}" ]]; then
  tb_tty_ok() { return 0; }
  tb_readline() {
    local line
    line="$(head -n 1 "$MOCK_ANSWERS")"
    sed -i 1d "$MOCK_ANSWERS"
    printf 'prompt: %s\n' "$1" >>"$MOCK_LOG"
    printf '%s' "$line"
  }
fi
