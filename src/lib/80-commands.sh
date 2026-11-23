# shellcheck shell=bash
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
  OPT_XHTTP_TLS=""
  OPT_XHTTP_LISTEN=""
  OPT_XHTTP_PORT=""
  OPT_XHTTP_PUBLIC_PORT=""
  OPT_XHTTP_CONNECT_ADDR=""
  OPT_XHTTP_HOST=""
  OPT_XHTTP_PATH=""
  OPT_XHTTP_MODE=""
  OPT_XHTTP_CLIENT_MODE=""
  OPT_XHTTP_ALPN=""
  OPT_XHTTP_CERT=""
  OPT_XHTTP_KEY=""
  OPT_XHTTP_CERT_HOOK=""
  OPT_XHTTP_WS_KEEPALIVE=""
  OPT_XHTTP_WS_PORT=""
  OPT_XHTTP_WS_PUBLIC_PORT=""
  OPT_XHTTP_WS_PATH=""
  OPT_XHTTP_WS_HEARTBEAT=""
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
      --xhttp-tls) var=OPT_XHTTP_TLS ;;
      --xhttp-listen) var=OPT_XHTTP_LISTEN ;;
      --xhttp-port) var=OPT_XHTTP_PORT ;;
      --xhttp-public-port) var=OPT_XHTTP_PUBLIC_PORT ;;
      --xhttp-connect-addr) var=OPT_XHTTP_CONNECT_ADDR ;;
      --xhttp-host) var=OPT_XHTTP_HOST ;;
      --xhttp-path) var=OPT_XHTTP_PATH ;;
      --xhttp-mode) var=OPT_XHTTP_MODE ;;
      --xhttp-client-mode) var=OPT_XHTTP_CLIENT_MODE ;;
      --xhttp-alpn) var=OPT_XHTTP_ALPN ;;
      --xhttp-cert) var=OPT_XHTTP_CERT ;;
      --xhttp-key) var=OPT_XHTTP_KEY ;;
      --xhttp-cert-hook) var=OPT_XHTTP_CERT_HOOK ;;
      --xhttp-ws-port) var=OPT_XHTTP_WS_PORT ;;
      --xhttp-ws-public-port) var=OPT_XHTTP_WS_PUBLIC_PORT ;;
      --xhttp-ws-path) var=OPT_XHTTP_WS_PATH ;;
      --xhttp-ws-heartbeat) var=OPT_XHTTP_WS_HEARTBEAT ;;
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
      if [[ "$var" == "OPT_XHTTP_CONNECT_ADDR" && -z "$1" ]]; then
        OPT_XHTTP_CONNECT_ADDR="none"
        shift
        continue
      fi
      if [[ -z "$1" ]] && [[ "$var" == OPT_TCP_* || "$var" == OPT_HY2_* || "$var" == OPT_XHTTP_* ]]; then
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
      --xhttp-ws-keepalive) OPT_XHTTP_WS_KEEPALIVE=1 ;;
      --no-xhttp-ws-keepalive) OPT_XHTTP_WS_KEEPALIVE=0 ;;
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
PARSED_XHTTP=0

# parse_protocols "vless,ss,hy2,xhttp": result in PARSED_*.
parse_protocols() {
  local item
  local -a items=()
  PARSED_VLESS=0
  PARSED_SS=0
  PARSED_HY2=0
  PARSED_XHTTP=0
  IFS=',+ ' read -r -a items <<<"$1"
  ((${#items[@]} > 0)) || return 1
  for item in "${items[@]}"; do
    case "$item" in
      1 | both) PARSED_VLESS=1 PARSED_SS=1 ;;
      2 | vless | reality | vless-reality) PARSED_VLESS=1 ;;
      3 | ss | ss2022 | shadowsocks | shadowsocks-2022) PARSED_SS=1 ;;
      4 | hy2 | hysteria2 | hysteria) PARSED_HY2=1 ;;
      5 | all) PARSED_VLESS=1 PARSED_SS=1 PARSED_HY2=1 ;;
      6 | xhttp | vless-xhttp) PARSED_XHTTP=1 ;;
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
  [[ "$PARSED_XHTTP" == "1" ]] && protos+=(xhttp)
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
  if valid_domain "$host"; then
    printf '%s' "${host,,}"
  elif valid_ipv4 "$host" || valid_ipv6 "$host"; then
    printf '%s' "$host"
  else
    return 1
  fi
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
    text | json | links | xray | mihomo | nginx) printf '%s' "$1" ;;
    sing-box | singbox) printf 'sing-box' ;;
    hysteria2 | hy2) printf 'hysteria2' ;;
    clash | clash-meta) printf 'mihomo' ;;
    *) return 1 ;;
  esac
}

norm_xhttp_tls() {
  case "$1" in
    1 | none | off) printf 'none' ;;
    2 | files | file | import) printf 'files' ;;
    *) return 1 ;;
  esac
}

