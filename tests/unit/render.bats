#!/usr/bin/env bats

load helper

setup() {
  load_toastbox
  sample_node
  ipv6_enabled() { return 0; }
}

# q FILTER: evaluates a jq filter against $output.
q() { jq -r "$1" <<<"$output"; }

@test "xray: VLESS inbound uses the current field names" {
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].protocol')" = "vless" ]
  [ "$(q '.inbounds[0].port')" = "443" ]
  [ "$(q '.inbounds[0].settings.users[0].id')" = "$CFG_VLESS_UUID" ]
  [ "$(q '.inbounds[0].settings.users[0].flow')" = "xtls-rprx-vision" ]
  [ "$(q '.inbounds[0].settings.decryption')" = "none" ]
  [ "$(q '.inbounds[0].streamSettings.method')" = "raw" ]
  [ "$(q '.inbounds[0].streamSettings.security')" = "reality" ]
  [ "$(q '.inbounds[0].streamSettings.realitySettings.target')" = "www.example.com:443" ]
  [ "$(q '.inbounds[0].streamSettings.realitySettings.serverNames | join(",")')" = "www.example.com" ]
  [ "$(q '.inbounds[0].streamSettings.realitySettings.privateKey')" = "$CFG_REALITY_PRIVATE_KEY" ]
  [ "$(q '.inbounds[0].streamSettings.realitySettings.shortIds | join(",")')" = "0123456789abcdef" ]
  # Legacy names must not appear.
  [ "$(q '[.. | objects | keys[]] | map(select(. == "clients" or . == "dest" or . == "tcpSettings")) | length')" = "0" ]
  [ "$(q '.inbounds[0].streamSettings | has("network")')" = "false" ]
}

@test "xray: the server config never contains the public key" {
  run xray_render
  [[ "$output" != *"$CFG_REALITY_PUBLIC_KEY"* ]]
}

@test "xray: Shadowsocks inbound listens on TCP and UDP by default" {
  run xray_render
  [ "$(q '.inbounds[1].protocol')" = "shadowsocks" ]
  [ "$(q '.inbounds[1].port')" = "28443" ]
  [ "$(q '.inbounds[1].settings.network')" = "tcp,udp" ]
  [ "$(q '.inbounds[1].settings.method')" = "2022-blake3-aes-128-gcm" ]
  [ "$(q '.inbounds[1].settings.password')" = "8JCsPssfgS8tiRwiMlhARg==" ]
}

@test "xray: --ss-network narrows the listen network" {
  CFG_SS_NETWORK="tcp"
  run xray_render
  [ "$(q '.inbounds[1].settings.network')" = "tcp" ]
  CFG_SS_NETWORK="udp"
  run xray_render
  [ "$(q '.inbounds[1].settings.network')" = "udp" ]
}

@test "xray: listen is omitted by default and applied to every inbound when set" {
  run xray_render
  [ "$(q '[.inbounds[] | has("listen")] | any')" = "false" ]
  CFG_LISTEN="203.0.113.10"
  run xray_render
  [ "$(q '[.inbounds[].listen] | unique | join(",")')" = "203.0.113.10" ]
}

@test "xray: private destinations are blocked unless allowed" {
  run xray_render
  [ "$(q '.routing.rules | length')" = "1" ]
  [ "$(q '.routing.rules[0].outboundTag')" = "block" ]
  [ "$(q '.routing.rules[0].ip | index("127.0.0.0/8") != null')" = "true" ]
  [ "$(q '.routing.rules[0].ip | index("169.254.0.0/16") != null')" = "true" ]
  [ "$(q '.routing.rules[0].ip | index("fc00::/7") != null')" = "true" ]
  [ "$(q '[.outbounds[].protocol] | join(",")')" = "freedom,blackhole" ]
  [ "$(q '.outbounds[0] | has("settings")')" = "false" ]
  CFG_ALLOW_PRIVATE=1
  run xray_render
  [ "$(q '.routing.rules | length')" = "0" ]
  [ "$(q '.outbounds[0].settings.finalRules[0].action')" = "allow" ]
}

