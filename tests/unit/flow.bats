#!/usr/bin/env bats
#
# End-to-end command flows with the host replaced by tests/unit/mocks.bash:
# the real argument parsing, parameter resolution, rendering, validation
# (against the fake cores), state handling and rollback all run.

load helper

setup() {
  load_toastbox
  export MOCK_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$MOCK_LOG"
  unset MOCK_RESTART_FAILS MOCK_BUSY_PORT MOCK_PROBE_RC MOCK_DETECTED_ADDR \
    MOCK_CLOCK_UNSYNCED MOCK_FW_BACKEND FAKE_CORE_REJECT FAKE_XRAY_VERSION FAKE_SINGBOX_VERSION \
    MOCK_ANSWERS MOCK_PROBE_FAIL_SNI MOCK_SERVICE_INACTIVE MOCK_REMOVE_FAILS MOCK_NO_IPV6
}

# answers LINE...: the replies a user would type, one per prompt.
answers() {
  export MOCK_ANSWERS="$BATS_TEST_TMPDIR/answers"
  printf '%s\n' "$@" >"$MOCK_ANSWERS"
}

state() { jq -r "$1" "$TB_STATE_FILE"; }
calls() { cat "$MOCK_LOG"; }

install_xray() {
  run_toastbox install -y --core xray --server-addr 203.0.113.10 \
    --reality-sni www.example.com --ss-port 28443 "$@"
}

@test "install: xray with both protocols" {
  install_xray
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install xray latest"* ]]
  [[ "$(calls)" == *"probe www.example.com www.example.com:443"* ]]
  [[ "$(calls)" == *"restart xray"* ]]

  [ "$(state .core)" = "xray" ]
  [ "$(state .vless.port)" = "443" ]
  [ "$(state .vless.target)" = "www.example.com:443" ]
  [ "$(state .ss.method)" = "2022-blake3-aes-128-gcm" ]
  [ "$(state .ss.network)" = "both" ]

  # The installed config is what the state describes.
  [ "$(jq -r '.inbounds[0].settings.users[0].id' "$TB_XRAY_CONFIG")" = "$(state .vless.uuid)" ]
  [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$TB_XRAY_CONFIG")" = "$(state .vless.private_key)" ]
  [ "$(jq -r '.inbounds[1].settings.password' "$TB_XRAY_CONFIG")" = "$(state .ss.password)" ]

  # ...and the summary on stdout carries both share links.
  [[ "$output" == *"vless://$(state .vless.uuid)@203.0.113.10:443?"* ]]
  [[ "$output" == *"ss://2022-blake3-aes-128-gcm:"*"@203.0.113.10:28443#"* ]]
  [[ "$output" == *"landing node"* ]]
}

@test "install: sing-box, Shadowsocks only, pinned version" {
  run_toastbox install -y --core sing-box --protocols ss --server-addr 203.0.113.10 \
    --ss-port 30000 --ss-method 2022-blake3-aes-256-gcm --core-version 1.14.4
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install sing-box 1.14.4"* ]]
  [[ "$(calls)" != *"probe"* ]]
  [ "$(state .vless.enabled)" = "false" ]
  [ "$(jq -r '[.inbounds[].type] | join(",")' "$TB_SINGBOX_CONFIG")" = "shadowsocks" ]
  [ "$(jq -r '.inbounds[0].listen_port' "$TB_SINGBOX_CONFIG")" = "30000" ]
  [[ "$output" != *"vless://"* ]]
  [[ "$output" == *"ss://2022-blake3-aes-256-gcm:"* ]]
}

@test "install: re-running keeps credentials and changes only what was asked" {
  install_xray
  local uuid key sspw
  uuid="$(state .vless.uuid)"
  key="$(state .vless.private_key)"
  sspw="$(state .ss.password)"

  : >"$MOCK_LOG"
  run_toastbox install -y --vless-port 8443 --block-bt
  [ "$status" -eq 0 ]
  # Already installed: the core is not installed again.
  [[ "$(calls)" != *"install xray"* ]]
  [ "$(state .vless.port)" = "8443" ]
  [ "$(state .block_bt)" = "true" ]
  [ "$(state .vless.uuid)" = "$uuid" ]
  [ "$(state .vless.private_key)" = "$key" ]
  [ "$(state .ss.password)" = "$sspw" ]
  [ "$(state .ss.port)" = "28443" ]
  [ "$(state .vless.sni)" = "www.example.com" ]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "8443" ]
  # The previous configuration was backed up.
  [ "$(find "$TB_BACKUP_DIR" -name 'xray-config-*.json' | wc -l)" -eq 1 ]
}

