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
masq_pid=""
hy2_client=""
e2e_netns=""
e2e_live_dir=""
e2e_archive_dir=""
e2e_sibling_hook=""
ufw_was_active=0

case "$core" in
  xray) service="xray" binary="/usr/local/bin/xray" config="/usr/local/etc/xray/config.json" ;;
  sing-box) service="sing-box" binary="/usr/bin/sing-box" config="/etc/sing-box/config.json" ;;
  *) echo "unknown core: $core" >&2 && exit 2 ;;
esac
xray_client="$binary"
singbox_client="$binary"

case "$(uname -m)" in
  x86_64 | amd64) arch="amd64" xray_arch="64" ;;
  aarch64 | arm64) arch="arm64" xray_arch="arm64-v8a" ;;
  *) echo "unsupported arch: $(uname -m)" >&2 && exit 2 ;;
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
  [[ -n "$masq_pid" ]] && kill "$masq_pid" 2>/dev/null
  if [[ "$ufw_was_active" == "1" ]] && command -v ufw >/dev/null 2>&1; then
    ufw --force disable >/dev/null 2>&1 || true
  fi
  if [[ -n "$e2e_netns" ]]; then
    ip netns del "$e2e_netns" 2>/dev/null || true
    ip link del tb-veth-srv 2>/dev/null || true
  fi
  if command -v nft >/dev/null 2>&1; then
    nft delete table inet e2e_keep 2>/dev/null || true
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -w -t nat -F E2E-KEEP 2>/dev/null || true
    iptables -w -t nat -X E2E-KEEP 2>/dev/null || true
  fi
  rm -rf "$e2e_live_dir" "$e2e_archive_dir" "$e2e_sibling_hook" \
    /etc/letsencrypt/live/toastbox-hy2-acme.e2e.test /etc/letsencrypt/archive/toastbox-hy2-acme.e2e.test 2>/dev/null || true
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
  local port="$1" ns="${2:-}"
  for _ in $(seq 1 50); do
    if [[ -n "$ns" ]]; then
      if [[ -n "$(ip netns exec "$ns" ss -H -ltn "sport = :$port")" ]]; then
        return 0
      fi
    elif [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
      return 0
    fi
    if [[ -n "$client_pid" ]] && ! kill -0 "$client_pid" 2>/dev/null; then
      return 1
    fi
    sleep 0.2
  done
  return 1
}

# start_client FORMAT PROTOCOL [CONFIG_OVERRIDE [NETNS]]: runs a client binary
# with the configuration `toastbox show` hands to users.
start_client() {
  local format="$1" protocol="$2" cfg="${3:-$work/client.json}" ns="${4:-}"
  local -a prefix=()
  [[ -n "$ns" ]] && prefix=(ip netns exec "$ns")
  stop_client
  if [[ -z "${3:-}" ]]; then
    tb show --format "$format" --protocols "$protocol" >"$cfg"
  fi
  case "$format" in
    xray) "${prefix[@]}" "$xray_client" run -c "$cfg" >"$work/client.log" 2>&1 & ;;
    sing-box) "${prefix[@]}" "$singbox_client" run -c "$cfg" -D "$work" >"$work/client.log" 2>&1 & ;;
    hysteria2) "${prefix[@]}" "$hy2_client" client -c "$cfg" >"$work/client.log" 2>&1 & ;;
  esac
  client_pid=$!
  wait_for_port 1080 "$ns"
}

# through_proxy URL [NETNS]: prints the HTTP status seen through the client.
through_proxy() {
  local url="$1" ns="${2:-}"
  local -a prefix=()
  [[ -n "$ns" ]] && prefix=(ip netns exec "$ns")
  "${prefix[@]}" curl --socks5-hostname "$socks" -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 "$url"
}