norm_xhttp_path() {
  local p="$1"
  [[ -n "$p" ]] || return 1
  [[ "$p" == /* ]] || p="/$p"
  while [[ "$p" == */ && "$p" != "/" ]]; do
    p="${p%/}"
  done
  valid_xhttp_path "$p" && printf '%s' "$p"
}

norm_xhttp_connect_addr() {
  case "$1" in
    none | off) printf 'none' ;;
    *) norm_host "$1" ;;
  esac
}

norm_xhttp_mode() {
  in_list "$1" "${TB_XHTTP_MODES[@]}" && printf '%s' "$1"
}

norm_xhttp_alpn() {
  in_list "$1" "${TB_XHTTP_ALPNS[@]}" && printf '%s' "$1"
}

norm_xhttp_ws_heartbeat() {
  local v
  v="$(norm_socket_int "$1" 3600)" || return 1
  ((v >= 1)) && printf '%d' "$v"
}

norm_yes_no() {
  case "${1,,}" in
    y | yes | 1 | true) printf '1' ;;
    n | no | 0 | false) printf '0' ;;
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
  normalize_opt OPT_XHTTP_TLS norm_xhttp_tls --xhttp-tls
  normalize_opt OPT_XHTTP_LISTEN norm_listen --xhttp-listen
  normalize_opt OPT_XHTTP_PORT norm_port --xhttp-port
  normalize_opt OPT_XHTTP_PUBLIC_PORT norm_port --xhttp-public-port
  normalize_opt OPT_XHTTP_CONNECT_ADDR norm_xhttp_connect_addr --xhttp-connect-addr
  normalize_opt OPT_XHTTP_HOST norm_domain --xhttp-host
  normalize_opt OPT_XHTTP_PATH norm_xhttp_path --xhttp-path
  normalize_opt OPT_XHTTP_MODE norm_xhttp_mode --xhttp-mode
  normalize_opt OPT_XHTTP_CLIENT_MODE norm_xhttp_mode --xhttp-client-mode
  normalize_opt OPT_XHTTP_ALPN norm_xhttp_alpn --xhttp-alpn
  normalize_opt OPT_XHTTP_CERT_HOOK norm_hy2_cert_hook --xhttp-cert-hook
  normalize_opt OPT_XHTTP_WS_PORT norm_port --xhttp-ws-port
  normalize_opt OPT_XHTTP_WS_PUBLIC_PORT norm_port --xhttp-ws-public-port
  normalize_opt OPT_XHTTP_WS_PATH norm_xhttp_path --xhttp-ws-path
  normalize_opt OPT_XHTTP_WS_HEARTBEAT norm_xhttp_ws_heartbeat --xhttp-ws-heartbeat
  if [[ -n "$OPT_XHTTP_TLS$OPT_XHTTP_LISTEN$OPT_XHTTP_PORT$OPT_XHTTP_PUBLIC_PORT$OPT_XHTTP_CONNECT_ADDR$OPT_XHTTP_HOST$OPT_XHTTP_PATH$OPT_XHTTP_MODE$OPT_XHTTP_CLIENT_MODE$OPT_XHTTP_ALPN$OPT_XHTTP_CERT$OPT_XHTTP_KEY$OPT_XHTTP_CERT_HOOK$OPT_XHTTP_WS_KEEPALIVE$OPT_XHTTP_WS_PORT$OPT_XHTTP_WS_PUBLIC_PORT$OPT_XHTTP_WS_PATH$OPT_XHTTP_WS_HEARTBEAT" ]]; then
    [[ "$OPT_COMMAND" == "install" ]] || die err_xhttp_command
  fi
  if [[ "$OPT_XHTTP_TLS" == "none" && -n "$OPT_XHTTP_CERT$OPT_XHTTP_KEY" ]]; then
    die err_xhttp_cert_with_none
  fi
  if [[ "$OPT_XHTTP_CERT_HOOK" == "certbot" && "$OPT_XHTTP_TLS" == "none" ]]; then
    die err_xhttp_hook_not_none
  fi
  if [[ -n "$OPT_XHTTP_CERT" && -z "$OPT_XHTTP_KEY" ]] || [[ -z "$OPT_XHTTP_CERT" && -n "$OPT_XHTTP_KEY" ]]; then
    die err_xhttp_cert_pair_required
  fi
  if [[ "$OPT_XHTTP_TLS" == "none" && -n "$OPT_XHTTP_LISTEN" ]] && ! hy2_hop_is_loopback "$OPT_XHTTP_LISTEN"; then
    die err_xhttp_none_loopback "$OPT_XHTTP_LISTEN"
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
    if [[ -n "$OPT_CORE$OPT_PROTOCOLS$OPT_SERVER_ADDR$OPT_NAME$OPT_LISTEN$OPT_VLESS_PORT$OPT_REALITY_SNI$OPT_REALITY_TARGET$OPT_SS_PORT$OPT_SS_METHOD$OPT_SS_NETWORK$OPT_XHTTP_TLS$OPT_XHTTP_LISTEN$OPT_XHTTP_PORT$OPT_XHTTP_PUBLIC_PORT$OPT_XHTTP_CONNECT_ADDR$OPT_XHTTP_HOST$OPT_XHTTP_PATH$OPT_XHTTP_MODE$OPT_XHTTP_CLIENT_MODE$OPT_XHTTP_ALPN$OPT_XHTTP_CERT$OPT_XHTTP_KEY$OPT_XHTTP_CERT_HOOK$OPT_XHTTP_WS_KEEPALIVE$OPT_XHTTP_WS_PORT$OPT_XHTTP_WS_PUBLIC_PORT$OPT_XHTTP_WS_PATH$OPT_XHTTP_WS_HEARTBEAT$OPT_BLOCK_BT$OPT_ALLOW_PRIVATE$OPT_CORE_VERSION$OPT_FORMAT" ||
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
    [[ "$CFG_XHTTP" == "1" ]] && active+=(xhttp)
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
  CFG_XHTTP="$PARSED_XHTTP"
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

xhttp_ws_port_node_conflict() {
  local p="$1"
  [[ "$p" == "$CFG_XHTTP_PORT" ]] && return 0
  [[ "$CFG_VLESS" == "1" && "$p" == "$CFG_VLESS_PORT" ]] && return 0
  [[ "$CFG_SS" == "1" && "$CFG_SS_NETWORK" != "udp" && "$p" == "$CFG_SS_PORT" ]] && return 0
  return 1
}

resolve_xhttp() {
  local prev_tls="$CFG_XHTTP_TLS" prev_ws="$CFG_XHTTP_WS"
  local old_port="$CFG_XHTTP_PORT" old_public_port="$CFG_XHTTP_PUBLIC_PORT"
  local old_ws_port="$CFG_XHTTP_WS_PORT" default_host="$CFG_XHTTP_HOST" default_port=""
  local cert_file="" key_file="" abs_cert="" abs_key="" default_ws_port="" ca_ans="" ws_def="no"

  check_xhttp_core_support "$CFG_CORE"

  if [[ -n "$OPT_XHTTP_TLS" ]]; then
    CFG_XHTTP_TLS="$OPT_XHTTP_TLS"
  elif [[ -n "$OPT_XHTTP_CERT" ]]; then
    CFG_XHTTP_TLS="files"
  else
    ask_valid CFG_XHTTP_TLS "${CFG_XHTTP_TLS:-none}" norm_xhttp_tls prompt_xhttp_tls
  fi

  if [[ -z "$default_host" ]] && valid_domain "$CFG_SERVER_ADDR"; then
    default_host="$CFG_SERVER_ADDR"
  fi
  if [[ -n "$OPT_XHTTP_HOST" ]]; then
    CFG_XHTTP_HOST="$OPT_XHTTP_HOST"
  elif [[ "$TB_INTERACTIVE" == "1" ]]; then
    ask_valid CFG_XHTTP_HOST "$default_host" norm_domain prompt_xhttp_host
  elif [[ -n "$default_host" ]]; then
    CFG_XHTTP_HOST="$default_host"
  else
    die err_xhttp_host_required
  fi

  if [[ "$CFG_XHTTP_TLS" == "none" ]]; then
    if [[ -n "$OPT_XHTTP_LISTEN" ]]; then
      hy2_hop_is_loopback "$OPT_XHTTP_LISTEN" || die err_xhttp_none_loopback "$OPT_XHTTP_LISTEN"
      CFG_XHTTP_LISTEN="$OPT_XHTTP_LISTEN"
    elif [[ "$prev_tls" != "none" ]] || ! hy2_hop_is_loopback "$CFG_XHTTP_LISTEN"; then
      CFG_XHTTP_LISTEN="127.0.0.1"
    fi

    default_port="$CFG_XHTTP_PORT"
    if [[ "$prev_tls" != "none" || -z "$default_port" ]]; then
      default_port="$TB_XHTTP_DEFAULT_PORT"
    fi
    if [[ -n "$OPT_XHTTP_PORT" ]]; then
      CFG_XHTTP_PORT="$OPT_XHTTP_PORT"
    else
      ask_valid CFG_XHTTP_PORT "$default_port" norm_port prompt_xhttp_port
    fi

    if [[ -n "$OPT_XHTTP_PUBLIC_PORT" ]]; then
      CFG_XHTTP_PUBLIC_PORT="$OPT_XHTTP_PUBLIC_PORT"
    elif [[ "$prev_tls" != "none" || -z "$CFG_XHTTP_PUBLIC_PORT" ]]; then
      CFG_XHTTP_PUBLIC_PORT="$TB_XHTTP_DEFAULT_PUBLIC_PORT"
    fi
  else
    if [[ -n "$OPT_XHTTP_LISTEN" ]]; then
      CFG_XHTTP_LISTEN="$OPT_XHTTP_LISTEN"
    elif [[ "$prev_tls" == "none" ]] && hy2_hop_is_loopback "$CFG_XHTTP_LISTEN"; then
      CFG_XHTTP_LISTEN=""
    fi

    default_port="$CFG_XHTTP_PORT"
    if [[ "$prev_tls" != "files" || -z "$default_port" ]]; then
      default_port="$TB_XHTTP_DEFAULT_PUBLIC_PORT"
    fi
    if [[ -n "$OPT_XHTTP_PORT" ]]; then
      CFG_XHTTP_PORT="$OPT_XHTTP_PORT"
    else
      ask_valid CFG_XHTTP_PORT "$default_port" norm_port prompt_xhttp_port
    fi

    if [[ -n "$OPT_XHTTP_PUBLIC_PORT" ]]; then
      CFG_XHTTP_PUBLIC_PORT="$OPT_XHTTP_PUBLIC_PORT"
    elif [[ "$prev_tls" != "files" || -z "$CFG_XHTTP_PUBLIC_PORT" ]] ||
      { [[ -n "$OPT_XHTTP_PORT" && "$CFG_XHTTP_PUBLIC_PORT" == "$old_port" ]]; }; then
      CFG_XHTTP_PUBLIC_PORT="$CFG_XHTTP_PORT"
    fi
  fi

  if [[ "$OPT_XHTTP_CONNECT_ADDR" == "none" ]]; then
    CFG_XHTTP_CONNECT_ADDR=""
  elif [[ -n "$OPT_XHTTP_CONNECT_ADDR" ]]; then
    CFG_XHTTP_CONNECT_ADDR="$OPT_XHTTP_CONNECT_ADDR"
  elif [[ "$TB_INTERACTIVE" == "1" ]]; then
    ask_valid ca_ans "${CFG_XHTTP_CONNECT_ADDR:-none}" norm_xhttp_connect_addr prompt_xhttp_connect_addr
    if [[ "$ca_ans" == "none" ]]; then
      CFG_XHTTP_CONNECT_ADDR=""
    else
      CFG_XHTTP_CONNECT_ADDR="$ca_ans"
    fi
  fi
  [[ "$CFG_XHTTP_CONNECT_ADDR" == "$CFG_XHTTP_HOST" ]] && CFG_XHTTP_CONNECT_ADDR=""

  [[ -n "$OPT_XHTTP_PATH" ]] && CFG_XHTTP_PATH="$OPT_XHTTP_PATH"
  CFG_XHTTP_MODE="${OPT_XHTTP_MODE:-${CFG_XHTTP_MODE:-auto}}"
  CFG_XHTTP_CLIENT_MODE="${OPT_XHTTP_CLIENT_MODE:-${CFG_XHTTP_CLIENT_MODE:-packet-up}}"
  CFG_XHTTP_ALPN="${OPT_XHTTP_ALPN:-${CFG_XHTTP_ALPN:-h2}}"
  if [[ "$CFG_XHTTP_ALPN" == "h3" ]]; then
    log_warn warn_xhttp_alpn_h3
  fi

  if [[ "$CFG_XHTTP_TLS" == "files" ]]; then
    if [[ -n "$OPT_XHTTP_CERT" ]]; then
      cert_file="$OPT_XHTTP_CERT"
      key_file="$OPT_XHTTP_KEY"
    elif [[ "$prev_tls" != "files" || -z "$CFG_XHTTP_CERT" || -z "$CFG_XHTTP_KEY" ]]; then
      if [[ "$TB_INTERACTIVE" == "1" ]]; then
        ask_valid cert_file "" norm_readable_file prompt_xhttp_cert
        ask_valid key_file "" norm_readable_file prompt_xhttp_key
      else
        die err_xhttp_files_required
      fi
    fi

    if [[ -n "$cert_file" ]]; then
      tls_validate_pair_files "$cert_file" "$key_file" || die err_xhttp_cert_pair "$cert_file" "$key_file"
      abs_cert="$(tls_abs_path "$cert_file")" || die err_xhttp_cert_pair "$cert_file" "$key_file"
      abs_key="$(tls_abs_path "$key_file")" || die err_xhttp_cert_pair "$cert_file" "$key_file"
      tls_cert_matches_name "$cert_file" "$CFG_XHTTP_HOST" || die err_xhttp_cert_host_mismatch "$CFG_XHTTP_HOST"
      CFG_XHTTP_CERT="$TLS_CERT_PEM"
      CFG_XHTTP_KEY="$TLS_KEY_PEM"
      CFG_XHTTP_CERT_SHA256="$TLS_CERT_SHA256"
      CFG_XHTTP_CERT_FILE="$abs_cert"
      CFG_XHTTP_KEY_FILE="$abs_key"
    else
      tls_validate_pem_pair "$CFG_XHTTP_CERT" "$CFG_XHTTP_KEY" || die err_xhttp_tls_invalid
      CFG_XHTTP_CERT_SHA256="$TLS_CERT_SHA256"
      tls_pem_matches_name "$CFG_XHTTP_CERT" "$CFG_XHTTP_HOST" || die err_xhttp_cert_host_mismatch "$CFG_XHTTP_HOST"
    fi

    case "$OPT_XHTTP_CERT_HOOK" in
      certbot) CFG_XHTTP_CERTBOT_HOOK=1 ;;
      none) CFG_XHTTP_CERTBOT_HOOK=0 ;;
    esac
    if [[ "$CFG_XHTTP_CERTBOT_HOOK" == "1" ]]; then
      if [[ -z "$CFG_XHTTP_CERT_FILE" || -z "$CFG_XHTTP_KEY_FILE" ]]; then
        die err_xhttp_cert_sources_missing
      fi
      certbot_lineage_from_pair "$CFG_XHTTP_CERT_FILE" "$CFG_XHTTP_KEY_FILE" >/dev/null ||
        die err_hy2_hook_certbot_paths "$(certbot_live_root)"
    fi
  else
    if [[ "$OPT_XHTTP_CERT_HOOK" == "certbot" ]]; then
      die err_xhttp_hook_not_none
    fi
    CFG_XHTTP_CERT=""
    CFG_XHTTP_KEY=""
    CFG_XHTTP_CERT_SHA256=""
    CFG_XHTTP_CERT_FILE=""
    CFG_XHTTP_KEY_FILE=""
    CFG_XHTTP_CERTBOT_HOOK=0
  fi

  if [[ -n "$OPT_XHTTP_WS_KEEPALIVE" ]]; then
    CFG_XHTTP_WS="$OPT_XHTTP_WS_KEEPALIVE"
  elif [[ "$TB_INTERACTIVE" == "1" ]]; then
    [[ "$CFG_XHTTP_WS" == "1" ]] && ws_def="yes"
    ask_valid CFG_XHTTP_WS "$ws_def" norm_yes_no prompt_xhttp_ws_keepalive
  fi

  if [[ "$CFG_XHTTP_WS" != "1" ]]; then
    if [[ -n "$OPT_XHTTP_WS_PORT$OPT_XHTTP_WS_PUBLIC_PORT$OPT_XHTTP_WS_PATH$OPT_XHTTP_WS_HEARTBEAT" ]]; then
      die err_xhttp_ws_not_enabled
    fi
    CFG_XHTTP_WS_PORT=""
    CFG_XHTTP_WS_PUBLIC_PORT=""
    CFG_XHTTP_WS_PATH=""
    CFG_XHTTP_WS_HEARTBEAT="$TB_XHTTP_DEFAULT_WS_HEARTBEAT"
    return 0
  fi

  if [[ "$CFG_XHTTP_TLS" == "none" ]]; then
    if [[ -n "$OPT_XHTTP_WS_PORT" ]]; then
      CFG_XHTTP_WS_PORT="$OPT_XHTTP_WS_PORT"
    elif [[ "$prev_tls" != "none" || "$prev_ws" != "1" || -z "$CFG_XHTTP_WS_PORT" ]] ||
      [[ "$CFG_XHTTP_WS_PORT" == "$TB_XHTTP_DEFAULT_WS_PORT" && "$CFG_XHTTP_WS_PORT" == "$CFG_XHTTP_PORT" ]]; then
      default_ws_port="$TB_XHTTP_DEFAULT_WS_PORT"
      if [[ "$default_ws_port" == "$CFG_XHTTP_PORT" ]]; then
        default_ws_port=$((CFG_XHTTP_PORT + 1))
        log_warn warn_xhttp_ws_port_conflict "$TB_XHTTP_DEFAULT_WS_PORT" "$default_ws_port"
      fi
      CFG_XHTTP_WS_PORT="$default_ws_port"
    fi
    if [[ -n "$OPT_XHTTP_WS_PUBLIC_PORT" ]]; then
      CFG_XHTTP_WS_PUBLIC_PORT="$OPT_XHTTP_WS_PUBLIC_PORT"
    elif [[ "$prev_tls" != "none" || "$prev_ws" != "1" || -z "$CFG_XHTTP_WS_PUBLIC_PORT" ]] ||
      { [[ -n "$OPT_XHTTP_PUBLIC_PORT" && "$CFG_XHTTP_WS_PUBLIC_PORT" == "$old_public_port" ]]; }; then
      CFG_XHTTP_WS_PUBLIC_PORT="$CFG_XHTTP_PUBLIC_PORT"
    fi
  else
    if [[ -n "$OPT_XHTTP_WS_PORT" ]]; then
      CFG_XHTTP_WS_PORT="$OPT_XHTTP_WS_PORT"
    elif [[ "$prev_tls" != "files" || "$prev_ws" != "1" || -z "$CFG_XHTTP_WS_PORT" ]] ||
      { [[ "$CFG_XHTTP_WS_PORT" == "$TB_XHTTP_DEFAULT_WS_FILES_PORT" ]] && xhttp_ws_port_node_conflict "$CFG_XHTTP_WS_PORT"; }; then
      default_ws_port="$TB_XHTTP_DEFAULT_WS_FILES_PORT"
      if xhttp_ws_port_node_conflict "$default_ws_port"; then
        default_ws_port=2053
        log_warn warn_xhttp_ws_port_conflict "$TB_XHTTP_DEFAULT_WS_FILES_PORT" "$default_ws_port"
      elif port_conflict tcp "$default_ws_port" "$(core_call process)" >/dev/null 2>&1; then
        default_ws_port=2053
        log_warn warn_xhttp_ws_port_busy "$TB_XHTTP_DEFAULT_WS_FILES_PORT" "$default_ws_port"
      fi
      CFG_XHTTP_WS_PORT="$default_ws_port"
    fi
    if [[ -n "$OPT_XHTTP_WS_PUBLIC_PORT" ]]; then
      CFG_XHTTP_WS_PUBLIC_PORT="$OPT_XHTTP_WS_PUBLIC_PORT"
    elif [[ "$prev_tls" != "files" || "$prev_ws" != "1" || -z "$CFG_XHTTP_WS_PUBLIC_PORT" ]] ||
      { [[ "$CFG_XHTTP_WS_PORT" != "$old_ws_port" && "$CFG_XHTTP_WS_PUBLIC_PORT" == "$old_ws_port" ]]; }; then
      CFG_XHTTP_WS_PUBLIC_PORT="$CFG_XHTTP_WS_PORT"
    fi
  fi

  [[ -n "$OPT_XHTTP_WS_PATH" ]] && CFG_XHTTP_WS_PATH="$OPT_XHTTP_WS_PATH"
  if [[ -n "$CFG_XHTTP_PATH" && -n "$CFG_XHTTP_WS_PATH" ]] &&
    xhttp_paths_conflict "$CFG_XHTTP_PATH" "$CFG_XHTTP_WS_PATH"; then
    die err_xhttp_path_conflict "$CFG_XHTTP_PATH" "$CFG_XHTTP_WS_PATH"
  fi
  CFG_XHTTP_WS_HEARTBEAT="${OPT_XHTTP_WS_HEARTBEAT:-${CFG_XHTTP_WS_HEARTBEAT:-$TB_XHTTP_DEFAULT_WS_HEARTBEAT}}"
  if ((10#$CFG_XHTTP_WS_HEARTBEAT > 60)); then
    log_warn warn_xhttp_ws_heartbeat_cf "$CFG_XHTTP_WS_HEARTBEAT"
  fi
}

resolve_params() {
  local -a tcp_ports=() seen_ports=()
  local p
  resolve_core
  resolve_sockopt
  resolve_protocols

  [[ -n "$OPT_NAME" ]] && CFG_NODE_NAME="$OPT_NAME"
  [[ -n "$CFG_NODE_NAME" ]] || CFG_NODE_NAME="ToastBox"
  [[ -n "$OPT_LISTEN" ]] && CFG_LISTEN="$OPT_LISTEN"
  [[ -n "$OPT_BLOCK_BT" ]] && CFG_BLOCK_BT="$OPT_BLOCK_BT"
  [[ -n "$OPT_ALLOW_PRIVATE" ]] && CFG_ALLOW_PRIVATE="$OPT_ALLOW_PRIVATE"

  if [[ "$CFG_VLESS" == "1" || "$CFG_SS" == "1" || "$CFG_HY2" == "1" ]]; then
    resolve_server_addr
  elif [[ -n "$OPT_SERVER_ADDR" ]]; then
    CFG_SERVER_ADDR="$OPT_SERVER_ADDR"
  fi

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
  if [[ "$CFG_XHTTP" == "1" ]]; then
    resolve_xhttp
    if [[ -z "$CFG_SERVER_ADDR" ]] ||
      [[ "$CFG_VLESS$CFG_SS$CFG_HY2" == "000" && -z "$OPT_SERVER_ADDR" ]]; then
      CFG_SERVER_ADDR="$CFG_XHTTP_HOST"
    fi
  else
    if [[ -n "$OPT_XHTTP_TLS$OPT_XHTTP_LISTEN$OPT_XHTTP_PORT$OPT_XHTTP_PUBLIC_PORT$OPT_XHTTP_CONNECT_ADDR$OPT_XHTTP_HOST$OPT_XHTTP_PATH$OPT_XHTTP_MODE$OPT_XHTTP_CLIENT_MODE$OPT_XHTTP_ALPN$OPT_XHTTP_CERT$OPT_XHTTP_KEY$OPT_XHTTP_CERT_HOOK$OPT_XHTTP_WS_KEEPALIVE$OPT_XHTTP_WS_PORT$OPT_XHTTP_WS_PUBLIC_PORT$OPT_XHTTP_WS_PATH$OPT_XHTTP_WS_HEARTBEAT" ]]; then
      die err_xhttp_not_enabled
    fi
    CFG_XHTTP_CERT=""
    CFG_XHTTP_KEY=""
    CFG_XHTTP_CERT_SHA256=""
    CFG_XHTTP_CERT_FILE=""
    CFG_XHTTP_KEY_FILE=""
    CFG_XHTTP_CERTBOT_HOOK=0
    CFG_XHTTP_WS=0
    CFG_XHTTP_WS_PORT=""
    CFG_XHTTP_WS_PUBLIC_PORT=""
    CFG_XHTTP_WS_PATH=""
    CFG_XHTTP_WS_HEARTBEAT="$TB_XHTTP_DEFAULT_WS_HEARTBEAT"
  fi

  [[ "$CFG_VLESS" == "1" ]] && tcp_ports+=("$CFG_VLESS_PORT")
  [[ "$CFG_SS" == "1" && "$CFG_SS_NETWORK" != "udp" ]] && tcp_ports+=("$CFG_SS_PORT")
  if [[ "$CFG_XHTTP" == "1" ]]; then
    tcp_ports+=("$CFG_XHTTP_PORT")
    [[ "$CFG_XHTTP_WS" == "1" ]] && tcp_ports+=("$CFG_XHTTP_WS_PORT")
  fi
  for p in "${tcp_ports[@]}"; do
    if in_list "$p" "${seen_ports[@]}"; then
      die err_port_same "$p"
    fi
    seen_ports+=("$p")
  done

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
    if in_list "80" "${tcp_ports[@]}"; then
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
  if [[ "$CFG_XHTTP" == "1" ]]; then
    printf '  VLESS-XHTTP: TLS %s, %s:%s/tcp -> %s:%s, host %s, mode %s/%s, alpn %s\n' \
      "$CFG_XHTTP_TLS" "${CFG_XHTTP_LISTEN:-*}" "$CFG_XHTTP_PORT" \
      "$(uri_host "$(xhttp_dial_addr)")" "$CFG_XHTTP_PUBLIC_PORT" \
      "$CFG_XHTTP_HOST" "$CFG_XHTTP_MODE" "$CFG_XHTTP_CLIENT_MODE" "$CFG_XHTTP_ALPN" >&2
    if [[ "$CFG_XHTTP_CERTBOT_HOOK" == "1" ]]; then
      printf '  %s: certbot (%s)\n' "$(msg label_cert_hook)" "$CFG_XHTTP_CERT_FILE" >&2
    fi
    if [[ "$CFG_XHTTP_WS" == "1" ]]; then
      printf '  VLESS-WS-KeepAlive: %s:%s/tcp -> :%s, heartbeat %ss\n' \
        "${CFG_XHTTP_LISTEN:-*}" "$CFG_XHTTP_WS_PORT" "$CFG_XHTTP_WS_PUBLIC_PORT" \
        "$CFG_XHTTP_WS_HEARTBEAT" >&2
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
  if [[ "$CFG_XHTTP" == "1" ]]; then
    if procs="$(port_conflict tcp "$CFG_XHTTP_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_XHTTP_PORT/tcp" "$procs"
    fi
    if [[ "$CFG_XHTTP_WS" == "1" ]] && procs="$(port_conflict tcp "$CFG_XHTTP_WS_PORT" "${own[@]}")"; then
      die err_port_in_use "$CFG_XHTTP_WS_PORT/tcp" "$procs"
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
  check_xhttp_core_support "$CFG_CORE"
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
  check_xhttp_core_support "$CFG_CORE"

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
  if [[ "$CFG_XHTTP" == "1" && "$CFG_XHTTP_TLS" == "files" ]]; then
    rules+=("$CFG_XHTTP_PORT/tcp")
    [[ "$CFG_XHTTP_WS" == "1" ]] && rules+=("$CFG_XHTTP_WS_PORT/tcp")
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
  if [[ ("$CFG_HY2" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1") ||
    ("$CFG_XHTTP" == "1" && "$CFG_XHTTP_CERTBOT_HOOK" == "1") ]]; then
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

  if [[ ("$CFG_HY2" == "1" && "$CFG_HY2_CERTBOT_HOOK" == "1") ||
    ("$CFG_XHTTP" == "1" && "$CFG_XHTTP_CERTBOT_HOOK" == "1") ]]; then
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
  check_xhttp_core_support "$CFG_CORE"
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
  local hy2_files=0 xhttp_files=0 changed=0 had_error=0
  local renewed="${RENEWED_LINEAGE:-}" expected_dir=""
  local verify_name old_hy2_cert old_hy2_key old_hy2_sha
  local old_xhttp_cert old_xhttp_key old_xhttp_sha

  require_root
  require_systemd
  tb_mktemp_dir
  tb_acquire_lock
  require_state

  [[ "$CFG_HY2" == "1" && "$CFG_HY2_TLS" == "files" ]] && hy2_files=1
  [[ "$CFG_XHTTP" == "1" && "$CFG_XHTTP_TLS" == "files" ]] && xhttp_files=1

  if [[ "$hy2_files" != "1" && "$xhttp_files" != "1" ]]; then
    if [[ "$CFG_HY2" != "1" && "$CFG_XHTTP" != "1" ]]; then
      die err_refresh_requires_protocol
    fi
    die err_refresh_requires_files
  fi

  if [[ -n "$renewed" ]]; then
    renewed="${renewed%/}"
    if [[ "$hy2_files" == "1" ]]; then
      expected_dir="$(dirname -- "${CFG_HY2_CERT_FILE:-}")"
      [[ "${expected_dir%/}" == "$renewed" ]] || hy2_files=0
    fi
    if [[ "$xhttp_files" == "1" ]]; then
      expected_dir="$(dirname -- "${CFG_XHTTP_CERT_FILE:-}")"
      [[ "${expected_dir%/}" == "$renewed" ]] || xhttp_files=0
    fi
    if [[ "$hy2_files" != "1" && "$xhttp_files" != "1" ]]; then
      return 0
    fi
  fi

  old_hy2_cert="$CFG_HY2_CERT"
  old_hy2_key="$CFG_HY2_KEY"
  old_hy2_sha="$CFG_HY2_CERT_SHA256"
  old_xhttp_cert="$CFG_XHTTP_CERT"
  old_xhttp_key="$CFG_XHTTP_KEY"
  old_xhttp_sha="$CFG_XHTTP_CERT_SHA256"

  if [[ "$hy2_files" == "1" ]]; then
    verify_name="${CFG_HY2_SNI:-$CFG_SERVER_ADDR}"
    if [[ -z "$CFG_HY2_CERT_FILE" || -z "$CFG_HY2_KEY_FILE" ]]; then
      log_err err_hy2_cert_sources_missing
      had_error=1
    elif ! tls_validate_pair_files "$CFG_HY2_CERT_FILE" "$CFG_HY2_KEY_FILE"; then
      log_err err_hy2_cert_pair "$CFG_HY2_CERT_FILE" "$CFG_HY2_KEY_FILE"
      had_error=1
    elif ! tls_cert_matches_name "$CFG_HY2_CERT_FILE" "$verify_name"; then
      log_err err_hy2_cert_sni_mismatch "$verify_name"
      had_error=1
    elif [[ "$TLS_CERT_PEM" != "$CFG_HY2_CERT" || "$TLS_KEY_PEM" != "$CFG_HY2_KEY" ]]; then
      CFG_HY2_CERT="$TLS_CERT_PEM"
      CFG_HY2_KEY="$TLS_KEY_PEM"
      CFG_HY2_CERT_SHA256="$TLS_CERT_SHA256"
      changed=1
    fi
  fi

  if [[ "$xhttp_files" == "1" ]]; then
    if [[ -z "$CFG_XHTTP_CERT_FILE" || -z "$CFG_XHTTP_KEY_FILE" ]]; then
      log_err err_xhttp_cert_sources_missing
      had_error=1
    elif ! tls_validate_pair_files "$CFG_XHTTP_CERT_FILE" "$CFG_XHTTP_KEY_FILE"; then
      log_err err_xhttp_cert_pair "$CFG_XHTTP_CERT_FILE" "$CFG_XHTTP_KEY_FILE"
      had_error=1
    elif ! tls_cert_matches_name "$CFG_XHTTP_CERT_FILE" "$CFG_XHTTP_HOST"; then
      log_err err_xhttp_cert_host_mismatch "$CFG_XHTTP_HOST"
      had_error=1
    elif [[ "$TLS_CERT_PEM" != "$CFG_XHTTP_CERT" || "$TLS_KEY_PEM" != "$CFG_XHTTP_KEY" ]]; then
      CFG_XHTTP_CERT="$TLS_CERT_PEM"
      CFG_XHTTP_KEY="$TLS_KEY_PEM"
      CFG_XHTTP_CERT_SHA256="$TLS_CERT_SHA256"
      changed=1
    fi
  fi

  if [[ "$changed" != "1" ]]; then
    [[ "$had_error" == "1" ]] && exit 1
    log_info info_cert_unchanged
    return 0
  fi

  core_call is_installed || die err_core_install "$CFG_CORE"
  if ! apply_config "" "if-active"; then
    CFG_HY2_CERT="$old_hy2_cert"
    CFG_HY2_KEY="$old_hy2_key"
    CFG_HY2_CERT_SHA256="$old_hy2_sha"
    CFG_XHTTP_CERT="$old_xhttp_cert"
    CFG_XHTTP_KEY="$old_xhttp_key"
    CFG_XHTTP_CERT_SHA256="$old_xhttp_sha"
    die err_apply
  fi
  if ! state_save; then
    CFG_HY2_CERT="$old_hy2_cert"
    CFG_HY2_KEY="$old_hy2_key"
    CFG_HY2_CERT_SHA256="$old_hy2_sha"
    CFG_XHTTP_CERT="$old_xhttp_cert"
    CFG_XHTTP_KEY="$old_xhttp_key"
    CFG_XHTTP_CERT_SHA256="$old_xhttp_sha"
    rollback_applied_config
    die err_state_save "$TB_STATE_FILE"
  fi
  log_ok ok_cert_refreshed
  [[ "$had_error" == "1" ]] && exit 1
  return 0
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