@test "xray: --block-bt adds sniffing and a bittorrent rule" {
  run xray_render
  [ "$(q '[.inbounds[] | has("sniffing")] | any')" = "false" ]
  CFG_BLOCK_BT=1
  run xray_render
  [ "$(q '[.inbounds[].sniffing.enabled] | all')" = "true" ]
  [ "$(q '[.inbounds[].sniffing.routeOnly] | all')" = "true" ]
  [ "$(q '.routing.rules[0].protocol[0]')" = "bittorrent" ]
  [ "$(q '.routing.rules[0].outboundTag')" = "block" ]
}

@test "xray: only the enabled protocols are rendered" {
  CFG_SS=0
  run xray_render
  [ "$(q '[.inbounds[].protocol] | join(",")')" = "vless" ]
  CFG_SS=1
  CFG_VLESS=0
  run xray_render
  [ "$(q '[.inbounds[].protocol] | join(",")')" = "shadowsocks" ]
}

@test "sing-box: VLESS inbound with REALITY" {
  run singbox_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].type')" = "vless" ]
  [ "$(q '.inbounds[0].listen')" = "::" ]
  [ "$(q '.inbounds[0].listen_port')" = "443" ]
  [ "$(q '.inbounds[0].users[0].uuid')" = "$CFG_VLESS_UUID" ]
  [ "$(q '.inbounds[0].users[0].flow')" = "xtls-rprx-vision" ]
  [ "$(q '.inbounds[0].tls.enabled')" = "true" ]
  [ "$(q '.inbounds[0].tls.server_name')" = "www.example.com" ]
  [ "$(q '.inbounds[0].tls.reality.enabled')" = "true" ]
  [ "$(q '.inbounds[0].tls.reality.handshake.server')" = "www.example.com" ]
  [ "$(q '.inbounds[0].tls.reality.handshake.server_port')" = "443" ]
  [ "$(q '.inbounds[0].tls.reality.private_key')" = "$CFG_REALITY_PRIVATE_KEY" ]
  [ "$(q '.inbounds[0].tls.reality.short_id | join(",")')" = "0123456789abcdef" ]
  [ "$(q '.inbounds[0] | has("transport")')" = "false" ]
}

@test "sing-box: no deprecated inbound fields or special outbounds" {
  CFG_BLOCK_BT=1
  run singbox_render
  [ "$(q '[.inbounds[] | has("sniff") or has("domain_strategy") or has("sniff_override_destination")] | any')" = "false" ]
  [ "$(q '[.outbounds[].type] | join(",")')" = "direct" ]
  [ "$(q 'has("dns")')" = "false" ]
}

@test "sing-box: an IPv6 REALITY target is split into host and port" {
  CFG_REALITY_TARGET="[2001:db8::1]:8443"
  run singbox_render
  [ "$(q '.inbounds[0].tls.reality.handshake.server')" = "2001:db8::1" ]
  [ "$(q '.inbounds[0].tls.reality.handshake.server_port')" = "8443" ]
}

@test "sing-box: listen falls back to IPv4 when IPv6 is disabled" {
  ipv6_enabled() { return 1; }
  run singbox_render
  [ "$(q '[.inbounds[].listen] | unique | join(",")')" = "0.0.0.0" ]
  CFG_LISTEN="203.0.113.10"
  run singbox_render
  [ "$(q '[.inbounds[].listen] | unique | join(",")')" = "203.0.113.10" ]
}

@test "sing-box: Shadowsocks network is omitted for TCP+UDP" {
  run singbox_render
  [ "$(q '.inbounds[1].type')" = "shadowsocks" ]
  [ "$(q '.inbounds[1].listen_port')" = "28443" ]
  [ "$(q '.inbounds[1] | has("network")')" = "false" ]
  [ "$(q '.inbounds[1].method')" = "2022-blake3-aes-128-gcm" ]
  CFG_SS_NETWORK="tcp"
  run singbox_render
  [ "$(q '.inbounds[1].network')" = "tcp" ]
}

@test "sing-box: routing rules follow the options" {
  run singbox_render
  [ "$(q '.route.rules | length')" = "1" ]
  [ "$(q '.route.rules[0].ip_is_private')" = "true" ]
  [ "$(q '.route.rules[0].action')" = "reject" ]
  [ "$(q '.route.final')" = "direct" ]
  CFG_BLOCK_BT=1
  run singbox_render
  [ "$(q '[.route.rules[].action] | join(",")')" = "sniff,reject,reject" ]
  [ "$(q '.route.rules[1].protocol')" = "bittorrent" ]
  CFG_ALLOW_PRIVATE=1
  CFG_BLOCK_BT=0
  run singbox_render
  [ "$(q '.route.rules | length')" = "0" ]
}

