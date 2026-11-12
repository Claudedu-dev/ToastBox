#!/usr/bin/env bash
#
# End-to-end test on a real, disposable Debian/Ubuntu machine with systemd
# (the CI runners). It installs the real core, starts the real service and
# pushes traffic through both protocols using the client configurations
# that ToastBox prints.
#
#   sudo tests/e2e/run.sh xray|sing-box [path/to/toastbox.sh]
#
# DO NOT run this on a machine you care about: it installs and purges the
# core and binds ports 443, 8443 and 28443.

set -euo pipefail

core="${1:?usage: run.sh xray|sing-box [toastbox.sh]}"
script="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/toastbox.sh}"

# The runners live in Microsoft's network, which makes this a same-network
# target as the REALITY documentation recommends.
sni="${E2E_REALITY_SNI:-www.microsoft.com}"
probe_url="${E2E_PROBE_URL:-https://www.gstatic.com/generate_204}"
socks="127.0.0.1:1080"
work="$(mktemp -d)"
client_pid=""
http_pid=""

case "$core" in
  xray) service="xray" binary="/usr/local/bin/xray" config="/usr/local/etc/xray/config.json" ;;
  sing-box) service="sing-box" binary="/usr/bin/sing-box" config="/etc/sing-box/config.json" ;;
  *) echo "unknown core: $core" >&2 && exit 2 ;;
esac

step() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
fail() {
  printf '\033[31mFAIL: %s\033[0m\n' "$*" >&2
  exit 1
}

tb() { bash "$script" --lang en "$@"; }
state() { tb show --format json | jq -r "$1"; }

stop_client() {
  if [[ -n "$client_pid" ]]; then
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
    client_pid=""
  fi
}

diagnostics() {
  local rc=$?
  stop_client
  [[ -n "$http_pid" ]] && kill "$http_pid" 2>/dev/null
  if ((rc != 0)); then
    step "diagnostics"
    systemctl status "$service" --no-pager 2>&1 | tail -n 20 || true
    journalctl -u "$service" -n 40 --no-pager 2>&1 || true
    echo "--- server config"
    cat "$config" 2>/dev/null || true
    echo "--- client log"
    cat "$work/client.log" 2>/dev/null || true
    echo "--- listeners"
    ss -lntup 2>/dev/null || true
  fi
  rm -rf "$work"
  exit "$rc"
}
trap diagnostics EXIT

wait_for_port() {
  local port="$1"
  for _ in $(seq 1 50); do
    if [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# start_client PROTOCOL: runs the same core as a client, with the exact
# configuration `toastbox show` hands to users.
start_client() {
  local protocol="$1"
  stop_client
  tb show --format "$core" --protocols "$protocol" >"$work/client.json"
  case "$core" in
    xray) "$binary" run -c "$work/client.json" >"$work/client.log" 2>&1 & ;;
    sing-box) "$binary" run -c "$work/client.json" -D "$work" >"$work/client.log" 2>&1 & ;;
  esac
  client_pid=$!
  wait_for_port 1080 || fail "the $protocol client did not start"
}

# through_proxy URL: prints the HTTP status seen through the client.
through_proxy() {
  curl --socks5-hostname "$socks" -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 "$1"
}

check_protocol() {
  local protocol="$1" code
  start_client "$protocol"
  code="$(through_proxy "$probe_url" || true)"
  [[ "$code" == "204" ]] || fail "$protocol: expected HTTP 204 through the node, got '$code'"
  echo "ok: $protocol relays traffic"

  # Loopback and private destinations must be refused by the server.
  code="$(through_proxy "http://127.0.0.1:18080/" || true)"
  [[ "$code" != "200" ]] || fail "$protocol: the node relayed a request to its own loopback"
  echo "ok: $protocol refuses loopback destinations"
  stop_client
}

check_node() {
  local port tls
  systemctl -q is-active "$service" || fail "$service is not active"
  check_protocol vless
  check_protocol ss

  # A plain TLS client that knows nothing about REALITY must be handed the
  # genuine certificate of the target site.
  port="$(state .vless.port)"
  tls="$(openssl s_client -connect "127.0.0.1:$port" -servername "$sni" \
    -verify_hostname "$sni" </dev/null 2>&1 || true)"
  if [[ "$tls" != *"Verify return code: 0 (ok)"* ]]; then
    printf '%s\n' "$tls" | tail -n 15
    fail "an unauthenticated TLS client did not see the certificate of $sni"
  fi
  echo "ok: unauthenticated TLS clients see the real $sni certificate"

  port="$(state .ss.port)"
  [[ -n "$(ss -H -lun "sport = :$port")" ]] || fail "Shadowsocks is not listening on UDP $port"
  echo "ok: Shadowsocks listens on UDP"
}

[[ "$(id -u)" -eq 0 ]] || fail "run as root"
[[ -f "$script" ]] || fail "$script not found (run scripts/build.sh)"

# A local web server that must stay unreachable through the node.
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$work" >/dev/null 2>&1 &
http_pid=$!

step "install ($core)"
tb install -y --core "$core" --server-addr 127.0.0.1 --name e2e \
  --reality-sni "$sni" --ss-port 28443
[[ -x "$binary" ]] || fail "$binary is missing"
"$binary" version | head -n 1

step "file permissions"
ls -l "$config" /etc/toastbox/state.json
[[ "$(stat -c %a /etc/toastbox/state.json)" == "600" ]] || fail "state.json is not private"
case "$core" in
  xray) [[ "$(stat -c '%a %U:%G' "$config")" == "640 root:xray" ]] || fail "unexpected owner/mode on $config" ;;
  sing-box) [[ "$(stat -c '%a %U:%G' "$config")" == "600 root:root" ]] || fail "unexpected owner/mode on $config" ;;
esac
[[ -x /usr/local/bin/toastbox ]] || fail "the toastbox command was not installed"

step "traffic"
check_node

step "re-run is idempotent"
uuid="$(state .vless.uuid)"
password="$(state .ss.password)"
tb install -y >/dev/null
[[ "$(state .vless.uuid)" == "$uuid" ]] || fail "the UUID changed on a plain re-run"
[[ "$(state .ss.password)" == "$password" ]] || fail "the Shadowsocks key changed on a plain re-run"
echo "ok: credentials unchanged"

step "reconfigure (port, method, BitTorrent blocking)"
toastbox --lang en install -y --vless-port 8443 --ss-method 2022-blake3-aes-256-gcm --block-bt >/dev/null
[[ "$(state .vless.port)" == "8443" ]] || fail "the VLESS port did not change"
[[ "$(state .vless.uuid)" == "$uuid" ]] || fail "the UUID changed on reconfiguration"
[[ "$(state .ss.password)" != "$password" ]] || fail "the key was not regenerated for the new method"
check_node

step "rotate"
tb rotate -y >/dev/null
[[ "$(state .vless.uuid)" != "$uuid" ]] || fail "rotate kept the UUID"
check_node

step "update"
tb update
systemctl -q is-active "$service" || fail "$service is not active after update"

step "uninstall --purge"
tb uninstall -y --purge
if systemctl -q is-active "$service"; then fail "$service is still active"; fi
[[ ! -e "$binary" ]] || fail "$binary still exists"
[[ ! -e /etc/toastbox ]] || fail "/etc/toastbox still exists"
[[ ! -e "$config" ]] || fail "$config still exists"
[[ ! -e /usr/local/bin/toastbox ]] || fail "the toastbox command still exists"
if tb show >/dev/null 2>&1; then fail "show still works after uninstall"; fi

step "all good ($core)"