@test "install: a custom REALITY target survives as long as the SNI is unchanged" {
  install_xray --reality-target 203.0.113.50:8443
  [ "$(state .vless.target)" = "203.0.113.50:8443" ]
  run_toastbox install -y --name tokyo
  [ "$(state .vless.target)" = "203.0.113.50:8443" ]
  run_toastbox install -y --reality-sni www.example.org
  [ "$(state .vless.target)" = "www.example.org:443" ]
}

@test "install: the server address is detected when not given" {
  export MOCK_DETECTED_ADDR="198.51.100.7"
  run_toastbox install -y --core xray --protocols ss
  [ "$status" -eq 0 ]
  [ "$(state .server_addr)" = "198.51.100.7" ]
}

@test "install: fails cleanly when the address cannot be detected" {
  run_toastbox install -y --core xray --protocols ss
  [ "$status" -ne 0 ]
  [[ "$output" == *"--server-addr"* ]]
  [ ! -e "$TB_STATE_FILE" ]
}

@test "install: VLESS without a target domain is refused when not interactive" {
  run_toastbox install -y --core xray --server-addr 203.0.113.10
  [ "$status" -ne 0 ]
  [[ "$output" == *"--reality-sni"* ]]
  [[ "$(calls)" != *"install xray"* ]]
}

@test "install: a failing target probe stops --yes, --skip-target-check overrides" {
  export MOCK_PROBE_RC=2
  install_xray
  [ "$status" -ne 0 ]
  [[ "$output" == *"TLS 1.3"* ]]
  [ ! -e "$TB_STATE_FILE" ]
  [[ "$(calls)" != *"install xray"* ]]

  install_xray --skip-target-check
  [ "$status" -eq 0 ]
  [ "$(state .vless.sni)" = "www.example.com" ]
}

@test "install: a port taken by another program is reported before anything is installed" {
  export MOCK_BUSY_PORT="tcp:443:nginx"
  install_xray
  [ "$status" -ne 0 ]
  [[ "$output" == *"443/tcp"*"nginx"* ]]
  [[ "$(calls)" != *"install xray"* ]]
  [ ! -e "$TB_STATE_FILE" ]
}

@test "install: a port held by our own core is not a conflict" {
  export MOCK_BUSY_PORT="tcp:443:xray"
  install_xray
  [ "$status" -eq 0 ]
}

@test "install: VLESS and Shadowsocks cannot share a TCP port" {
  install_xray --ss-port 443
  [ "$status" -ne 0 ]
  [[ "$output" == *"443"* ]]
  [ ! -e "$TB_STATE_FILE" ]
}

@test "install: a core older than the minimum is refused" {
  export FAKE_XRAY_VERSION="25.12.8"
  install_xray
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
  [ ! -e "$TB_XRAY_CONFIG" ]
}

@test "install: a config the core rejects is never installed" {
  install_xray
  local before
  before="$(cat "$TB_XRAY_CONFIG")"
  : >"$MOCK_LOG"
  export FAKE_CORE_REJECT=1
  run_toastbox install -y --vless-port 8443
  [ "$status" -ne 0 ]
  [ "$(cat "$TB_XRAY_CONFIG")" = "$before" ]
  [ "$(state .vless.port)" = "443" ]
  [[ "$(calls)" != *"restart"* ]]
}

@test "install: a failed restart rolls the configuration back" {
  install_xray
  local before
  before="$(cat "$TB_XRAY_CONFIG")"
  export MOCK_RESTART_FAILS=1
  run_toastbox install -y --vless-port 8443
  [ "$status" -ne 0 ]
  [[ "$output" == *"Restored the previous configuration"* ]]
  [ "$(cat "$TB_XRAY_CONFIG")" = "$before" ]
  [ "$(state .vless.port)" = "443" ]
}

@test "install: switching cores stops the old service and keeps the credentials" {
  install_xray
  local uuid
  uuid="$(state .vless.uuid)"
  : >"$MOCK_LOG"
  run_toastbox install -y --core sing-box
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"stop xray"* ]]
  [[ "$(calls)" == *"install sing-box"* ]]
  [[ "$(calls)" == *"restart sing-box"* ]]
  [ "$(state .core)" = "sing-box" ]
  [ "$(state .vless.uuid)" = "$uuid" ]
  [ "$(jq -r '.inbounds[0].users[0].uuid' "$TB_SINGBOX_CONFIG")" = "$uuid" ]
}