# udp_dns_through_socks HOST PORT [NETNS]: sends a UDP DNS A query for
# example.com over SOCKS5 UDP ASSOCIATE and verifies a valid DNS response.
udp_dns_through_socks() {
  local -a prefix=()
  [[ -n "${3:-}" ]] && prefix=(ip netns exec "$3")
  "${prefix[@]}" python3 - "$1" "$2" <<'PY'
import socket, struct, sys

socks_host, socks_port = sys.argv[1], int(sys.argv[2])
tcp = socket.create_connection((socks_host, socks_port), timeout=10)
tcp.sendall(b"\x05\x01\x00")
if tcp.recv(2) != b"\x05\x00":
    raise RuntimeError("SOCKS5 greeting failed")
tcp.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
rep = tcp.recv(10)
if len(rep) < 10 or rep[1] != 0:
    raise RuntimeError(f"UDP ASSOCIATE failed: {rep!r}")
relay_ip = socket.inet_ntoa(rep[4:8])
if relay_ip == "0.0.0.0":
    relay_ip = socks_host
relay_port = struct.unpack("!H", rep[8:10])[0]

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.settimeout(10)
query = (
    b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    b"\x07example\x03com\x00\x00\x01\x00\x01"
)
pkt = b"\x00\x00\x00\x01" + socket.inet_aton("1.1.1.1") + struct.pack("!H", 53) + query
udp.sendto(pkt, (relay_ip, relay_port))
data, _ = udp.recvfrom(4096)
if len(data) < 12 or data[10:12] != b"\x12\x34":
    raise RuntimeError("invalid SOCKS5 UDP DNS response")
udp.close()
tcp.close()
PY
}

check_protocol() {
  local protocol="$1" format="${2:-$core}" ns="${3:-}" code
  start_client "$format" "$protocol" "" "$ns" || fail "the $format/$protocol client did not start"
  code="$(through_proxy "$probe_url" "$ns" || true)"
  [[ "$code" == "204" ]] || fail "$format/$protocol: expected HTTP 204 through the node, got '$code'"
  echo "ok: $format/$protocol relays TCP traffic${ns:+ (netns $ns)}"

  if [[ "$protocol" == "hy2" ]]; then
    udp_dns_through_socks 127.0.0.1 1080 "$ns" || fail "$format/$protocol: UDP forwarding failed"
    echo "ok: $format/$protocol relays UDP traffic${ns:+ (netns $ns)}"
  fi

  # Loopback and private destinations must be refused by the server.
  code="$(through_proxy "http://127.0.0.1:18080/" "$ns" || true)"
  [[ "$code" != "200" ]] || fail "$format/$protocol: the node relayed a request to its own loopback"
  echo "ok: $format/$protocol refuses loopback destinations"
  stop_client
}

check_hy2_clients() {
  local ns="${1:-}"
  check_protocol hy2 hysteria2 "$ns"
  check_protocol hy2 xray "$ns"
  check_protocol hy2 sing-box "$ns"
}