@test "values with JSON metacharacters cannot break the document" {
  CFG_SS_PASSWORD='a"b\c'
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[1].settings.password')" = 'a"b\c' ]
  run singbox_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[1].password')" = 'a"b\c' ]
}

@test "xray: Hysteria 2 inbound renders current fields, inline TLS, salamander and masquerade" {
  sample_hy2
  CFG_LISTEN="203.0.113.10"
  CFG_BLOCK_BT=1
  CFG_SOCKOPT='{"tcpKeepAliveIdle":120}'
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[2].protocol')" = "hysteria" ]
  [ "$(q '.inbounds[2].port')" = "443" ]
  [ "$(q '.inbounds[2].listen')" = "203.0.113.10" ]
  [ "$(q '.inbounds[2].settings.version')" = "2" ]
  [ "$(q '.inbounds[2].settings.users[0].auth')" = "hy2-secret-password" ]
  [ "$(q '.inbounds[2].streamSettings.method')" = "hysteria" ]
  [ "$(q '.inbounds[2].streamSettings.security')" = "tls" ]
  [ "$(q '.inbounds[2].streamSettings.tlsSettings.alpn | join(",")')" = "h3" ]
  [ "$(q '.inbounds[2].streamSettings.tlsSettings.certificates[0].certificate[0]')" = "-----BEGIN CERTIFICATE-----" ]
  [ "$(q '.inbounds[2].streamSettings.tlsSettings.certificates[0].key[0]')" = "-----BEGIN PRIVATE KEY-----" ]
  [ "$(q '.inbounds[2].streamSettings.hysteriaSettings.version')" = "2" ]
  [ "$(q '.inbounds[2].streamSettings.hysteriaSettings.masquerade.type')" = "proxy" ]
  [ "$(q '.inbounds[2].streamSettings.hysteriaSettings.masquerade.url')" = "https://www.example.com" ]
  [ "$(q '.inbounds[2].streamSettings.hysteriaSettings.masquerade.rewriteHost')" = "true" ]
  [ "$(q '.inbounds[2].streamSettings.finalmask.udp[0].type')" = "salamander" ]
  [ "$(q '.inbounds[2].streamSettings.finalmask.udp[0].settings.password')" = "obfs-secret-password" ]
  [ "$(q '.inbounds[2].streamSettings | has("sockopt")')" = "false" ]
  [ "$(q '.inbounds[2].sniffing.enabled')" = "true" ]
}

@test "sing-box: Hysteria 2 inbound renders TLS, obfs and masquerade" {
  sample_hy2
  CFG_BLOCK_BT=1
  run singbox_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[2].type')" = "hysteria2" ]
  [ "$(q '.inbounds[2].listen')" = "::" ]
  [ "$(q '.inbounds[2].listen_port')" = "443" ]
  [ "$(q '.inbounds[2].users[0].password')" = "hy2-secret-password" ]
  [ "$(q '.inbounds[2].tls.enabled')" = "true" ]
  [ "$(q '.inbounds[2].tls.certificate[0]')" = "-----BEGIN CERTIFICATE-----" ]
  [ "$(q '.inbounds[2].tls.key[0]')" = "-----BEGIN PRIVATE KEY-----" ]
  [ "$(q '.inbounds[2].obfs.type')" = "salamander" ]
  [ "$(q '.inbounds[2].obfs.password')" = "obfs-secret-password" ]
  [ "$(q '.inbounds[2].masquerade.type')" = "proxy" ]
  [ "$(q '.inbounds[2].masquerade.url')" = "https://www.example.com" ]
  [ "$(q '.inbounds[2].masquerade.rewrite_host')" = "true" ]

  CFG_HY2_OBFS="none"
  CFG_HY2_MASQUERADE=""
  run singbox_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[2] | has("obfs")')" = "false" ]
  [ "$(q '.inbounds[2] | has("masquerade")')" = "false" ]
}
