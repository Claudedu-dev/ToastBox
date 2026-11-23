#!/usr/bin/env bats

load helper

setup() {
  load_toastbox
  export MOCK_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$MOCK_LOG"
  unset MOCK_RESTART_FAILS MOCK_BUSY_PORT MOCK_PROBE_RC MOCK_DETECTED_ADDR \
    MOCK_CLOCK_UNSYNCED MOCK_FW_BACKEND FAKE_CORE_REJECT FAKE_XRAY_VERSION FAKE_SINGBOX_VERSION \
    MOCK_ANSWERS MOCK_PROBE_FAIL_SNI MOCK_SERVICE_INACTIVE MOCK_REMOVE_FAILS MOCK_NO_IPV6 \
    MOCK_HY2_HOP_NO_BACKEND MOCK_HY2_HOP_NO_CMD MOCK_HY2_HOP_FAILS TOASTBOX_HY2_HOP_BACKEND \
    MOCK_SYSTEMCTL_ENABLE_FAILS MOCK_CERTBOT_SYSTEM_TIMER
  ipv6_enabled() { return 0; }
}

q() { jq -r "$1" <<<"$output"; }
state() { jq -r "$1" "$TB_STATE_FILE"; }
calls() { cat "$MOCK_LOG"; }

make_xhttp_cert_files() {
  local name="$1" host="$2" out_cert="$3" out_key="$4"
  tls_generate_self_signed "203.0.113.10" "$host"
  printf '%s\n' "$TLS_CERT_PEM" >"$out_cert"
  printf '%s\n' "$TLS_KEY_PEM" >"$out_key"
}

@test "xhttp normalizers and path conflict detection work as specified" {
  [ "$(norm_protocols xhttp)" = "xhttp" ]
  [ "$(norm_protocols 6)" = "xhttp" ]
  [ "$(norm_protocols vless-xhttp)" = "xhttp" ]
  [ "$(norm_protocols vless,xhttp)" = "vless,xhttp" ]
  [ "$(norm_protocols all)" = "vless,ss,hy2" ]
  [ "$(norm_protocols 5)" = "vless,ss,hy2" ]

  [ "$(norm_format mihomo)" = "mihomo" ]
  [ "$(norm_format clash)" = "mihomo" ]
  [ "$(norm_format clash-meta)" = "mihomo" ]
  [ "$(norm_format nginx)" = "nginx" ]

  [ "$(norm_xhttp_tls 1)" = "none" ]
  [ "$(norm_xhttp_tls none)" = "none" ]
  [ "$(norm_xhttp_tls 2)" = "files" ]
  [ "$(norm_xhttp_tls files)" = "files" ]
  refute norm_xhttp_tls acme
  refute norm_xhttp_tls self-signed

  [ "$(norm_xhttp_path edge)" = "/edge" ]
  [ "$(norm_xhttp_path /edge-xhttp)" = "/edge-xhttp" ]
  refute norm_xhttp_path ""
  refute norm_xhttp_path "//bad"
  refute norm_xhttp_path "/bad?q=1"
  refute norm_xhttp_path "/bad#frag"
  refute norm_xhttp_path "/bad space"

  xhttp_paths_conflict "/edge" "/edge"
  xhttp_paths_conflict "/edge" "/edge/"
  xhttp_paths_conflict "/edge" "/edge/ws"
  xhttp_paths_conflict "/edge/ws" "/edge"
  refute xhttp_paths_conflict "/edge" "/edge-ws"
  refute xhttp_paths_conflict "/a1" "/a2"

  [ "$(norm_xhttp_mode auto)" = "auto" ]
  [ "$(norm_xhttp_mode packet-up)" = "packet-up" ]
  [ "$(norm_xhttp_mode stream-up)" = "stream-up" ]
  [ "$(norm_xhttp_mode stream-one)" = "stream-one" ]
  refute norm_xhttp_mode multi

  [ "$(norm_xhttp_alpn h2)" = "h2" ]
  [ "$(norm_xhttp_alpn h3)" = "h3" ]
  [ "$(norm_xhttp_alpn 'http/1.1')" = "http/1.1" ]
  refute norm_xhttp_alpn 'h3,h2'
  refute norm_xhttp_alpn 'h2,http/1.1'
  refute norm_xhttp_alpn spdy

  [ "$(norm_xhttp_ws_heartbeat 0030)" = "30" ]
  [ "$(norm_xhttp_ws_heartbeat 5)" = "5" ]
  refute norm_xhttp_ws_heartbeat 0
  refute norm_xhttp_ws_heartbeat -5
  refute norm_xhttp_ws_heartbeat abc

  [ "$(norm_xhttp_connect_addr none)" = "none" ]
  [ "$(norm_xhttp_connect_addr off)" = "none" ]
  [ "$(norm_xhttp_connect_addr '[2001:db8::1]')" = "2001:db8::1" ]
  [ "$(norm_xhttp_connect_addr CF.Example.COM)" = "cf.example.com" ]
  refute norm_xhttp_connect_addr "bad host"
}