@test "install: a foreign configuration is only replaced with --overwrite-config" {
  install_fake_cores
  mkdir -p "$(dirname "$TB_XRAY_CONFIG")"
  echo '{"inbounds": [{"port": 1234}]}' >"$TB_XRAY_CONFIG"
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    tb_main install --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443 </dev/null
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--overwrite-config"* ]]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "1234" ]

  # --yes alone must not replace it either.
  run_toastbox install -y --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443
  [ "$status" -ne 0 ]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "1234" ]
  [ ! -e "$TB_STATE_FILE" ]

  run_toastbox install -y --overwrite-config --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443
  [ "$status" -eq 0 ]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "28443" ]
  # The foreign configuration is preserved as a backup.
  [ "$(jq -r '.inbounds[0].port' "$TB_BACKUP_DIR"/xray-config-*.json)" = "1234" ]
}

@test "install: ufw rules follow the node and only our own are removed" {
  export MOCK_FW_BACKEND="ufw"
  install_xray
  [ "$(state '.firewall.rules | join(" ")')" = "443/tcp 28443/tcp 28443/udp" ]
  : >"$MOCK_LOG"
  run_toastbox install -y --vless-port 8443 --ss-network tcp
  [ "$(state '.firewall.rules | join(" ")')" = "8443/tcp 28443/tcp" ]
  [[ "$(calls)" == *"fw_close 443/tcp"* ]]
  [[ "$(calls)" == *"fw_close 28443/udp"* ]]
  [[ "$(calls)" == *"fw_open 8443/tcp"* ]]
  [[ "$(calls)" != *"fw_open 28443/tcp"* ]]

  : >"$MOCK_LOG"
  run_toastbox install -y --no-firewall --vless-port 9443
  [[ "$(calls)" != *"fw_"* ]]
}

@test "install: an unsynchronized clock is called out for Shadowsocks" {
  export MOCK_CLOCK_UNSYNCED=1
  install_xray
  [ "$status" -eq 0 ]
  [[ "$output" == *"NTP"* ]]
}

@test "install: messages follow --lang" {
  install_xray --lang zh
  [ "$status" -eq 0 ]
  [[ "$output" == *"节点部署完成"* ]]
  [[ "$output" == *"落地节点"* ]]
}

@test "show: formats" {
  install_xray
  run_toastbox show --format links
  [ "$status" -eq 0 ]
  [ "$(grep -c '^vless://' <<<"$output")" -eq 1 ]
  [ "$(grep -c '^ss://' <<<"$output")" -eq 1 ]

  run_toastbox show --format links --protocols ss
  [ "$(grep -c '^vless://' <<<"$output")" -eq 0 ]

  run_toastbox show --format json
  [ "$(jq -r .vless.uuid <<<"$output")" = "$(state .vless.uuid)" ]
  [ "$(jq -r '.links | keys | join(",")' <<<"$output")" = "ss,vless" ]

  run_toastbox show --format xray
  [ "$(jq -r '.outbounds[0].streamSettings.realitySettings.password' <<<"$output")" = "$(state .vless.public_key)" ]

  run_toastbox show --format sing-box --protocols ss
  [ "$(jq -r '.route.final' <<<"$output")" = "ss-2022" ]
}

@test "show: without a node" {
  run_toastbox show
  [ "$status" -ne 0 ]
  [[ "$output" == *"install"* ]]
}

@test "rotate: every credential changes, settings do not" {
  install_xray
  local uuid key pub sid sspw
  uuid="$(state .vless.uuid)" key="$(state .vless.private_key)" pub="$(state .vless.public_key)"
  sid="$(state .vless.short_id)" sspw="$(state .ss.password)"

  run_toastbox rotate -y
  [ "$status" -eq 0 ]
  [ "$(state .vless.uuid)" != "$uuid" ]
  [ "$(state .vless.private_key)" != "$key" ]
  [ "$(state .vless.public_key)" != "$pub" ]
  [ "$(state .vless.short_id)" != "$sid" ]
  [ "$(state .ss.password)" != "$sspw" ]
  [ "$(state .vless.port)" = "443" ]
  [ "$(state .vless.sni)" = "www.example.com" ]
  [ "$(jq -r '.inbounds[0].settings.users[0].id' "$TB_XRAY_CONFIG")" = "$(state .vless.uuid)" ]
  [[ "$output" == *"vless://$(state .vless.uuid)@"* ]]
}