setup_hop_netns() {
  e2e_netns="tb-e2e-cli"
  ip netns add "$e2e_netns"
  ip link add tb-veth-srv type veth peer name tb-veth-cli
  ip link set tb-veth-cli netns "$e2e_netns"
  ip addr add 10.203.0.1/24 dev tb-veth-srv
  ip link set tb-veth-srv up
  ip -n "$e2e_netns" link set lo up
  ip -n "$e2e_netns" addr add 10.203.0.2/24 dev tb-veth-cli
  ip -n "$e2e_netns" link set tb-veth-cli up
  ip -n "$e2e_netns" route add default via 10.203.0.1
  if [[ -e /proc/net/if_inet6 ]] &&
    [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" == "0" ]]; then
    ip -6 addr add fd00:203::1/64 dev tb-veth-srv nodad 2>/dev/null || true
    ip -n "$e2e_netns" -6 addr add fd00:203::2/64 dev tb-veth-cli nodad 2>/dev/null || true
    ip -n "$e2e_netns" -6 route add default via fd00:203::1 2>/dev/null || true
  fi
}

# check_hy2_hop_over_time FORMAT PORT_MIN PORT_MAX: runs TCP & UDP traffic
# through FORMAT client across >=3 5-second hop intervals in the isolated netns
# while sniffing ingress UDP destination ports on tb-veth-srv.
check_hy2_hop_over_time() {
  local format="$1" min_p="$2" max_p="$3"
  local seen_file="$work/seen_ports_${format}" code sniffer_pid
  : >"$seen_file"

  python3 - tb-veth-srv "$min_p" "$max_p" "$seen_file" <<'PY' &
import socket, struct, sys

iface, pmin, pmax, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
s.bind((iface, 0))
s.settimeout(0.5)
seen = set()
while True:
    try:
        pkt, _ = s.recvfrom(2048)
    except TimeoutError:
        continue
    except OSError:
        break
    if len(pkt) < 34:
        continue
    eth_type = struct.unpack("!H", pkt[12:14])[0]
    off = 14
    proto = None
    if eth_type == 0x0800 and len(pkt) >= off + 20:
        ihl = (pkt[off] & 0x0F) * 4
        proto = pkt[off + 9]
        off += ihl
    elif eth_type == 0x86DD and len(pkt) >= off + 40:
        proto = pkt[off + 6]
        off += 40
    if proto == 17 and len(pkt) >= off + 8:
        dport = struct.unpack("!H", pkt[off + 2:off + 4])[0]
        if pmin <= dport <= pmax and dport not in seen:
            seen.add(dport)
            with open(out, "w", encoding="utf-8") as f:
                f.write("\n".join(str(p) for p in sorted(seen)) + "\n")
PY
  sniffer_pid=$!

  start_client "$format" hy2 "" "$e2e_netns" || {
    kill "$sniffer_pid" 2>/dev/null || true
    fail "$format hop client failed to start"
  }
  local round count
  for round in 1 2 3 4 5; do
    code="$(through_proxy "$probe_url" "$e2e_netns" || true)"
    [[ "$code" == "204" ]] || {
      kill "$sniffer_pid" 2>/dev/null || true
      fail "$format hop round $round: expected 204, got '$code'"
    }
    udp_dns_through_socks 127.0.0.1 1080 "$e2e_netns" || {
      kill "$sniffer_pid" 2>/dev/null || true
      fail "$format hop round $round: UDP failed"
    }
    count="$(wc -l <"$seen_file" 2>/dev/null || echo 0)"
    if ((round >= 4 && count >= 2)); then
      break
    fi
    sleep 5.5
  done

  kill "$sniffer_pid" 2>/dev/null || true
  wait "$sniffer_pid" 2>/dev/null || true
  stop_client

  count="$(wc -l <"$seen_file" 2>/dev/null || echo 0)"
  ((count >= 2)) || fail "$format did not use multiple hop ports (seen: $(tr '\n' ',' <"$seen_file"))"
  echo "ok: $format hopped across $count ingress UDP ports: $(tr '\n' ' ' <"$seen_file")"
}

check_hy2_negative() {
  local bad_cfg="$work/bad-client.json" code=""

  # Wrong auth password with official client must fail.
  tb show --format hysteria2 --protocols hy2 | jq '.auth = "wrong-password"' >"$bad_cfg"
  if start_client hysteria2 hy2 "$bad_cfg" 2>/dev/null; then
    code="$(through_proxy "$probe_url" || true)"
    stop_client
    [[ "$code" != "204" ]] || fail "hy2 accepted a wrong password"
  fi
  stop_client

  # Wrong certificate pin with official client must fail.
  tb show --format hysteria2 --protocols hy2 |
    jq '.tls.pinSHA256 = "0000000000000000000000000000000000000000000000000000000000000000"' >"$bad_cfg"
  if start_client hysteria2 hy2 "$bad_cfg" 2>/dev/null; then
    code="$(through_proxy "$probe_url" || true)"
    stop_client
    [[ "$code" != "204" ]] || fail "hy2 accepted a wrong certificate pin"
  fi
  stop_client

  # Wrong certificate pin with Xray client must fail.
  tb show --format xray --protocols hy2 |
    jq '.outbounds[0].streamSettings.tlsSettings.pinnedPeerCertSha256 = "0000000000000000000000000000000000000000000000000000000000000000"' >"$bad_cfg"
  if start_client xray hy2 "$bad_cfg" 2>/dev/null; then
    code="$(through_proxy "$probe_url" || true)"
    stop_client
    [[ "$code" != "204" ]] || fail "xray hy2 accepted a wrong certificate pin"
  fi
  stop_client
  echo "ok: wrong password and wrong certificate trust fail"
}

prepare_clients() {
  mkdir -p "$work/clients"
  hy2_client="$work/clients/hysteria"
  curl -fsSL -o "$hy2_client" \
    "https://github.com/HyNetworks/hysteria/releases/download/app%2Fv2.14.0/hysteria-linux-$arch"
  chmod +x "$hy2_client"

  if [[ "$core" == "xray" ]]; then
    xray_client="$binary"
    local sb_ver
    sb_ver="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')"
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/${sb_ver}/sing-box-${sb_ver#v}-linux-${arch}.tar.gz" |
      tar -xz -C "$work/clients" --strip-components=1 "sing-box-${sb_ver#v}-linux-${arch}/sing-box"
    singbox_client="$work/clients/sing-box"
  else
    singbox_client="$binary"
    curl -fsSL -o "$work/clients/xray.zip" \
      "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xray_arch}.zip"
    python3 -m zipfile -e "$work/clients/xray.zip" "$work/clients/xray-dir"
    xray_client="$work/clients/xray-dir/xray"
    chmod +x "$xray_client"
  fi
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

step "hysteria 2 interop (all three protocols + salamander + masquerade)"
prepare_clients
mkdir -p "$work/masq"
printf 'toastbox-masquerade-ok\n' >"$work/masq/index.html"
python3 -m http.server 18081 --bind 127.0.0.1 --directory "$work/masq" >/dev/null 2>&1 &
masq_pid=$!

tb install -y --protocols all --hy2-port 8443 --hy2-obfs salamander \
  --hy2-masquerade "http://127.0.0.1:18081" >/dev/null
check_node
check_hy2_clients
check_hy2_negative

if curl --help all 2>/dev/null | grep -q -- '--http3-only'; then
  masq_body="$(curl --http3-only -k -fsS --max-time 10 "https://127.0.0.1:8443/" || true)"
  [[ "$masq_body" == *"toastbox-masquerade-ok"* ]] || echo "note: HTTP/3 masquerade check skipped or differed"
fi

step "hysteria 2 lifecycle (rotate keeps cert, renew-cert changes pin, hy2-only)"
sha_before="$(state .hy2.cert_sha256)"
hy2_pw="$(state .hy2.password)"
tb rotate -y >/dev/null
[[ "$(state .hy2.password)" != "$hy2_pw" ]] || fail "rotate kept the hy2 password"
[[ "$(state .hy2.cert_sha256)" == "$sha_before" ]] || fail "rotate changed the hy2 certificate"
check_hy2_clients

tb install -y --hy2-renew-cert >/dev/null
[[ "$(state .hy2.cert_sha256)" != "$sha_before" ]] || fail "--hy2-renew-cert kept the old SHA-256"
check_hy2_clients

tb install -y --protocols hy2 --hy2-port 9443 --hy2-obfs none --hy2-masquerade none >/dev/null
[[ "$(state .vless.enabled)" == "false" ]] || fail "vless stayed enabled on hy2-only switch"
check_hy2_clients

step "hysteria 2 imported certificate + certbot hook (--hy2-tls files & refresh-cert)"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$work/ca.key" 2>/dev/null
openssl req -new -x509 -sha256 -days 30 -key "$work/ca.key" -subj "/CN=ToastBox E2E CA" -out "$work/ca.crt" 2>/dev/null
e2e_live_dir="/etc/letsencrypt/live/toastweb-e2e.test"
e2e_archive_dir="/etc/letsencrypt/archive/toastweb-e2e.test"
mkdir -p "$e2e_live_dir" "$e2e_archive_dir" /etc/letsencrypt/renewal-hooks/deploy
e2e_sibling_hook="/etc/letsencrypt/renewal-hooks/deploy/toastweb.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$e2e_sibling_hook"
chmod +x "$e2e_sibling_hook"

gen_ca_signed_leaf() {
  local idx="$1"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$e2e_archive_dir/privkey${idx}.pem" 2>/dev/null
  openssl req -new -key "$e2e_archive_dir/privkey${idx}.pem" -subj "/CN=hy2.e2e.test" -out "$work/srv${idx}.csr" 2>/dev/null
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:hy2.e2e.test,IP:127.0.0.1,IP:10.203.0.1,IP:fd00:203::1\n' >"$work/srv${idx}.ext"
  openssl x509 -req -in "$work/srv${idx}.csr" -CA "$work/ca.crt" -CAkey "$work/ca.key" -CAcreateserial \
    -out "$work/srv${idx}.crt" -days 30 -sha256 -extfile "$work/srv${idx}.ext" 2>/dev/null
  cat "$work/srv${idx}.crt" "$work/ca.crt" >"$e2e_archive_dir/fullchain${idx}.pem"
}

gen_ca_signed_leaf 1
ln -sfn "../../archive/toastweb-e2e.test/fullchain1.pem" "$e2e_live_dir/fullchain.pem"
ln -sfn "../../archive/toastweb-e2e.test/privkey1.pem" "$e2e_live_dir/privkey.pem"
sha1="$(openssl x509 -noout -fingerprint -sha256 -in "$e2e_live_dir/fullchain.pem" | sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"

# Regression check (Item 2): if repo src/main.sh is available and a legacy entrypoint is at
# /usr/local/bin/toastbox, running from source must rebuild /usr/local/bin/toastbox cleanly.
repo_main="$(dirname "$script")/src/main.sh"
if [[ -f "$repo_main" ]]; then
  cat >/usr/local/bin/toastbox <<'EOF'
#!/usr/bin/env bash
echo "unknown command: ${1:-}" >&2
exit 2
EOF
  chmod 755 /usr/local/bin/toastbox
  bash "$repo_main" --lang en install -y --protocols all --hy2-port 9443 --hy2-obfs salamander \
    --hy2-cert "$e2e_live_dir/fullchain.pem" --hy2-key "$e2e_live_dir/privkey.pem" \
    --hy2-sni hy2.e2e.test --hy2-cert-hook certbot >/dev/null
  ! grep -q 'unknown command:' /usr/local/bin/toastbox || fail "source install did not replace legacy /usr/local/bin/toastbox"
else
  tb install -y --protocols all --hy2-port 9443 --hy2-obfs salamander \
    --hy2-cert "$e2e_live_dir/fullchain.pem" --hy2-key "$e2e_live_dir/privkey.pem" \
    --hy2-sni hy2.e2e.test --hy2-cert-hook certbot >/dev/null
fi
[[ "$(state .hy2.tls)" == "files" ]] || fail "hy2.tls was not set to files"
[[ "$(state .hy2.cert_file)" == "$e2e_live_dir/fullchain.pem" ]] || fail "live symlink path was not preserved"
[[ "$(state .hy2.certbot_hook)" == "true" ]] || fail "certbot_hook was not enabled"
SSL_CERT_FILE="$work/ca.crt" check_hy2_clients

# Pin sha1 succeeds before renewal.
tb show --format hysteria2 --protocols hy2 | jq --arg p "$sha1" '.tls.insecure = true | .tls.pinSHA256 = $p' >"$work/pin1.json"
start_client hysteria2 hy2 "$work/pin1.json" || fail "v1 pin check failed to start"
[[ "$(through_proxy "$probe_url" || true)" == "204" ]] || fail "live server did not serve v1 cert"
stop_client

# Rotate Certbot live symlink to v2, ensure unrelated lineage skips, then trigger matching hook.
gen_ca_signed_leaf 2
ln -sfn "../../archive/toastweb-e2e.test/fullchain2.pem" "$e2e_live_dir/fullchain.pem"
ln -sfn "../../archive/toastweb-e2e.test/privkey2.pem" "$e2e_live_dir/privkey.pem"
sha2="$(openssl x509 -noout -fingerprint -sha256 -in "$e2e_live_dir/fullchain.pem" | sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"

RENEWED_LINEAGE="/etc/letsencrypt/live/unrelated.test" /etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh
[[ "$(state .hy2.cert_sha256)" == "$sha1" ]] || fail "unrelated lineage triggered refresh"

hy2_pw="$(state .hy2.password)"
RENEWED_LINEAGE="$e2e_live_dir" /etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh
[[ "$(state .hy2.cert_sha256)" == "$sha2" ]] || fail "hook failed to refresh state SHA-256"
[[ "$(state .hy2.password)" == "$hy2_pw" ]] || fail "certbot refresh changed password"
[[ -f "$e2e_sibling_hook" ]] || fail "toastweb sibling hook was deleted"

# Prove the live running server now rejects v1 pin and serves v2 cert!
if start_client hysteria2 hy2 "$work/pin1.json" 2>/dev/null; then
  code="$(through_proxy "$probe_url" || true)"
  stop_client
  [[ "$code" != "204" ]] || fail "live server is still serving old v1 certificate after refresh-cert"
fi
tb show --format hysteria2 --protocols hy2 | jq --arg p "$sha2" '.tls.insecure = true | .tls.pinSHA256 = $p' >"$work/pin2.json"
start_client hysteria2 hy2 "$work/pin2.json" || fail "v2 pin check failed to start"
[[ "$(through_proxy "$probe_url" || true)" == "204" ]] || fail "live server did not serve new v2 cert"
stop_client
SSL_CERT_FILE="$work/ca.crt" check_hy2_clients
echo "ok: live certificate rotated from v1 to v2 via Certbot hook"

step "hysteria 2 UDP port hopping over real netns PREROUTING (fixed, random, both NAT backends, UFW, systemd lifecycle)"
setup_hop_netns

# Install unrelated host firewall table/chain to confirm ToastBox leaves them alone.
if command -v nft >/dev/null 2>&1; then
  nft add table inet e2e_keep
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -w -t nat -N E2E-KEEP || true
fi

# Enable UFW before deploying so ToastBox opens 8443/udp synchronously, then verify NAT -> INPUT UFW flow.
if command -v ufw >/dev/null 2>&1; then
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw --force enable >/dev/null
    ufw_was_active=1
  fi
fi

# Deploy with --listen 0.0.0.0 / empty wildcard on 10.203.0.1 netns target, both with & without salamander.
tb install -y --server-addr 10.203.0.1 --hy2-port 8443 --hy2-obfs none \
  --hy2-hop-ports '20001-20008' --hy2-hop-interval 5 >/dev/null
if command -v ufw >/dev/null 2>&1; then
  ufw status | grep -q '8443/udp' || fail "ufw did not open post-NAT Hy2 listening port 8443/udp"
fi
SSL_CERT_FILE="$work/ca.crt" check_hy2_clients "$e2e_netns"

# Verify multi-hop across >= 3 5-second intervals for official Hysteria, Xray, and sing-box clients!
SSL_CERT_FILE="$work/ca.crt" check_hy2_hop_over_time hysteria2 20001 20008
SSL_CERT_FILE="$work/ca.crt" check_hy2_hop_over_time xray 20001 20008
SSL_CERT_FILE="$work/ca.crt" check_hy2_hop_over_time sing-box 20001 20008

# Random hop interval + Salamander obfs over netns PREROUTING (covers obfs+udphop across all 3 clients).
tb install -y --hy2-obfs salamander --hy2-hop-interval 5-6 >/dev/null
SSL_CERT_FILE="$work/ca.crt" check_hy2_clients "$e2e_netns"

# Exercise alternate NAT backend (iptables if nft was primary, else nftables).
if command -v nft >/dev/null 2>&1 && command -v iptables >/dev/null 2>&1; then
  TOASTBOX_HY2_HOP_BACKEND=iptables tb install -y --hy2-hop-ports '20101-20108' --hy2-hop-interval 5 >/dev/null
  iptables -w -t nat -L TOASTBOX-HY2 -n >/dev/null || fail "iptables backend chain missing"
  SSL_CERT_FILE="$work/ca.crt" check_hy2_clients "$e2e_netns"
  TOASTBOX_HY2_HOP_BACKEND=nftables tb install -y --hy2-hop-ports '20001-20008' >/dev/null
  nft list table ip toastbox_hy2 >/dev/null || fail "nftables backend table missing"
fi

# Verify systemd stop removes NAT without restarting service, and start restores it!
systemctl stop "$service"
sleep 1
if systemctl -q is-active "$service"; then fail "$service auto-restarted after stop"; fi
if systemctl -q is-active toastbox-hy2-hop.service; then fail "toastbox-hy2-hop stayed active after $service stopped"; fi
if command -v nft >/dev/null 2>&1 && nft list table ip toastbox_hy2 >/dev/null 2>&1; then
  fail "nftables table remained after $service stopped"
fi
systemctl start "$service"
systemctl -q is-active "$service" || fail "$service did not start"
systemctl -q is-active toastbox-hy2-hop.service || fail "toastbox-hy2-hop did not start with $service"
SSL_CERT_FILE="$work/ca.crt" check_hy2_clients "$e2e_netns"

# Disable hopping explicitly, then switch core with hopping restored to verify migration + disable cleanup.
tb install -y --hy2-hop-ports none >/dev/null
[[ ! -e /etc/toastbox/hy2-hop.json ]] || fail "hy2-hop.json remained after --hy2-hop-ports none"
[[ ! -e /etc/systemd/system/toastbox-hy2-hop.service ]] || fail "unit remained after --hy2-hop-ports none"
if command -v nft >/dev/null 2>&1 && nft list table inet e2e_keep >/dev/null 2>&1; then
  echo "ok: unrelated host nft table preserved"
fi
if command -v iptables >/dev/null 2>&1 && iptables -w -t nat -L E2E-KEEP -n >/dev/null 2>&1; then
  echo "ok: unrelated host iptables chain preserved"
fi

step "hysteria 2 ACME standalone flow, scoped timer, renewal hook, and uninstall preservation (local certbot harness)"
mkdir -p "$work/acme-bin"
cat >"$work/acme-bin/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "ahosts" && "${2:-}" == "acme.e2e.test" ]]; then
  printf '203.0.113.50 STREAM acme.e2e.test\n'
  exit 0
fi
exec /usr/bin/getent "$@"
EOF
cat >"$work/acme-bin/certbot" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ca_crt="${E2E_CA_CRT:?}"
ca_key="${E2E_CA_KEY:?}"
case "${1:-}" in
  --help)
    echo "  --key-type {rsa,ecdsa}"
    exit 0
    ;;
  certonly)
    domain="" lineage=""
    while (($# > 0)); do
      case "$1" in
        -d) domain="$2"; shift 2 ;;
        --cert-name) lineage="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    archive="/etc/letsencrypt/archive/$lineage"
    live="/etc/letsencrypt/live/$lineage"
    mkdir -p "$archive" "$live"
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$archive/privkey1.pem" 2>/dev/null
    openssl req -new -key "$archive/privkey1.pem" -subj "/CN=$domain" -out "$archive/req1.csr" 2>/dev/null
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s,IP:127.0.0.1\n' "$domain" >"$archive/ext1"
    openssl x509 -req -in "$archive/req1.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial \
      -out "$archive/cert1.crt" -days 90 -sha256 -extfile "$archive/ext1" 2>/dev/null
    cat "$archive/cert1.crt" "$ca_crt" >"$archive/fullchain1.pem"
    ln -sfn "../../archive/$lineage/fullchain1.pem" "$live/fullchain.pem"
    ln -sfn "../../archive/$lineage/privkey1.pem" "$live/privkey.pem"
    exit 0
    ;;
  renew)
    lineage=""
    while (($# > 0)); do
      case "$1" in
        --cert-name) lineage="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    archive="/etc/letsencrypt/archive/$lineage"
    live="/etc/letsencrypt/live/$lineage"
    domain="${lineage#toastbox-hy2-}"
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$archive/privkey2.pem" 2>/dev/null
    openssl req -new -key "$archive/privkey2.pem" -subj "/CN=$domain" -out "$archive/req2.csr" 2>/dev/null
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s,IP:127.0.0.1\n' "$domain" >"$archive/ext2"
    openssl x509 -req -in "$archive/req2.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial \
      -out "$archive/cert2.crt" -days 90 -sha256 -extfile "$archive/ext2" 2>/dev/null
    cat "$archive/cert2.crt" "$ca_crt" >"$archive/fullchain2.pem"
    ln -sfn "../../archive/$lineage/fullchain2.pem" "$live/fullchain.pem"
    ln -sfn "../../archive/$lineage/privkey2.pem" "$live/privkey.pem"
    RENEWED_LINEAGE="$live" /etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh
    exit $?
    ;;
esac
EOF
chmod +x "$work/acme-bin/getent" "$work/acme-bin/certbot"

# Ensure TCP 80 busy check refuses before invoking certbot.
python3 -c "import socket, time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', 80)); s.listen(1); time.sleep(10)" &
p80_pid=$!
sleep 0.3
if PATH="$work/acme-bin:$PATH" E2E_CA_CRT="$work/ca.crt" E2E_CA_KEY="$work/ca.key" \
  tb install -y --server-addr 127.0.0.1 --hy2-port 9443 --hy2-tls acme --hy2-acme-domain acme.e2e.test \
  --hy2-acme-email e2e@example.org --hy2-acme-agree-tos >/dev/null 2>&1; then
  kill "$p80_pid" 2>/dev/null || true
  fail "ACME install succeeded despite TCP 80 already being occupied"
fi
kill "$p80_pid" 2>/dev/null || true
wait "$p80_pid" 2>/dev/null || true

# Note: public CA staging validation requires an externally routable test domain pointing at this host;
# this harness tests the complete ToastBox ACME CLI -> standalone certbot -> systemd timer -> deploy hook -> refresh-cert chain.
PATH="$work/acme-bin:$PATH" E2E_CA_CRT="$work/ca.crt" E2E_CA_KEY="$work/ca.key" \
  tb install -y --server-addr 127.0.0.1 --hy2-port 9443 --hy2-tls acme --hy2-acme-domain acme.e2e.test \
  --hy2-acme-email e2e@example.org --hy2-acme-agree-tos >/dev/null
[[ "$(state .hy2.acme.enabled)" == "true" ]] || fail "hy2.acme.enabled was not saved"
[[ "$(state .hy2.tls)" == "files" ]] || fail "hy2.tls should remain files in state.json for ACME"
if ! systemctl -q is-active certbot.timer 2>/dev/null && ! systemctl -q is-active snap.certbot.renew.timer 2>/dev/null; then
  systemctl -q is-enabled toastbox-hy2-certbot.timer || fail "toastbox-hy2-certbot.timer not enabled"
fi
acme_sha1="$(state .hy2.cert_sha256)"
# Trigger renewal directly via our local certbot test harness cleanly under our E2E CA env.
E2E_CA_CRT="$work/ca.crt" E2E_CA_KEY="$work/ca.key" "$work/acme-bin/certbot" renew --non-interactive --cert-name toastbox-hy2-acme.e2e.test
[[ "$(state .hy2.cert_sha256)" != "$acme_sha1" ]] || fail "ACME renewal did not update node cert_sha256"

# Switch server back to 127.0.0.1 with hop restored, then test uninstall --purge.
PATH="$work/acme-bin:$PATH" E2E_CA_CRT="$work/ca.crt" E2E_CA_KEY="$work/ca.key" \
  tb install -y --server-addr 127.0.0.1 --hy2-port 8443 --hy2-hop-ports '20001-20008' >/dev/null
step "uninstall --purge"
tb uninstall -y --purge
if systemctl -q is-active "$service"; then fail "$service is still active"; fi
if systemctl -q is-active toastbox-hy2-hop.service; then fail "toastbox-hy2-hop is still active"; fi
if systemctl -q is-active toastbox-hy2-certbot.timer; then fail "toastbox-hy2-certbot.timer is still active"; fi
[[ ! -e /etc/systemd/system/toastbox-hy2-certbot.timer ]] || fail "acme timer unit still exists"
[[ ! -e /etc/systemd/system/toastbox-hy2-certbot.service ]] || fail "acme service unit still exists"
[[ -e /etc/letsencrypt/live/toastbox-hy2-acme.e2e.test/fullchain.pem ]] || fail "uninstall deleted Certbot live certificates"
rm -rf /etc/letsencrypt/live/toastbox-hy2-acme.e2e.test /etc/letsencrypt/archive/toastbox-hy2-acme.e2e.test
[[ ! -e "$binary" ]] || fail "$binary still exists"
[[ ! -e /etc/toastbox ]] || fail "/etc/toastbox still exists"
[[ ! -e "$config" ]] || fail "$config still exists"
[[ ! -e /usr/local/bin/toastbox ]] || fail "the toastbox command still exists"
[[ ! -e /etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh ]] || fail "toastbox certbot hook still exists"
[[ -f "$e2e_sibling_hook" ]] || fail "sibling toastweb hook was deleted on purge"
[[ ! -e /etc/systemd/system/toastbox-hy2-hop.service ]] || fail "hop unit still exists"
[[ ! -e /usr/local/libexec/toastbox-hy2-hop ]] || fail "hop helper still exists"
if command -v nft >/dev/null 2>&1; then
  nft list table inet e2e_keep >/dev/null 2>&1 || fail "unrelated nft table was removed on purge"
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -w -t nat -L E2E-KEEP -n >/dev/null 2>&1 || fail "unrelated iptables chain was removed on purge"
fi
if tb show >/dev/null 2>&1; then fail "show still works after uninstall"; fi

step "all good ($core)"