@test "xhttp CLI options validate constraints cleanly" {
  run_toastbox install -y --core sing-box --protocols xhttp --xhttp-host edge.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"Xray"* ]]

  run_toastbox install -y --protocols vless --reality-sni www.example.com --skip-target-check --xhttp-host edge.example.com
  [ "$status" -ne 0 ]

  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com --xhttp-ws-port 10002
  [ "$status" -ne 0 ]

  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com --xhttp-tls none --xhttp-listen 0.0.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"loopback"* ]]

  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com --xhttp-tls none --xhttp-cert /tmp/c --xhttp-key /tmp/k
  [ "$status" -ne 0 ]

  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com --xhttp-tls files --xhttp-cert /tmp/c
  [ "$status" -ne 0 ]

  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com --xhttp-path /same --xhttp-ws-keepalive --xhttp-ws-path /same/sub
  [ "$status" -ne 0 ]

  run_toastbox show --xhttp-host edge.example.com
  [ "$status" -ne 0 ]
  run_toastbox rotate -y --xhttp-host edge.example.com
  [ "$status" -ne 0 ]
  run_toastbox refresh-cert --xhttp-tls none
  [ "$status" -ne 0 ]
}

@test "state_json and state_load round-trip xhttp + ws and reject malformed state" {
  sample_node
  CFG_VLESS=0
  CFG_SS=0
  sample_xhttp
  CFG_SERVER_ADDR="edge.example.com"
  CFG_XHTTP_HOST="edge.example.com"
  CFG_XHTTP_WS=1
  state_save
  local before
  before="$(state_json)"

  cfg_reset
  state_load
  [ "$CFG_XHTTP" = "1" ]
  [ "$CFG_XHTTP_TLS" = "none" ]
  [ "$CFG_XHTTP_LISTEN" = "127.0.0.1" ]
  [ "$CFG_XHTTP_PORT" = "10000" ]
  [ "$CFG_XHTTP_PUBLIC_PORT" = "443" ]
  [ "$CFG_XHTTP_HOST" = "edge.example.com" ]
  [ "$CFG_XHTTP_HOST" != "" ]
  [ "$(state_json)" = "$before" ]

  # Missing .xhttp in legacy schema-1 file loads cleanly as disabled.
  state_json | jq 'del(.xhttp)' >"$TB_STATE_FILE"
  cfg_reset
  state_load
  [ "$CFG_XHTTP" = "0" ]

  # Corrupt fields fail state_load cleanly.
  printf '%s\n' "$before" >"$BATS_TEST_TMPDIR/good.json"
  local bad
  for bad in \
    '.xhttp.tls = "acme"' \
    '.xhttp.path = "/bad?x=1"' \
    '.xhttp.mode = "broken"' \
    '.xhttp.ws.enabled = true | .xhttp.ws.path = "/edge-xhttp"' \
    '.xhttp.ws.enabled = true | .xhttp.ws.heartbeat = 0' \
    '.xhttp.tls = "files" | .xhttp.cert = ""'; do
    jq "$bad" "$BATS_TEST_TMPDIR/good.json" >"$TB_STATE_FILE"
    run state_load
    [ "$status" -ne 0 ]
    [[ "$output" == *"damaged"* ]]
  done
}