@test "rotate: needs confirmation" {
  install_xray
  local uuid
  uuid="$(state .vless.uuid)"
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    tb_main rotate </dev/null
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [ "$(state .vless.uuid)" = "$uuid" ]
}

@test "update: reinstalls the core and restarts on a fresh render" {
  install_xray
  : >"$MOCK_LOG"
  run_toastbox update --core-version 26.11.9
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install xray 26.11.9"* ]]
  [[ "$(calls)" == *"restart xray"* ]]
  [[ "$output" == *"26.11.9"* ]]
}

@test "uninstall: removes the core and the state, keeps backups" {
  export MOCK_FW_BACKEND="ufw"
  install_xray
  run_toastbox install -y --vless-port 8443
  : >"$MOCK_LOG"
  run_toastbox uninstall -y
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"stop xray"* ]]
  [[ "$(calls)" == *"remove xray purge=0"* ]]
  [[ "$(calls)" == *"fw_close 8443/tcp"* ]]
  [ ! -e "$TB_STATE_FILE" ]
  [ -d "$TB_BACKUP_DIR" ]
}

@test "uninstall --purge: removes everything ToastBox created" {
  install_xray
  : >"$MOCK_LOG"
  run_toastbox uninstall -y --purge
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"remove xray purge=1"* ]]
  [ ! -e "$TB_STATE_DIR" ]
}

@test "uninstall: refuses to run unconfirmed" {
  install_xray
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    tb_main uninstall </dev/null
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [ -e "$TB_STATE_FILE" ]
  [[ "$(cat "$MOCK_LOG")" != *"remove xray"* ]]
}

@test "interactive: the menu walks through a complete installation" {
  export MOCK_DETECTED_ADDR="198.51.100.7"
  #        lang menu core proto addr port sni             ssport method proceed
  answers  2    1    ""   ""    ""   ""   www.example.com 28443  2      y
  run_toastbox
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_ANSWERS" ]
  [[ "$output" == *"节点部署完成"* ]]
  [ "$(state .core)" = "xray" ]
  [ "$(state .server_addr)" = "198.51.100.7" ]
  [ "$(state .vless.port)" = "443" ]
  [ "$(state .vless.sni)" = "www.example.com" ]
  [ "$(state .ss.port)" = "28443" ]
  [ "$(state .ss.method)" = "2022-blake3-aes-256-gcm" ]
  [[ "$(calls)" == *"prompt: Language / 语言"* ]]
}

@test "interactive: invalid answers are asked again" {
  #       core     proto addr         port  port sni  sni             ssport method proceed
  answers sing-box 2     203.0.113.10 99999 8443 nope www.example.com
  run_toastbox install --lang en
  [ "$status" -eq 0 ]
  [[ "$output" == *'"99999" is not valid'* ]]
  [[ "$output" == *'"nope" is not valid'* ]]
  [ "$(state .core)" = "sing-box" ]
  [ "$(state .ss.enabled)" = "false" ]
  [ "$(state .vless.port)" = "8443" ]
}

@test "interactive: a rejected target leads back to the domain prompt" {
  export MOCK_PROBE_FAIL_SNI="bad.example.com"
  #       sni             anyway sni             proceed
  answers bad.example.com n      www.example.com y
  run_toastbox install --lang en --core xray --protocols vless --server-addr 203.0.113.10 --vless-port 443
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not valid for bad.example.com"* ]]
  [ "$(state .vless.sni)" = "www.example.com" ]
}

@test "interactive: a rejected target can be kept on request" {
  export MOCK_PROBE_FAIL_SNI="bad.example.com"
  answers bad.example.com y y
  run_toastbox install --lang en --core xray --protocols vless --server-addr 203.0.113.10 --vless-port 443
  [ "$status" -eq 0 ]
  [ "$(state .vless.sni)" = "bad.example.com" ]
}

@test "interactive: declining the plan changes nothing" {
  answers n
  run_toastbox install --lang en --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443 --ss-method 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Nothing was changed"* ]]
  [[ "$(calls)" != *"install xray"* ]]
  [ ! -e "$TB_STATE_FILE" ]
}

