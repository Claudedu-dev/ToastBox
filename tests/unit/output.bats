#!/usr/bin/env bats

load helper

setup() {
  load_toastbox
  sample_node
  OUT_VLESS=1
  OUT_SS=1
}

q() { jq -r "$1" <<<"$output"; }

@test "vless_link carries every REALITY parameter" {
  run vless_link
  [ "$output" = "vless://5783a3e7-e373-51cd-8642-c83782b807c5@203.0.113.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0&sid=0123456789abcdef&type=tcp&headerType=none#ToastBox-vless" ]
}

@test "ss_link is SIP002 with a percent-encoded plain user info" {
  run ss_link
  [ "$output" = "ss://2022-blake3-aes-128-gcm:8JCsPssfgS8tiRwiMlhARg%3D%3D@203.0.113.10:28443#ToastBox-ss" ]
}

@test "ss_link escapes + and / in the key" {
  CFG_SS_PASSWORD="ab+/cd+/ef+/gh+/ij+/kg=="
  run ss_link
  [[ "$output" == "ss://2022-blake3-aes-128-gcm:ab%2B%2Fcd%2B%2Fef%2B%2Fgh%2B%2Fij%2B%2Fkg%3D%3D@"* ]]
}

@test "links bracket IPv6 addresses and encode the node name" {
  CFG_SERVER_ADDR="2001:db8::1"
  CFG_NODE_NAME="东京 #1"
  run vless_link
  [[ "$output" == *"@[2001:db8::1]:443?"* ]]
  [[ "$output" == *"#%E4%B8%9C%E4%BA%AC%20%231-vless" ]]
  run ss_link
  [[ "$output" == *"@[2001:db8::1]:28443#"* ]]
}

@test "xray client config mirrors the server parameters" {
  run client_xray_json
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].protocol')" = "socks" ]
  [ "$(q '.inbounds[0].listen')" = "127.0.0.1" ]
  [ "$(q '.outbounds[0].protocol')" = "vless" ]
  [ "$(q '.outbounds[0].settings.address')" = "203.0.113.10" ]
  [ "$(q '.outbounds[0].settings.port')" = "443" ]
  [ "$(q '.outbounds[0].settings.id')" = "$CFG_VLESS_UUID" ]
  [ "$(q '.outbounds[0].settings.encryption')" = "none" ]
  [ "$(q '.outbounds[0].settings.flow')" = "xtls-rprx-vision" ]
  [ "$(q '.outbounds[0].streamSettings.method')" = "raw" ]
  [ "$(q '.outbounds[0].streamSettings.security')" = "reality" ]
  [ "$(q '.outbounds[0].streamSettings.realitySettings.serverName')" = "www.example.com" ]
  [ "$(q '.outbounds[0].streamSettings.realitySettings.password')" = "$CFG_REALITY_PUBLIC_KEY" ]
  [ "$(q '.outbounds[0].streamSettings.realitySettings.shortId')" = "0123456789abcdef" ]
  [ "$(q '.outbounds[0].streamSettings.realitySettings.fingerprint')" = "chrome" ]
  [ "$(q '.outbounds[1].protocol')" = "shadowsocks" ]
  [ "$(q '.outbounds[1].settings.port')" = "28443" ]
  [ "$(q '.outbounds[1].settings.password')" = "8JCsPssfgS8tiRwiMlhARg==" ]
}

@test "sing-box client config mirrors the server parameters" {
  run client_singbox_json
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].type')" = "mixed" ]
  [ "$(q '.outbounds[0].type')" = "vless" ]
  [ "$(q '.outbounds[0].server')" = "203.0.113.10" ]
  [ "$(q '.outbounds[0].server_port')" = "443" ]
  [ "$(q '.outbounds[0].uuid')" = "$CFG_VLESS_UUID" ]
  [ "$(q '.outbounds[0].flow')" = "xtls-rprx-vision" ]
  [ "$(q '.outbounds[0].tls.server_name')" = "www.example.com" ]
  [ "$(q '.outbounds[0].tls.utls.enabled')" = "true" ]
  [ "$(q '.outbounds[0].tls.reality.public_key')" = "$CFG_REALITY_PUBLIC_KEY" ]
  [ "$(q '.outbounds[0].tls.reality.short_id')" = "0123456789abcdef" ]
  [ "$(q '.outbounds[1].type')" = "shadowsocks" ]
  [ "$(q '.outbounds[1].method')" = "2022-blake3-aes-128-gcm" ]
  [ "$(q '.route.final')" = "vless-reality" ]
}

@test "client configs never contain the REALITY private key" {
  run client_xray_json
  [[ "$output" != *"$CFG_REALITY_PRIVATE_KEY"* ]]
  run client_singbox_json
  [[ "$output" != *"$CFG_REALITY_PRIVATE_KEY"* ]]
}

@test "a Shadowsocks-only client config routes through Shadowsocks" {
  OUT_VLESS=0
  run client_singbox_json
  [ "$(q '[.outbounds[].type] | join(",")')" = "shadowsocks" ]
  [ "$(q '.route.final')" = "ss-2022" ]
  run client_xray_json
  [ "$(q '[.outbounds[].protocol] | join(",")')" = "shadowsocks" ]
}

@test "show_json exposes the node and its links" {
  run show_json
  [ "$status" -eq 0 ]
  [ "$(q '.core')" = "xray" ]
  [ "$(q '.vless.port')" = "443" ]
  [ "$(q '.links.vless')" = "$(vless_link)" ]
  [ "$(q '.links.ss')" = "$(ss_link)" ]
  [ "$(q '.toastbox_version')" = "$TB_VERSION" ]
}

@test "select_output_protocols honours --protocols" {
  select_output_protocols
  [ "$OUT_VLESS$OUT_SS" = "11" ]
  OPT_PROTOCOLS="ss"
  select_output_protocols
  [ "$OUT_VLESS$OUT_SS" = "01" ]
}

@test "select_output_protocols rejects a protocol the node does not run" {
  CFG_SS=0
  OPT_PROTOCOLS="ss"
  run select_output_protocols
  [ "$status" -ne 0 ]
  [[ "$output" == *"not enabled"* ]]
}