@test "xray_render and singbox_render handle xhttp none, ws, files and sockopt cleanly" {
  sample_node
  CFG_VLESS=0
  CFG_SS=0
  sample_xhttp
  CFG_SOCKOPT='{"tcpKeepAliveIdle":120}'

  # 1. tls=none with WS keepalive: loopback, no sockopt, modern fields only.
  CFG_XHTTP_WS=1
  CFG_XHTTP_LISTEN="::1"
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds | length')" = "2" ]
  [ "$(q '.inbounds[0].tag')" = "vless-xhttp" ]
  [ "$(q '.inbounds[0].listen')" = "::1" ]
  [ "$(q '.inbounds[0].port')" = "10000" ]
  [ "$(q '.inbounds[0].settings.users[0].id')" = "$CFG_XHTTP_UUID" ]
  [ "$(q '.inbounds[0].settings.users[0] | has("flow")')" = "false" ]
  [ "$(q '.inbounds[0].streamSettings.method')" = "xhttp" ]
  [ "$(q '.inbounds[0].streamSettings.security')" = "none" ]
  [ "$(q '.inbounds[0].streamSettings.xhttpSettings.path')" = "/edge-xhttp" ]
  [ "$(q '.inbounds[0].streamSettings.xhttpSettings.mode')" = "auto" ]
  [ "$(q '.inbounds[0].streamSettings | has("sockopt")')" = "false" ]
  [ "$(q '.inbounds[1].tag')" = "vless-ws-keepalive" ]
  [ "$(q '.inbounds[1].listen')" = "::1" ]
  [ "$(q '.inbounds[1].port')" = "10001" ]
  [ "$(q '.inbounds[1].streamSettings.method')" = "websocket" ]
  [ "$(q '.inbounds[1].streamSettings.wsSettings.path')" = "/edge-ws" ]
  [ "$(q '.inbounds[1].streamSettings.wsSettings.heartbeatPeriod')" = "30" ]
  [ "$(q '.inbounds[1].streamSettings | has("sockopt")')" = "false" ]
  [ "$(q '[.. | objects | keys[]] | map(select(. == "clients" or . == "dest" or . == "tcpSettings" or . == "network")) | length')" = "0" ]

  # 2. tls=files applies TLS cert/key, serverName + rejectUnknownSni, alpn array, host and sockopt.
  sample_hy2
  CFG_HY2=0
  CFG_XHTTP_TLS="files"
  CFG_XHTTP_LISTEN=""
  CFG_XHTTP_PORT=443
  CFG_XHTTP_ALPN="h3"
  CFG_XHTTP_CERT="$CFG_HY2_CERT"
  CFG_XHTTP_KEY="$CFG_HY2_KEY"
  CFG_XHTTP_WS_PORT=8443
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].streamSettings.security')" = "tls" ]
  [ "$(q '.inbounds[0].streamSettings.tlsSettings.serverName')" = "xhttp.example.com" ]
  [ "$(q '.inbounds[0].streamSettings.tlsSettings.rejectUnknownSni')" = "true" ]
  [ "$(q '.inbounds[0].streamSettings.tlsSettings.alpn | join(",")')" = "h2,http/1.1" ]
  [ "$(q '.inbounds[0].streamSettings.xhttpSettings.host')" = "xhttp.example.com" ]
  [ "$(q '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificate[0]')" = "-----BEGIN CERTIFICATE-----" ]
  [ "$(q '.inbounds[0].streamSettings.sockopt.tcpKeepAliveIdle')" = "120" ]
  [ "$(q '.inbounds[1].streamSettings.security')" = "tls" ]
  [ "$(q '.inbounds[1].streamSettings.tlsSettings.serverName')" = "xhttp.example.com" ]
  [ "$(q '.inbounds[1].streamSettings.tlsSettings.rejectUnknownSni')" = "true" ]
  [ "$(q '.inbounds[1].streamSettings.tlsSettings.alpn | join(",")')" = "http/1.1" ]
  [ "$(q '.inbounds[1].streamSettings.wsSettings.host')" = "xhttp.example.com" ]
  [ "$(q '.inbounds[1].streamSettings.sockopt.tcpKeepAliveIdle')" = "120" ]

  # 3. sing-box rejects xhttp.
  run singbox_render
  [ "$status" -ne 0 ]
}

