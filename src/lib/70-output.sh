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

xhttp_dial_addr() {
  printf '%s' "${CFG_XHTTP_CONNECT_ADDR:-$CFG_XHTTP_HOST}"
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

# Standard VLESS + XHTTP share link understood by v2rayN / v2rayNG / Xray.
xhttp_link() {
  local dial query
  dial="$(uri_host "$(xhttp_dial_addr)")"
  query="encryption=none&security=tls"
  query+="&sni=$(urlencode "$CFG_XHTTP_HOST")"
  query+="&alpn=$(urlencode "$CFG_XHTTP_ALPN")"
  query+="&fp=chrome&type=xhttp"
  query+="&host=$(urlencode "$CFG_XHTTP_HOST")"
  query+="&path=$(urlencode "$CFG_XHTTP_PATH")"
  query+="&mode=$(urlencode "$CFG_XHTTP_CLIENT_MODE")"
  printf 'vless://%s@%s:%s?%s#%s\n' \
    "$CFG_XHTTP_UUID" "$dial" "$CFG_XHTTP_PUBLIC_PORT" \
    "$query" "$(urlencode "$(link_label xhttp)")"
}

xhttp_ws_link() {
  local dial query
  dial="$(uri_host "$(xhttp_dial_addr)")"
  query="encryption=none&security=tls"
  query+="&sni=$(urlencode "$CFG_XHTTP_HOST")"
  query+="&alpn=$(urlencode "http/1.1")"
  query+="&fp=chrome&type=ws"
  query+="&host=$(urlencode "$CFG_XHTTP_HOST")"
  query+="&path=$(urlencode "$CFG_XHTTP_WS_PATH")"
  printf 'vless://%s@%s:%s?%s#%s\n' \
    "$CFG_XHTTP_UUID" "$dial" "$CFG_XHTTP_WS_PUBLIC_PORT" \
    "$query" "$(urlencode "$(link_label xhttp-ws)")"
}

# client_jq ARGS...: runs jq with the arguments shared by all client
# renderers. OUT_VLESS / OUT_SS / OUT_HY2 / OUT_XHTTP select which outbounds are emitted.
client_jq() {
  jq -n \
    --arg node_name "${CFG_NODE_NAME:-ToastBox}" \
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
    --arg ss_network "$CFG_SS_NETWORK" \
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
    --arg xhttp "$OUT_XHTTP" \
    --arg xhttp_dial "$(xhttp_dial_addr)" \
    --arg xhttp_public_port "$CFG_XHTTP_PUBLIC_PORT" \
    --arg xhttp_connect_addr "$CFG_XHTTP_CONNECT_ADDR" \
    --arg xhttp_uuid "$CFG_XHTTP_UUID" \
    --arg xhttp_host "$CFG_XHTTP_HOST" \
    --arg xhttp_path "$CFG_XHTTP_PATH" \
    --arg xhttp_client_mode "$CFG_XHTTP_CLIENT_MODE" \
    --arg xhttp_alpn "$CFG_XHTTP_ALPN" \
    --arg xhttp_ws "$CFG_XHTTP_WS" \
    --arg xhttp_ws_public_port "$CFG_XHTTP_WS_PUBLIC_PORT" \
    --arg xhttp_ws_path "$CFG_XHTTP_WS_PATH" \
    "$@"
}

# A complete Xray client configuration: SOCKS5 on 127.0.0.1:1080. The first
# outbound is the default one.
client_xray_json() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  client_jq '
    {
      log: {logLevel: "warning"},
      inbounds: [
        ({
          tag: "socks-in",
          listen: "127.0.0.1",
          port: 1080,
          protocol: "socks",
          settings: {udp: true}
        }
        + (if $xhttp == "1" and $xhttp_ws == "1" then {
          sniffing: {
            enabled: true,
            destOverride: ["http", "tls"],
            routeOnly: true
          }
        } else {} end))
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
        (if $xhttp == "1" then
          {
            tag: "vless-xhttp",
            protocol: "vless",
            settings: {
              address: $xhttp_dial,
              port: ($xhttp_public_port | tonumber),
              id: $xhttp_uuid,
              encryption: "none"
            },
            streamSettings: {
              method: "xhttp",
              security: "tls",
              tlsSettings: {
                serverName: $xhttp_host,
                alpn: ($xhttp_alpn | split(",")),
                fingerprint: "chrome",
                useSystemCA: true
              },
              xhttpSettings: {
                host: $xhttp_host,
                path: $xhttp_path,
                mode: $xhttp_client_mode
              }
            }
          }
        else empty end),
        (if $xhttp == "1" and $xhttp_ws == "1" then
          {
            tag: "vless-ws-keepalive",
            protocol: "vless",
            settings: {
              address: $xhttp_dial,
              port: ($xhttp_ws_public_port | tonumber),
              id: $xhttp_uuid,
              encryption: "none"
            },
            streamSettings: {
              method: "websocket",
              security: "tls",
              tlsSettings: {
                serverName: $xhttp_host,
                alpn: ["http/1.1"],
                fingerprint: "chrome",
                useSystemCA: true
              },
              wsSettings: {
                host: $xhttp_host,
                path: $xhttp_ws_path
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
    }
    + (if $xhttp == "1" and $xhttp_ws == "1" then {
      routing: {
        rules: [
          {
            domain: [
              "domain:openai.com",
              "domain:chatgpt.com",
              "domain:oaistatic.com",
              "domain:oaiusercontent.com"
            ],
            outboundTag: "vless-ws-keepalive"
          },
          {
            port: "22",
            network: "tcp",
            outboundTag: "vless-ws-keepalive"
          }
        ]
      }
    } else {} end)'
}

# A complete sing-box client configuration: mixed (SOCKS5 + HTTP) proxy on
# 127.0.0.1:1080. REALITY on the client side needs uTLS.
client_singbox_json() {
  if [[ "$OUT_XHTTP" == "1" ]]; then
    if [[ "$CFG_XHTTP_WS" == "1" ]]; then
      log_warn warn_singbox_xhttp_ws_only
    else
      if [[ "$OUT_VLESS" != "1" && "$OUT_SS" != "1" && "$OUT_HY2" != "1" ]]; then
        die err_format_singbox_no_xhttp
      fi
      log_warn warn_singbox_skip_xhttp
    fi
  fi
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
        (if $xhttp == "1" and $xhttp_ws == "1" then
          {
            type: "vless",
            tag: "vless-ws-keepalive",
            server: $xhttp_dial,
            server_port: ($xhttp_ws_public_port | tonumber),
            uuid: $xhttp_uuid,
            tls: {
              enabled: true,
              server_name: $xhttp_host,
              alpn: ["http/1.1"],
              utls: {enabled: true, fingerprint: "chrome"}
            },
            transport: {
              type: "ws",
              path: $xhttp_ws_path,
              headers: {Host: $xhttp_host}
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
      route: (
        {
          final: (
            if $vless == "1" then "vless-reality"
            elif $ss == "1" then "ss-2022"
            elif $hy2 == "1" then "hysteria2"
            else "vless-ws-keepalive"
            end
          )
        }
        + (if $xhttp == "1" and $xhttp_ws == "1" and ($vless == "1" or $ss == "1" or $hy2 == "1") then {
          rules: [
            {action: "sniff"},
            {
              domain_suffix: [
                "openai.com",
                "chatgpt.com",
                "oaistatic.com",
                "oaiusercontent.com"
              ],
              outbound: "vless-ws-keepalive"
            },
            {
              network: "tcp",
              port: [22],
              outbound: "vless-ws-keepalive"
            }
          ]
        } else {} end)
      )
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

# Complete runnable Mihomo (Clash Meta >= v1.19.34) YAML configuration.
client_mihomo_yaml() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  client_jq -r '
    def q: @json;
    def node_label($s): ($node_name + "-" + $s);
    def has_fallback: ($xhttp == "1" and $xhttp_connect_addr != "" and $xhttp_connect_addr != $xhttp_host);
    def proxy_names:
      [
        (if $vless == "1" then node_label("vless") else empty end),
        (if $xhttp == "1" then node_label("xhttp") else empty end),
        (if has_fallback then node_label("xhttp-fallback") else empty end),
        (if $xhttp == "1" and $xhttp_ws == "1" then node_label("xhttp-ws") else empty end),
        (if has_fallback and $xhttp_ws == "1" then node_label("xhttp-ws-fallback") else empty end),
        (if $ss == "1" then node_label("ss") else empty end),
        (if $hy2 == "1" then node_label("hy2") else empty end)
      ];
    def ws_names:
      [
        (if $xhttp == "1" and $xhttp_ws == "1" then node_label("xhttp-ws") else empty end),
        (if has_fallback and $xhttp_ws == "1" then node_label("xhttp-ws-fallback") else empty end),
        (if $xhttp == "1" then node_label("xhttp") else empty end),
        (if has_fallback then node_label("xhttp-fallback") else empty end),
        (if $vless == "1" then node_label("vless") else empty end),
        (if $ss == "1" then node_label("ss") else empty end),
        (if $hy2 == "1" then node_label("hy2") else empty end)
      ];
    def xhttp_entry($name; $srv):
      [
        "  - name: \($name | q)",
        "    type: vless",
        "    server: \($srv | q)",
        "    port: \($xhttp_public_port)",
        "    uuid: \($xhttp_uuid | q)",
        "    udp: true",
        "    tls: true",
        "    servername: \($xhttp_host | q)",
        "    client-fingerprint: chrome",
        "    alpn:",
        (($xhttp_alpn | split(","))[] | "      - \(. | q)"),
        "    network: xhttp",
        "    xhttp-opts:",
        "      host: \($xhttp_host | q)",
        "      path: \($xhttp_path | q)",
        "      mode: \($xhttp_client_mode | q)"
      ];
    def ws_entry($name; $srv):
      [
        "  - name: \($name | q)",
        "    type: vless",
        "    server: \($srv | q)",
        "    port: \($xhttp_ws_public_port)",
        "    uuid: \($xhttp_uuid | q)",
        "    udp: true",
        "    tls: true",
        "    servername: \($xhttp_host | q)",
        "    client-fingerprint: chrome",
        "    alpn:",
        "      - \"http/1.1\"",
        "    network: ws",
        "    ws-opts:",
        "      path: \($xhttp_ws_path | q)",
        "      headers:",
        "        Host: \($xhttp_host | q)"
      ];
    def vless_lines:
      if $vless == "1" then
        [
          "  - name: \(node_label("vless") | q)",
          "    type: vless",
          "    server: \($server | q)",
          "    port: \($vless_port)",
          "    uuid: \($uuid | q)",
          "    network: tcp",
          "    udp: true",
          "    tls: true",
          "    flow: xtls-rprx-vision",
          "    servername: \($sni | q)",
          "    client-fingerprint: chrome",
          "    reality-opts:",
          "      public-key: \($public_key | q)",
          "      short-id: \($short_id | q)"
        ]
      else [] end;
    def xhttp_lines:
      if $xhttp == "1" then
        xhttp_entry(node_label("xhttp"); $xhttp_dial)
        + (if has_fallback then xhttp_entry(node_label("xhttp-fallback"); $xhttp_host) else [] end)
        + (if $xhttp_ws == "1" then
            ws_entry(node_label("xhttp-ws"); $xhttp_dial)
            + (if has_fallback then ws_entry(node_label("xhttp-ws-fallback"); $xhttp_host) else [] end)
           else [] end)
      else [] end;
    def ss_lines:
      if $ss == "1" then
        [
          "  - name: \(node_label("ss") | q)",
          "    type: ss",
          "    server: \($server | q)",
          "    port: \($ss_port)",
          "    cipher: \($ss_method | q)",
          "    password: \($ss_password | q)",
          "    udp: \(if $ss_network == "tcp" then "false" else "true" end)"
        ]
      else [] end;
    def hy2_lines:
      if $hy2 == "1" then
        [
          "  - name: \(node_label("hy2") | q)",
          "    type: hysteria2",
          "    server: \($server | q)"
        ]
        + (if $hy2_hop_ports != "" then
            [
              "    ports: \($hy2_hop_ports | q)",
              "    hop-interval: \(if $hy2_hop_min == $hy2_hop_max then $hy2_hop_min else "\($hy2_hop_min)-\($hy2_hop_max)" | q end)"
            ]
           else
            ["    port: \($hy2_port)"]
           end)
        + [
            "    password: \($hy2_password | q)"
          ]
        + (if $hy2_sni != "" then ["    sni: \($hy2_sni | q)"] else [] end)
        + (if $hy2_tls == "self-signed" then
            [
              "    skip-cert-verify: false",
              "    fingerprint: \($hy2_sha256 | q)"
            ]
           else [] end)
        + (if $hy2_obfs == "salamander" then
            [
              "    obfs: salamander",
              "    obfs-password: \($hy2_obfs_password | q)"
            ]
           else [] end)
        + [
            "    alpn:",
            "      - \"h3\""
          ]
      else [] end;

    [
      (if $xhttp == "1"
       then "# Generated by ToastBox (Mihomo >= v1.19.34 required for XHTTP)"
       else "# Generated by ToastBox" end),
      "mixed-port: 1080",
      "bind-address: 127.0.0.1",
      "allow-lan: false",
      "mode: rule",
      "log-level: warning",
      "",
      "proxies:"
    ]
    + vless_lines + xhttp_lines + ss_lines + hy2_lines
    + [
      "",
      "proxy-groups:",
      "  - name: \"Proxy-Main\"",
      "    type: select",
      "    proxies:"
    ]
    + (proxy_names | map("      - \(q)"))
    + (if $xhttp == "1" and $xhttp_ws == "1" then
        [
          "  - name: \"Long-Conn-KeepAlive\"",
          "    type: select",
          "    proxies:"
        ] + (ws_names | map("      - \(q)"))
       else [] end)
    + [
      "",
      "rules:",
      "  # Private / loopback / CGNAT / link-local direct rules MUST stay before DST-PORT,22",
      "  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
      "  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
      "  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
      "  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
      "  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
      "  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
      "  - IP-CIDR6,::1/128,DIRECT,no-resolve",
      "  - IP-CIDR6,fc00::/7,DIRECT,no-resolve",
      "  - IP-CIDR6,fe80::/10,DIRECT,no-resolve"
    ]
    + (if $xhttp == "1" and $xhttp_ws == "1" then
        [
          "  - DOMAIN-SUFFIX,openai.com,Long-Conn-KeepAlive",
          "  - DOMAIN-SUFFIX,chatgpt.com,Long-Conn-KeepAlive",
          "  - DOMAIN-SUFFIX,oaistatic.com,Long-Conn-KeepAlive",
          "  - DOMAIN-SUFFIX,oaiusercontent.com,Long-Conn-KeepAlive",
          "  - DST-PORT,22,Long-Conn-KeepAlive"
        ]
       else [] end)
    + ["  - MATCH,Proxy-Main"]
    | join("\n")'
}

nginx_xhttp_snippet() {
  local upstream
  [[ "$OUT_XHTTP" == "1" ]] || die err_format_requires_xhttp
  [[ "$CFG_XHTTP_TLS" == "none" ]] || die err_format_nginx_requires_none
  upstream="$(uri_host "$CFG_XHTTP_LISTEN")"
  cat <<EOF
# Embed inside: server { listen 443 ssl; http2 on; server_name $CFG_XHTTP_HOST; ... }
# Note: On Nginx < 1.25.1 use 'listen 443 ssl http2;' and remove 'http2 on;'.
# Do NOT change '^~' to '=' on the XHTTP location (packet-up appends /<session>/<seq>).

location ^~ $CFG_XHTTP_PATH {
    client_max_body_size 0;
    client_body_timeout  5m;
    grpc_read_timeout    315s;
    grpc_send_timeout    5m;
    grpc_set_header      Host \$host;
    grpc_set_header      X-Real-IP \$remote_addr;
    grpc_set_header      X-Forwarded-For \$proxy_add_x_forwarded_for;
    grpc_pass            grpc://$upstream:$CFG_XHTTP_PORT;
}

# HTTP/1.1 fallback (if Cloudflare HTTP/2 to Origin is disabled):
# location ^~ $CFG_XHTTP_PATH {
#     client_max_body_size    0;
#     proxy_http_version      1.1;
#     proxy_set_header        Host \$host;
#     proxy_set_header        X-Real-IP \$remote_addr;
#     proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
#     proxy_set_header        Connection "";
#     proxy_buffering         off;
#     proxy_request_buffering off;
#     proxy_read_timeout      3600s;
#     proxy_send_timeout      3600s;
#     proxy_pass              http://$upstream:$CFG_XHTTP_PORT;
# }
EOF
  if [[ "$CFG_XHTTP_WS" == "1" ]]; then
    cat <<EOF

# Companion VLESS + WebSocket keep-alive path (heartbeatPeriod: ${CFG_XHTTP_WS_HEARTBEAT}s)
location = $CFG_XHTTP_WS_PATH {
    if (\$http_upgrade !~* "^websocket\$") {
        return 404;
    }
    proxy_http_version 1.1;
    proxy_set_header   Upgrade \$http_upgrade;
    proxy_set_header   Connection "upgrade";
    proxy_set_header   Host \$host;
    proxy_set_header   X-Real-IP \$remote_addr;
    proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_pass         http://$upstream:$CFG_XHTTP_WS_PORT;
}
EOF
  fi
}

# Machine-readable description: the state plus the share links. Private keys
# are left out: no client needs them, and this output tends to get pasted into
# issues and chats.
show_json() {
  local vless_uri="" ss_uri="" hy2_uri="" xhttp_uri="" xhttp_ws_uri=""
  [[ "$OUT_VLESS" == "1" ]] && vless_uri="$(vless_link)"
  [[ "$OUT_SS" == "1" ]] && ss_uri="$(ss_link)"
  [[ "$OUT_HY2" == "1" ]] && hy2_uri="$(hy2_link)"
  [[ "$OUT_XHTTP" == "1" ]] && xhttp_uri="$(xhttp_link)"
  [[ "$OUT_XHTTP" == "1" && "$CFG_XHTTP_WS" == "1" ]] && xhttp_ws_uri="$(xhttp_ws_link)"
  state_json | jq \
    --arg vless "$vless_uri" --arg ss "$ss_uri" --arg hy2 "$hy2_uri" \
    --arg xhttp "$xhttp_uri" --arg xhttp_ws "$xhttp_ws_uri" \
    --arg version "$TB_VERSION" '
    del(.firewall, .schema, .vless.private_key, .hy2.key, .xhttp.key)
    + {toastbox_version: $version}
    + {links: ({} + (if $vless != "" then {vless: $vless} else {} end)
                  + (if $ss != "" then {ss: $ss} else {} end)
                  + (if $hy2 != "" then {hy2: $hy2} else {} end)
                  + (if $xhttp != "" then {xhttp: $xhttp} else {} end)
                  + (if $xhttp_ws != "" then {xhttp_ws: $xhttp_ws} else {} end))}'
}

show_links() {
  if [[ "$OUT_VLESS" == "1" ]]; then vless_link; fi
  if [[ "$OUT_SS" == "1" ]]; then ss_link; fi
  if [[ "$OUT_HY2" == "1" ]]; then hy2_link; fi
  if [[ "$OUT_XHTTP" == "1" ]]; then
    xhttp_link
    if [[ "$CFG_XHTTP_WS" == "1" ]]; then xhttp_ws_link; fi
  fi
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

  if [[ "$OUT_XHTTP" == "1" ]]; then
    link="$(xhttp_link)"
    printf '\n%s-- VLESS + XHTTP --%s\n' "$TB_C_BOLD" "$TB_C_RESET"
    kv label_tls "$CFG_XHTTP_TLS"
    if [[ "$CFG_XHTTP_TLS" == "none" ]]; then
      kv label_backend "$(uri_host "$CFG_XHTTP_LISTEN"):$CFG_XHTTP_PORT/tcp"
    else
      if [[ -n "$CFG_XHTTP_LISTEN" ]]; then
        kv label_backend "$(uri_host "$CFG_XHTTP_LISTEN"):$CFG_XHTTP_PORT/tcp"
      else
        kv label_port "$CFG_XHTTP_PORT/tcp"
      fi
      if [[ -n "$CFG_XHTTP_CERT_FILE" ]]; then
        kv label_cert_file "$CFG_XHTTP_CERT_FILE"
        if [[ "$CFG_XHTTP_CERTBOT_HOOK" == "1" ]]; then
          kv label_cert_hook "certbot"
        fi
      fi
    fi
    kv label_connect_addr "$(uri_host "$(xhttp_dial_addr)"):$CFG_XHTTP_PUBLIC_PORT"
    kv label_host "$CFG_XHTTP_HOST"
    kv label_path "$CFG_XHTTP_PATH"
    kv label_xhttp_mode "$CFG_XHTTP_MODE (client: $CFG_XHTTP_CLIENT_MODE)"
    kv label_alpn "$CFG_XHTTP_ALPN"
    kv label_uuid "$CFG_XHTTP_UUID"
    kv label_fingerprint "chrome"
    printf '\n  %s\n  %s\n' "$(msg label_link)" "$link"
    if [[ "${OPT_QR:-0}" == "1" ]]; then show_qr "$link"; fi

    if [[ "$CFG_XHTTP_WS" == "1" ]]; then
      link="$(xhttp_ws_link)"
      printf '\n%s-- VLESS + WS (Keep-Alive) --%s\n' "$TB_C_BOLD" "$TB_C_RESET"
      if [[ "$CFG_XHTTP_TLS" == "none" || -n "$CFG_XHTTP_LISTEN" ]]; then
        kv label_backend "$(uri_host "$CFG_XHTTP_LISTEN"):$CFG_XHTTP_WS_PORT/tcp"
      else
        kv label_port "$CFG_XHTTP_WS_PORT/tcp"
      fi
      kv label_connect_addr "$(uri_host "$(xhttp_dial_addr)"):$CFG_XHTTP_WS_PUBLIC_PORT"
      kv label_host "$CFG_XHTTP_HOST"
      kv label_path "$CFG_XHTTP_WS_PATH"
      kv label_ws_heartbeat "${CFG_XHTTP_WS_HEARTBEAT}s"
      kv label_alpn "http/1.1"
      kv label_uuid "$CFG_XHTTP_UUID"
      printf '\n  %s\n  %s\n' "$(msg label_link)" "$link"
      if [[ "${OPT_QR:-0}" == "1" ]]; then show_qr "$link"; fi
      printf '\n  %s\n' "$(msg note_xhttp_ws_keepalive)"
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
  if [[ "$OUT_XHTTP" == "1" ]]; then
    if [[ "$CFG_XHTTP_TLS" == "none" ]]; then
      printf '%s\n' "$(msg note_xhttp_nginx)"
    fi
    printf '%s\n' "$(msg note_xhttp_mihomo_ver)"
  fi
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
  OUT_XHTTP="$CFG_XHTTP"
  if [[ -n "${OPT_PROTOCOLS:-}" ]]; then
    local want_vless=0 want_ss=0 want_hy2=0 want_xhttp=0
    parse_protocols "$OPT_PROTOCOLS" || die err_protocols "$OPT_PROTOCOLS"
    want_vless="$PARSED_VLESS"
    want_ss="$PARSED_SS"
    want_hy2="$PARSED_HY2"
    want_xhttp="$PARSED_XHTTP"
    [[ "$want_vless" == "1" && "$CFG_VLESS" != "1" ]] && die err_protocol_disabled "vless"
    [[ "$want_ss" == "1" && "$CFG_SS" != "1" ]] && die err_protocol_disabled "ss"
    [[ "$want_hy2" == "1" && "$CFG_HY2" != "1" ]] && die err_protocol_disabled "hy2"
    [[ "$want_xhttp" == "1" && "$CFG_XHTTP" != "1" ]] && die err_protocol_disabled "xhttp"
    OUT_VLESS="$want_vless"
    OUT_SS="$want_ss"
    OUT_HY2="$want_hy2"
    OUT_XHTTP="$want_xhttp"
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
    mihomo) client_mihomo_yaml ;;
    nginx) nginx_xhttp_snippet ;;
    *) die err_format "$OPT_FORMAT" ;;
  esac
}
