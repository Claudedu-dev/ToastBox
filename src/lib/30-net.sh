# shellcheck shell=bash
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