@test "output formats (links, json, xray, mihomo, nginx, sing-box) behave as specified" {
  sample_node
  sample_xhttp
  CFG_XHTTP_WS=1
  CFG_XHTTP_CONNECT_ADDR="cf-vip.example.com"
  CFG_NODE_NAME='Node: "One" #1'
  CFG_XHTTP_KEY="SECRET-PRIVATE-KEY-DO-NOT-LEAK"

  OUT_VLESS=1
  OUT_SS=0
  OUT_HY2=0
  OUT_XHTTP=1

  # show_json strips private key and emits links.
  run show_json
  [ "$status" -eq 0 ]
  [ "$(q '.xhttp | has("key")')" = "false" ]
  [[ "$output" != *"$CFG_XHTTP_KEY"* ]]
  [[ "$(q '.links.xhttp')" == "vless://$CFG_XHTTP_UUID@cf-vip.example.com:443?"* ]]
  [[ "$(q '.links.xhttp')" == *"type=xhttp"* ]]
  [[ "$(q '.links.xhttp_ws')" == *"type=ws"* ]]

  # client_xray_json renders vless-xhttp, vless-ws-keepalive with useSystemCA, sniffing and keep-alive routing rules.
  OUT_VLESS=0
  run client_xray_json
  [ "$status" -eq 0 ]
  [ "$(q '.inbounds[0].sniffing.routeOnly')" = "true" ]
  [ "$(q '.outbounds | length')" = "2" ]
  [ "$(q '.outbounds[0].tag')" = "vless-xhttp" ]
  [ "$(q '.outbounds[0].settings.address')" = "cf-vip.example.com" ]
  [ "$(q '.outbounds[0].streamSettings.tlsSettings.serverName')" = "xhttp.example.com" ]
  [ "$(q '.outbounds[0].streamSettings.tlsSettings.useSystemCA')" = "true" ]
  [ "$(q '.outbounds[1].tag')" = "vless-ws-keepalive" ]
  [ "$(q '.outbounds[1].settings.address')" = "cf-vip.example.com" ]
  [ "$(q '.outbounds[1].streamSettings.wsSettings.host')" = "xhttp.example.com" ]
  [ "$(q '.outbounds[1].streamSettings.wsSettings.path')" = "/edge-ws" ]
  [ "$(q '.routing.rules[0].outboundTag')" = "vless-ws-keepalive" ]
  [ "$(q '.routing.rules[1].port')" = "22" ]
  [ "$(q '.routing.rules[1].outboundTag')" = "vless-ws-keepalive" ]

  # client_mihomo_yaml emits full YAML with -fallback nodes and proper rule ordering.
  OUT_VLESS=1
  run client_mihomo_yaml
  [ "$status" -eq 0 ]
  [[ "$output" == *"mixed-port: 1080"* ]]
  [[ "$output" == *"network: xhttp"* ]]
  [[ "$output" == *"servername: \"xhttp.example.com\""* ]]
  [[ "$output" == *"server: \"cf-vip.example.com\""* ]]
  [[ "$output" == *"xhttp-fallback"* ]]
  [[ "$output" == *"xhttp-ws-fallback"* ]]
  [[ "$output" == *"IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"* ]]
  [[ "$output" == *"IP-CIDR,169.254.0.0/16,DIRECT,no-resolve"* ]]
  # RFC1918 / CGNAT DIRECT,no-resolve rules must precede DST-PORT,22,Long-Conn-KeepAlive.
  local rfc_line cgnat_line ssh_line
  rfc_line="$(grep -n 'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve' <<<"$output" | cut -d: -f1)"
  cgnat_line="$(grep -n 'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve' <<<"$output" | cut -d: -f1)"
  ssh_line="$(grep -n 'DST-PORT,22,Long-Conn-KeepAlive' <<<"$output" | cut -d: -f1)"
  [ -n "$rfc_line" ] && [ -n "$cgnat_line" ] && [ -n "$ssh_line" ] && [ "$rfc_line" -lt "$ssh_line" ] && [ "$cgnat_line" -lt "$ssh_line" ]
  # Verify Python PyYAML if installed on test runner, else basic single-quote safety.
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c 'import sys, yaml; d=yaml.safe_load(sys.stdin.read()); assert d["mixed-port"]==1080 and len(d["proxies"])>=5' <<<"$output"
  fi

  # nginx snippet outputs location blocks only (and handles IPv6 upstreams and case-insensitive upgrade cleanly).
  OUT_VLESS=0
  CFG_XHTTP_LISTEN="::1"
  run nginx_xhttp_snippet
  [ "$status" -eq 0 ]
  ! grep -qE '^[[:space:]]*server[[:space:]]*\{' <<<"$output"
  [[ "$output" == *"grpc_pass            grpc://[::1]:10000;"* ]]
  [[ "$output" == *"proxy_pass         http://[::1]:10001;"* ]]
  [[ "$output" == *'!~* "^websocket$"'* ]]
  CFG_XHTTP_LISTEN="127.0.0.1"

  # show --format sing-box exports vless-ws-keepalive when WS is enabled, and fails on xhttp-only when WS is disabled.
  OUT_XHTTP=1
  OUT_VLESS=0
  CFG_XHTTP_WS=1
  run client_singbox_json
  [ "$status" -eq 0 ]
  local sb_json
  sb_json="$(client_singbox_json 2>/dev/null)"
  [ "$(jq -r '.outbounds[0].tag' <<<"$sb_json")" = "vless-ws-keepalive" ]
  [ "$(jq -r '.outbounds[0].transport.type' <<<"$sb_json")" = "ws" ]
  [ "$(jq -r '.route.final' <<<"$sb_json")" = "vless-ws-keepalive" ]

  OUT_VLESS=1
  sb_json="$(client_singbox_json 2>/dev/null)"
  [ "$(jq -r '.outbounds | map(select(.type == "vless")) | length' <<<"$sb_json")" = "2" ]
  [ "$(jq -r '.route.final' <<<"$sb_json")" = "vless-reality" ]
  [ "$(jq -r '.route.rules[0].action' <<<"$sb_json")" = "sniff" ]
  [ "$(jq -r '.route.rules[1].outbound' <<<"$sb_json")" = "vless-ws-keepalive" ]

  CFG_XHTTP_WS=0
  OUT_VLESS=0
  run client_singbox_json
  [ "$status" -ne 0 ]
  OUT_VLESS=1
  run client_singbox_json
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  sb_json="$(client_singbox_json 2>/dev/null)"
  [ "$(jq -r '.outbounds | map(select(.type == "vless")) | length' <<<"$sb_json")" = "1" ]
  CFG_XHTTP_WS=1

  # nginx format refuses files mode.
  CFG_XHTTP_TLS="files"
  run nginx_xhttp_snippet
  [ "$status" -ne 0 ]
}