@test "interactive: reconfiguring offers the current values as defaults" {
  install_xray
  local uuid
  uuid="$(state .vless.uuid)"
  #       core proto addr port sni ssport method proceed
  answers ""   ""    ""   ""   ""  ""     ""     ""
  run_toastbox install --lang en
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_ANSWERS" ]
  [[ "$(calls)" == *"[www.example.com]"* ]]
  [[ "$(calls)" == *"[28443]"* ]]
  [ "$(state .vless.uuid)" = "$uuid" ]
  [ "$(state .vless.port)" = "443" ]
}

@test "rollback: a config that was not in service is never started" {
  # The sing-box package ships a sample config (a Shadowsocks server with a
  # published password) and leaves the service stopped.
  install_fake_cores
  mkdir -p "$(dirname "$TB_SINGBOX_CONFIG")"
  echo '{"inbounds": [{"type": "shadowsocks", "listen_port": 8080}]}' >"$TB_SINGBOX_CONFIG"
  export MOCK_SERVICE_INACTIVE=1 MOCK_RESTART_FAILS=1
  run_toastbox install -y --overwrite-config --core sing-box --protocols ss --server-addr 203.0.113.10 --ss-port 28443
  [ "$status" -ne 0 ]
  [[ "$output" == *"left stopped"* ]]
  # One start attempt (ours), then stopped (even if hop NAT cleanup logs afterwards): no restart on the old file.
  [ "$(grep -c '^restart sing-box$' "$MOCK_LOG")" -eq 1 ]
  [ "$(grep -c '^stop sing-box$' "$MOCK_LOG")" -eq 1 ]
  [ "$(grep -E '^(restart|stop) sing-box$' "$MOCK_LOG" | tail -n 1)" = "stop sing-box" ]
  [ ! -e "$TB_STATE_FILE" ]
}

@test "core switch: the old core keeps running until the new one is validated" {
  install_xray
  : >"$MOCK_LOG"
  export FAKE_CORE_REJECT=1
  run_toastbox install -y --core sing-box
  [ "$status" -ne 0 ]
  [[ "$(calls)" != *"stop xray"* ]]
  [ "$(state .core)" = "xray" ]
}

@test "core switch: the old core is started again when the new one fails" {
  install_xray
  : >"$MOCK_LOG"
  export MOCK_RESTART_FAILS=1 MOCK_SERVICE_INACTIVE=1
  run_toastbox install -y --core sing-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"Started the previous xray service again"* ]]
  grep -qx 'restart xray' "$MOCK_LOG"
  [ "$(grep -E '^restart (xray|sing-box)$' "$MOCK_LOG" | tail -n 1)" = "restart xray" ]
  [ "$(state .core)" = "xray" ]
}

@test "core switch: ports held by the old core are not a conflict" {
  install_xray
  export MOCK_BUSY_PORT="tcp:443:xray"
  run_toastbox install -y --core sing-box
  [ "$status" -eq 0 ]
  [ "$(state .core)" = "sing-box" ]
}

@test "uninstall --core: removing a leftover core keeps the node" {
  install_xray
  run_toastbox install -y --core sing-box
  : >"$MOCK_LOG"
  run_toastbox uninstall -y --core xray
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"remove xray purge=0"* ]]
  [[ "$(calls)" != *"remove sing-box"* ]]
  [ "$(state .core)" = "sing-box" ]
}

@test "interactive: a foreign configuration can be replaced at the prompt" {
  install_fake_cores
  mkdir -p "$(dirname "$TB_XRAY_CONFIG")"
  echo '{"inbounds": [{"port": 1234}]}' >"$TB_XRAY_CONFIG"
  #       proceed overwrite
  answers y       y
  run_toastbox install --lang en --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443 --ss-method 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "28443" ]
}

@test "install: a leftover config without a core binary still requires --overwrite-config" {
  mkdir -p "$(dirname "$TB_XRAY_CONFIG")"
  echo '{"inbounds": [{"port": 1234}]}' >"$TB_XRAY_CONFIG"
  rm -f "$TB_XRAY_BIN"

  run_toastbox install -y --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443
  [ "$status" -ne 0 ]
  [[ "$output" == *"--overwrite-config"* ]]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "1234" ]
  [ ! -e "$TB_STATE_FILE" ]

  run_toastbox install -y --overwrite-config --core xray --protocols ss --server-addr 203.0.113.10 --ss-port 28443
  [ "$status" -eq 0 ]
  [ "$(jq -r '.inbounds[0].port' "$TB_XRAY_CONFIG")" = "28443" ]
  [ "$(jq -r '.inbounds[0].port' "$TB_BACKUP_DIR"/xray-config-*.json)" = "1234" ]
}

