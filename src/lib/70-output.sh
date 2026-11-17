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