@test "xhttp none install skips UFW & public IP probe, rotates UUID only, and refuses sing-box switch" {
  install_fake_cores
  export MOCK_FW_BACKEND="ufw"

  # No MOCK_DETECTED_ADDR set — XHTTP-only inherits server_addr from xhttp.host without probing public IP!
  run_toastbox install -y --protocols xhttp --xhttp-host edge.example.com \
    --xhttp-alpn h3 --xhttp-ws-keepalive --xhttp-ws-heartbeat 75
  [ "$status" -eq 0 ]
  [[ "$output" == *"125s"* ]]
  [[ "$output" == *"HTTP/3"* ]]
  [ "$(state .server_addr)" = "edge.example.com" ]
  [ "$(state .xhttp.enabled)" = "true" ]
  [ "$(state .xhttp.tls)" = "none" ]
  [ "$(state .xhttp.listen)" = "127.0.0.1" ]
  [ "$(state '.firewall.rules | length')" = "0" ]
  ! grep -q '^fw_open ' "$MOCK_LOG"

  local uuid1 path1 wspath1
  uuid1="$(state .xhttp.uuid)"
  path1="$(state .xhttp.path)"
  wspath1="$(state .xhttp.ws.path)"

  # Set and clear connect_addr idempotently without regenerating credentials.
  run_toastbox install -y --xhttp-connect-addr cf.example.com
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.connect_addr)" = "cf.example.com" ]
  [ "$(state .xhttp.uuid)" = "$uuid1" ]
  [ "$(state .xhttp.path)" = "$path1" ]

  run_toastbox install -y --xhttp-connect-addr ""
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.connect_addr)" = "" ]

  # show --format nginx & mihomo work via CLI.
  run_toastbox show --format nginx
  [ "$status" -eq 0 ]
  [[ "$output" == *"grpc_pass            grpc://127.0.0.1:10000;"* ]]

  run_toastbox show --format mihomo
  [ "$status" -eq 0 ]
  [[ "$output" == *"mixed-port: 1080"* ]]

  # show --format sing-box exports vless-ws-keepalive when WS is enabled.
  run_toastbox show --format sing-box
  [ "$status" -eq 0 ]
  [[ "$output" == *"vless-ws-keepalive"* ]]

  # rotate updates UUID while preserving paths.
  run_toastbox rotate -y
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.uuid)" != "$uuid1" ]
  [ "$(state .xhttp.path)" = "$path1" ]
  [ "$(state .xhttp.ws.path)" = "$wspath1" ]

  # Refuses switching to sing-box while xhttp is enabled.
  run_toastbox install -y --core sing-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"Xray"* ]]
}