@test "rotate: a config write failure aborts before saving state" {
  install_xray
  local uuid before
  uuid="$(state .vless.uuid)"
  before="$(<"$TB_XRAY_CONFIG")"

  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    xray_install_config() { return 1; }
    tb_main rotate -y
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" != *"New credentials are active"* ]]
  [ "$(state .vless.uuid)" = "$uuid" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before" ]
}

@test "apply_config: a backup failure aborts before stopping the old core" {
  install_xray
  local before
  before="$(<"$TB_XRAY_CONFIG")"
  : >"$MOCK_LOG"

  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    backup_file() { return 1; }
    tb_main install -y --vless-port 8443
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [ "$(state .vless.port)" = "443" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before" ]
  [[ "$(calls)" != *"restart"* ]]
}

@test "install and update: --core-version below the minimum is rejected before installing" {
  install_xray
  : >"$MOCK_LOG"

  run_toastbox install -y --core xray --core-version 26.5.9
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
  [[ "$(calls)" != *"install xray"* ]]

  run_toastbox update --core-version 26.5.9
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
  [[ "$(calls)" != *"install xray"* ]]

  run_toastbox install -y --core sing-box --protocols ss --server-addr 203.0.113.10 \
    --ss-port 28443 --core-version 1.11.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
  [[ "$(calls)" != *"install sing-box"* ]]
}

@test "update: an incompatible new xray binary is rolled back when config apply fails" {
  install_xray
  cat >"$TB_XRAY_BIN" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version) echo "Xray 26.11.9 (old)" ;;
  run) jq -e . "$4" >/dev/null ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$TB_XRAY_BIN"
  : >"$MOCK_LOG"

  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    xray_install() {
      echo "install xray ${1:-latest}" >>"$MOCK_LOG"
      cat >"$TB_XRAY_BIN" <<"XEOF"
#!/usr/bin/env bash
case "${1:-}" in
  version) echo "Xray 27.0.0 (broken)" ;;
  run) echo "rejected" >&2; exit 23 ;;
  *) exit 2 ;;
esac
XEOF
      chmod +x "$TB_XRAY_BIN"
    }
    tb_main update
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Restored the previous xray binary"* ]]
  [[ "$("$TB_XRAY_BIN" version)" == *"26.11.9"* ]]
  [[ "$(calls)" == *"restart xray"* ]]
}

@test "uninstall: removal failure preserves node state, firewall rules and toastbox binary" {
  export MOCK_FW_BACKEND="ufw"
  install_xray
  printf '#!/usr/bin/env bash\n' >"$TB_SELF_PATH"
  chmod +x "$TB_SELF_PATH"
  : >"$MOCK_LOG"

  export MOCK_REMOVE_FAILS=1
  run_toastbox uninstall -y --purge
  [ "$status" -ne 0 ]
  [[ "$output" != *"were removed"* ]]
  [ -e "$TB_STATE_FILE" ]
  [ -e "$TB_SELF_PATH" ]
  [[ "$(calls)" != *"fw_close"* ]]
}

@test "singbox_remove: propagates apt errors and preserves files on failure" {
  mkdir -p "$(dirname "$TB_SINGBOX_CONFIG")"
  echo '{"inbounds":[]}' >"$TB_SINGBOX_CONFIG"

  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    apt-get() { return 100; }
    singbox_remove 1
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [ -e "$TB_SINGBOX_CONFIG" ]
}

