# shellcheck shell=bash
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

# Machine-readable description: the state plus the share links.
show_json() {
  local vless_uri="" ss_uri=""
  [[ "$OUT_VLESS" == "1" ]] && vless_uri="$(vless_link)"
  [[ "$OUT_SS" == "1" ]] && ss_uri="$(ss_link)"
  state_json | jq --arg vless "$vless_uri" --arg ss "$ss_uri" \
    --arg version "$TB_VERSION" '
    del(.firewall, .schema)
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