@test "xhttp files mode opens UFW, picks 2053 if 8443 taken, supports refresh-cert (alone and alongside hy2), and rolls back cleanly" {
  local cert="$BATS_TEST_TMPDIR/origin.crt" key="$BATS_TEST_TMPDIR/origin.key"
  make_xhttp_cert_files "x1" "edge.example.com" "$cert" "$key"
  export MOCK_FW_BACKEND="ufw"

  # When 8443 is busy (either taken by an external process or by xhttp), companion WS auto-picks 2053 and emits the specific warning.
  export MOCK_BUSY_PORT="tcp:8443:nginx"
  run_toastbox install -y --protocols xhttp --xhttp-tls files --xhttp-host edge.example.com \
    --xhttp-port 443 --xhttp-cert "$cert" --xhttp-key "$key" --xhttp-ws-keepalive
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.port)" = "443" ]
  [ "$(state .xhttp.ws.port)" = "2053" ]
  [[ "$output" == *"XHTTP WS default port 8443/tcp is already in use; using fallback port 2053/tcp."* ]]
  unset MOCK_BUSY_PORT

  # A node whose state was lost still owns the old config file only by its
  # ToastBox marker: drop both to model a fresh node on 8443.
  rm -f "$TB_STATE_FILE" "$TOASTBOX_XRAY_CONFIG"
  : >"$MOCK_LOG"
  run_toastbox install -y --protocols xhttp --xhttp-tls files --xhttp-host edge.example.com \
    --xhttp-port 8443 --xhttp-cert "$cert" --xhttp-key "$key" --xhttp-ws-keepalive
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.port)" = "8443" ]
  [ "$(state .xhttp.ws.port)" = "2053" ]
  [[ "$output" == *"XHTTP WS default port 8443/tcp conflicts with another configured TCP port on this node; using fallback port 2053/tcp."* ]]
  grep -Fxq 'fw_open 8443/tcp' "$MOCK_LOG"
  grep -Fxq 'fw_open 2053/tcp' "$MOCK_LOG"

  local sha1 uuid1
  sha1="$(state .xhttp.cert_sha256)"
  uuid1="$(state .xhttp.uuid)"

  # Failed restart rolls back files cert change cleanly.
  local before_state
  before_state="$(<"$TB_STATE_FILE")"
  export MOCK_RESTART_FAILS=1
  run_toastbox install -y --xhttp-port 9443
  [ "$status" -ne 0 ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  unset MOCK_RESTART_FAILS

  # refresh-cert on unchanged files skips restart cleanly.
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  ! grep -q '^restart ' "$MOCK_LOG"

  # Update source cert and verify refresh-cert reloads xray and preserves uuid.
  make_xhttp_cert_files "x2" "edge.example.com" "$cert" "$key"
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.cert_sha256)" != "$sha1" ]
  [ "$(state .xhttp.uuid)" = "$uuid1" ]
  grep -Fxq 'restart xray' "$MOCK_LOG"

  # Stopped xray remains stopped on refresh-cert.
  make_xhttp_cert_files "x3" "edge.example.com" "$cert" "$key"
  export MOCK_SERVICE_INACTIVE=1
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  ! grep -q '^restart ' "$MOCK_LOG"
  unset MOCK_SERVICE_INACTIVE

  # Both hy2 (files) and xhttp (files) refresh cleanly together, and isolate faults per protocol.
  mkdir -p "$BATS_TEST_TMPDIR/hy2-certs"
  local hcert="$BATS_TEST_TMPDIR/hy2-certs/hy2.crt" hkey="$BATS_TEST_TMPDIR/hy2-certs/hy2.key"
  make_xhttp_cert_files "h1" "hy2.example.com" "$hcert" "$hkey"
  run_toastbox install -y --protocols hy2,xhttp --server-addr 203.0.113.10 \
    --hy2-port 9443 --hy2-cert "$hcert" --hy2-key "$hkey" --hy2-sni hy2.example.com
  [ "$status" -eq 0 ]
  local hsha1 xsha2
  hsha1="$(state .hy2.cert_sha256)"
  xsha2="$(state .xhttp.cert_sha256)"
  make_xhttp_cert_files "h2" "hy2.example.com" "$hcert" "$hkey"
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_sha256)" != "$hsha1" ]
  [ "$(state .xhttp.cert_sha256)" = "$xsha2" ]
  grep -Fxq 'restart xray' "$MOCK_LOG"

  # If xhttp cert source is missing/broken, hy2 renewal still succeeds and applies.
  local hsha2
  hsha2="$(state .hy2.cert_sha256)"
  rm -f "$cert"
  make_xhttp_cert_files "h3" "hy2.example.com" "$hcert" "$hkey"
  run_toastbox refresh-cert
  [ "$status" -ne 0 ]
  [ "$(state .hy2.cert_sha256)" != "$hsha2" ]

  # Scoped RENEWED_LINEAGE for hy2 ignores missing xhttp cert file and exits 0.
  local hsha3
  hsha3="$(state .hy2.cert_sha256)"
  make_xhttp_cert_files "h4" "hy2.example.com" "$hcert" "$hkey"
  RENEWED_LINEAGE="$(dirname "$hcert")" run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_sha256)" != "$hsha3" ]

  # Switching xhttp back to none closes old UFW TLS ports.
  : >"$MOCK_LOG"
  run_toastbox install -y --protocols xhttp --xhttp-tls none --xhttp-listen 127.0.0.1 --no-xhttp-ws-keepalive
  [ "$status" -eq 0 ]
  [ "$(state '.firewall.rules | length')" = "0" ]
  grep -Fxq 'fw_close 8443/tcp' "$MOCK_LOG"
  grep -Fxq 'fw_close 2053/tcp' "$MOCK_LOG"

  # XHTTP-only --xhttp-cert-hook certbot installs hook and refreshes via RENEWED_LINEAGE.
  cat >"$TB_SELF_PATH" <<EOF