@test "xray_config_perms: avoids 0644 and follows the systemd service identity" {
  # Fallback without xray group/user defaults to 0600 root:root.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    service_unit_exists() { return 1; }
    getent() { return 2; }
    xray_config_perms
    printf "%s %s:%s\n" "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "600 root:root" ]

  # Installed systemd unit running as root stays 0600 even if xray group exists.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    service_unit_exists() { return 0; }
    service_unit_prop() {
      case "$2" in
        User) printf "root" ;;
        Group) printf "" ;;
        DynamicUser) printf "no" ;;
      esac
    }
    getent() { return 0; }
    xray_config_perms
    printf "%s %s:%s\n" "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "600 root:root" ]

  # Installed systemd unit running as User=xray Group=xray uses 0640 root:xray.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    service_unit_exists() { return 0; }
    service_unit_prop() {
      case "$2" in
        User) printf "xray" ;;
        Group) printf "xray" ;;
        DynamicUser) printf "no" ;;
      esac
    }
    getent() { [[ "$1" == "group" && "$2" == "xray" ]]; }
    xray_config_perms
    printf "%s %s:%s\n" "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "640 root:xray" ]

  # Unprivileged user in nogroup (e.g. nobody) restricts file to that UID only.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    service_unit_exists() { return 0; }
    service_unit_prop() {
      case "$2" in
        User) printf "nobody" ;;
        Group) printf "" ;;
        DynamicUser) printf "no" ;;
      esac
    }
    getent() {
      case "$1:$2" in
        passwd:nobody) printf "nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n" ;;
        group:65534) printf "nogroup:x:65534:\n" ;;
        *) return 2 ;;
      esac
    }
    xray_config_perms
    printf "%s %s:%s\n" "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "600 nobody:root" ]

  # DynamicUser without a static group refuses world-readable permissions.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    service_unit_exists() { return 0; }
    service_unit_prop() {
      case "$2" in
        DynamicUser) printf "yes" ;;
        *) printf "" ;;
      esac
    }
    xray_config_perms
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
}

@test "install: Hy2-only on sing-box generates self-signed cert, opens UDP, and stays Hy2-only on re-run" {
  export MOCK_FW_BACKEND="ufw"
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-port 443 --hy2-obfs salamander --hy2-masquerade https://www.example.com
  [ "$status" -eq 0 ]
  [ "$(state .core)" = "sing-box" ]
  [ "$(state .vless.enabled)" = "false" ]
  [ "$(state .ss.enabled)" = "false" ]
  [ "$(state .hy2.enabled)" = "true" ]
  [ "$(state .hy2.port)" = "443" ]
  [ "$(state .hy2.tls)" = "self-signed" ]
  [ "$(state .hy2.obfs)" = "salamander" ]
  [ "$(state '.firewall.rules | join(" ")')" = "443/udp" ]
  [ "$(jq -r '[.inbounds[].type] | join(",")' "$TB_SINGBOX_CONFIG")" = "hysteria2" ]
  [[ "$output" == *"hysteria2://"* ]]

  local pw cert sha
  pw="$(state .hy2.password)"
  cert="$(state .hy2.cert)"
  sha="$(state .hy2.cert_sha256)"

  # Re-running without --protocols keeps Hy2-only and preserves cert/password.
  run_toastbox install -y --hy2-port 8443
  [ "$status" -eq 0 ]
  [ "$(state .vless.enabled)" = "false" ]
  [ "$(state .ss.enabled)" = "false" ]
  [ "$(state .hy2.enabled)" = "true" ]
  [ "$(state .hy2.port)" = "8443" ]
  [ "$(state .hy2.password)" = "$pw" ]
  [ "$(state .hy2.cert)" = "$cert" ]
  [ "$(state .hy2.cert_sha256)" = "$sha" ]
  [ "$(state '.firewall.rules | join(" ")')" = "8443/udp" ]
}

@test "install: VLESS TCP and TCP-only SS may share port 443 with Hy2, while SS UDP conflicts" {
  # VLESS 443/tcp + Hy2 443/udp is allowed.
  run_toastbox install -y --core xray --protocols vless,hy2 --server-addr 203.0.113.10 \
    --reality-sni www.example.com --vless-port 443 --hy2-port 443
  [ "$status" -eq 0 ]
  [ "$(state .vless.port)" = "443" ]
  [ "$(state .hy2.port)" = "443" ]

  # SS with UDP on the same port as Hy2 is rejected.
  run_toastbox install -y --core xray --protocols ss,hy2 --server-addr 203.0.113.10 \
    --ss-port 443 --ss-network both --hy2-port 443
  [ "$status" -ne 0 ]
  [[ "$output" == *"443"* ]]

  # SS TCP-only on the same port as Hy2 UDP is allowed.
  run_toastbox install -y --core xray --protocols ss,hy2 --server-addr 203.0.113.10 \
    --ss-port 443 --ss-network tcp --hy2-port 443
  [ "$status" -eq 0 ]
}