#!/usr/bin/env bash
export TOASTBOX_SOURCE_ONLY=1
source "$REPO_ROOT/src/main.sh"
source "$REPO_ROOT/tests/unit/mocks.bash"
tb_main "\$@"
EOF
  chmod +x "$TB_SELF_PATH"
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/edge.example.com"
  mkdir -p "$live"
  make_xhttp_cert_files "xh1" "edge.example.com" "$live/fullchain.pem" "$live/privkey.pem"
  run_toastbox install -y --protocols xhttp --xhttp-tls files --xhttp-host edge.example.com \
    --xhttp-cert "$live/fullchain.pem" --xhttp-key "$live/privkey.pem" --xhttp-cert-hook certbot
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.certbot_hook)" = "true" ]
  [ -x "$TB_CERTBOT_HOOK_PATH" ]
  local hook_sha1
  hook_sha1="$(state .xhttp.cert_sha256)"
  make_xhttp_cert_files "xh2" "edge.example.com" "$live/fullchain.pem" "$live/privkey.pem"
  run env RENEWED_LINEAGE="$live" "$TB_CERTBOT_HOOK_PATH"
  [ "$status" -eq 0 ]
  [ "$(state .xhttp.cert_sha256)" != "$hook_sha1" ]
}

@test "interactive xhttp install asks tls, host, port, connect addr, and ws keepalive" {
  export MOCK_ANSWERS="$BATS_TEST_TMPDIR/answers"
  printf '%s\n' \
    "" \
    "6" \
    "1" \
    "edge.example.com" \
    "" \
    "cf.example.com" \
    "y" \
    "y" >"$MOCK_ANSWERS"

  run_toastbox install
  [ "$status" -eq 0 ]
  [ "$(state .core)" = "xray" ]
  [ "$(state .xhttp.enabled)" = "true" ]
  [ "$(state .xhttp.tls)" = "none" ]
  [ "$(state .xhttp.host)" = "edge.example.com" ]
  [ "$(state .xhttp.connect_addr)" = "cf.example.com" ]
  [ "$(state .xhttp.ws.enabled)" = "true" ]
}