@test "install: adding and removing Hy2 updates firewall rules and keeps existing credentials" {
  export MOCK_FW_BACKEND="ufw"
  install_xray
  local uuid
  uuid="$(state .vless.uuid)"

  run_toastbox install -y --protocols all --hy2-port 8443
  [ "$status" -eq 0 ]
  [ "$(state .vless.uuid)" = "$uuid" ]
  [ "$(state .hy2.enabled)" = "true" ]
  [ "$(state '.firewall.rules | join(" ")')" = "443/tcp 28443/tcp 28443/udp 8443/udp" ]

  # Removing Hy2 removes its UDP rule.
  : >"$MOCK_LOG"
  run_toastbox install -y --protocols both
  [ "$status" -eq 0 ]
  [ "$(state .hy2.enabled)" = "false" ]
  [[ "$(calls)" == *"fw_close 8443/udp"* ]]
  [ "$(state '.firewall.rules | join(" ")')" = "443/tcp 28443/tcp 28443/udp" ]
}

@test "install: --hy2-tls files imports certificate pair and rejects invalid combos" {
  tls_generate_self_signed "203.0.113.10" "hy2.example.com"
  printf '%s\n' "$TLS_CERT_PEM" >"$BATS_TEST_TMPDIR/fullchain.pem"
  printf '%s\n' "$TLS_KEY_PEM" >"$BATS_TEST_TMPDIR/privkey.pem"

  # Missing files fails cleanly.
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 --hy2-tls files
  [ "$status" -ne 0 ]

  # Incompatible --hy2-renew-cert with files fails cleanly.
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$BATS_TEST_TMPDIR/fullchain.pem" --hy2-key "$BATS_TEST_TMPDIR/privkey.pem" --hy2-renew-cert
  [ "$status" -ne 0 ]

  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$BATS_TEST_TMPDIR/fullchain.pem" --hy2-key "$BATS_TEST_TMPDIR/privkey.pem"
  [ "$status" -eq 0 ]
  [ "$(state .hy2.tls)" = "files" ]
  [ "$(state .hy2.sni)" = "hy2.example.com" ]
  [ "$(state .hy2.cert_sha256)" = "$TLS_CERT_SHA256" ]

  # Re-running without --hy2-cert keeps the imported snapshot.
  run_toastbox install -y --hy2-port 8443
  [ "$status" -eq 0 ]
  [ "$(state .hy2.port)" = "8443" ]
  [ "$(state .hy2.cert_sha256)" = "$TLS_CERT_SHA256" ]
}

@test "hy2 lifecycle: --hy2-renew-cert renews cert, rotate keeps cert, core switch preserves all" {
  run_toastbox install -y --core xray --protocols hy2 --server-addr 203.0.113.10 --hy2-obfs salamander
  [ "$status" -eq 0 ]
  local pw1 obfs1 sha1
  pw1="$(state .hy2.password)"
  obfs1="$(state .hy2.obfs_password)"
  sha1="$(state .hy2.cert_sha256)"

  # rotate changes auth + obfs passwords, preserves cert.
  run_toastbox rotate -y
  [ "$status" -eq 0 ]
  [ "$(state .hy2.password)" != "$pw1" ]
  [ "$(state .hy2.obfs_password)" != "$obfs1" ]
  [ "$(state .hy2.cert_sha256)" = "$sha1" ]

  local pw2 sha2
  pw2="$(state .hy2.password)"

  # Switching to sing-box preserves Hy2 credentials and cert.
  run_toastbox install -y --core sing-box
  [ "$status" -eq 0 ]
  [ "$(state .core)" = "sing-box" ]
  [ "$(state .hy2.password)" = "$pw2" ]
  [ "$(state .hy2.cert_sha256)" = "$sha1" ]

  # --hy2-renew-cert regenerates the self-signed certificate.
  run_toastbox install -y --hy2-renew-cert
  [ "$status" -eq 0 ]
  sha2="$(state .hy2.cert_sha256)"
  [ "$sha2" != "$sha1" ]

  # show --format hysteria2 outputs official client config.
  run_toastbox show --format hysteria2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tls.pinSHA256' <<<"$output")" = "$sha2" ]
  [ "$(jq -r '.tls.insecure' <<<"$output")" = "true" ]
}
