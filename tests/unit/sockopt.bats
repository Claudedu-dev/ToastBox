#!/usr/bin/env bats

load helper

setup() {
  load_toastbox
  sample_node
  export MOCK_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$MOCK_LOG"
  unset MOCK_RESTART_FAILS FAKE_CORE_REJECT MOCK_SERVICE_INACTIVE MOCK_ANSWERS
}

profile() {
  printf '%s' '{"tcpKeepAliveIdle":120,"tcpKeepAliveInterval":30,"tcpUserTimeout":120000}'
}

# Use a pre-existing node for command tests; no system service or network is used.
saved_node() {
  CFG_SOCKOPT="$(profile)"
  install_fake_cores
  mkdir -p "$(dirname "$TB_XRAY_CONFIG")"
  xray_render >"$TB_XRAY_CONFIG"
  state_save
}

assert_profile() {
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = "$(profile)" ]
  [ "$(jq -c '.inbounds[0].streamSettings.sockopt' "$TB_XRAY_CONFIG")" = "$(profile)" ]
  [ "$(jq -c '.inbounds[1].streamSettings.sockopt' "$TB_XRAY_CONFIG")" = "$(profile)" ]
}

@test "sockopt: flags parse both forms and canonicalize decimal integers" {
  parse_args install --tcp-keepalive-idle=000120 --tcp-keepalive-interval 030 --tcp-user-timeout=120000
  validate_options
  [ "$OPT_TCP_KEEPALIVE_IDLE" = "120" ]
  [ "$OPT_TCP_KEEPALIVE_INTERVAL" = "30" ]
  [ "$OPT_TCP_USER_TIMEOUT" = "120000" ]
  resolve_sockopt
  [ "$CFG_SOCKOPT" = "$(profile)" ]
}

@test "sockopt: zero clears and Linux/int32 upper limits are accepted" {
  [ "$(norm_tcp_keepalive 0)" = "0" ]
  [ "$(norm_tcp_keepalive 32767)" = "32767" ]
  [ "$(norm_tcp_user_timeout 2147483647)" = "2147483647" ]
  parse_args install --tcp-keepalive-idle 32767 --tcp-keepalive-interval 32767 --tcp-user-timeout 2147483647
  validate_options
  resolve_sockopt
  sockopt_valid "$CFG_SOCKOPT"
}

@test "sockopt: invalid and empty CLI values fail before a command runs" {
  local flag value
  for flag in --tcp-keepalive-idle --tcp-keepalive-interval --tcp-user-timeout; do
    for value in '' -1 1.5 false '1 2' 1e3 0x10 999999999999999999999999 "\$(id)"; do
      run_toastbox install "$flag=$value"
      [ "$status" -ne 0 ]
      [[ "$output" == *"Invalid value for $flag"* ]]
    done
    run_toastbox install "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs a value"* ]]
  done
  run_toastbox install --tcp-keepalive-idle 32768
  [ "$status" -ne 0 ]
  run_toastbox install --tcp-keepalive-interval 32768
  [ "$status" -ne 0 ]
  run_toastbox install --tcp-user-timeout 2147483648
  [ "$status" -ne 0 ]
  [ ! -s "$MOCK_LOG" ]
}

@test "sockopt: install-only flags cannot be silently ignored by other commands" {
  local command flag
  for command in show update rotate uninstall; do
    for flag in --tcp-keepalive-idle=120 --tcp-keepalive-interval=30 --tcp-user-timeout=120000 --reset-sockopt; do
      run_toastbox "$command" "$flag"
      [ "$status" -ne 0 ]
      [[ "$output" == *"only accepted with install"* ]]
    done
  done
  [ ! -s "$MOCK_LOG" ]
}

@test "sockopt: state round-trip keeps integer types and credentials" {
  CFG_SOCKOPT="$(profile)"
  local before
  before="$(state_json)"
  state_save
  cfg_reset
  state_load
  [ "$CFG_SOCKOPT" = "$(profile)" ]
  [ "$(state_json)" = "$before" ]
  [ "$(jq -r '[.sockopt[] | type] | unique | join(",")' "$TB_STATE_FILE")" = "number" ]
}

@test "sockopt: schema-1 states without the field load without tuning" {
  state_json | jq 'del(.sockopt)' >"$BATS_TEST_TMPDIR/old.json"
  mkdir -p "$TB_STATE_DIR"
  cp "$BATS_TEST_TMPDIR/old.json" "$TB_STATE_FILE"
  CFG_SOCKOPT="$(profile)"
  state_load
  [ "$TB_HAS_STATE" = "1" ]
  [ "$CFG_SOCKOPT" = '{}' ]
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(jq '[.. | objects | has("sockopt")] | any' <<<"$output")" = "false" ]
}

@test "sockopt: invalid saved settings are rejected, not silently dropped" {
  local invalid
  state_save
  cp "$TB_STATE_FILE" "$BATS_TEST_TMPDIR/good.json"
  for invalid in 'false' 'true' '[]' '"oops"' '{"unknown":1}' \
    '{"tcpKeepAliveIdle":"120"}' '{"tcpKeepAliveIdle":null}' \
    '{"tcpKeepAliveIdle":0}' '{"tcpKeepAliveIdle":-1}' \
    '{"tcpKeepAliveIdle":1.5}' '{"tcpKeepAliveInterval":32768}' \
    '{"tcpUserTimeout":2147483648}'; do
    jq --argjson value "$invalid" '.sockopt = $value' "$BATS_TEST_TMPDIR/good.json" >"$TB_STATE_FILE"
    run state_load
    [ "$status" -ne 0 ]
    [[ "$output" == *"damaged"* ]]
  done
}

@test "sockopt: defaults do not add any server-side socket override" {
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(jq '[.. | objects | has("sockopt")] | any' <<<"$output")" = "false" ]
  run singbox_render
  [ "$status" -eq 0 ]
}

@test "sockopt: Xray VLESS and SS TCP render the saved numeric options" {
  CFG_SOCKOPT="$(profile)"
  local network
  for network in tcp both; do
    CFG_SS_NETWORK="$network"
    run xray_render
    [ "$status" -eq 0 ]
    [ "$(jq -c '.inbounds[0].streamSettings.sockopt' <<<"$output")" = "$(profile)" ]
    [ "$(jq -c '.inbounds[1].streamSettings.sockopt' <<<"$output")" = "$(profile)" ]
    [ "$(jq -r '.inbounds[0].streamSettings.method' <<<"$output")" = "raw" ]
    [ "$(jq -r '.inbounds[1].settings.password' <<<"$output")" = "$CFG_SS_PASSWORD" ]
    [ "$(jq '[.outbounds[] | has("streamSettings")] | any' <<<"$output")" = "false" ]
  done
}

@test "sockopt: UDP-only SS does not acquire TCP stream settings" {
  CFG_SOCKOPT="$(profile)"
  CFG_SS_NETWORK=udp
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(jq -c '.inbounds[0].streamSettings.sockopt' <<<"$output")" = "$(profile)" ]
  [ "$(jq '.inbounds[1] | has("streamSettings")' <<<"$output")" = "false" ]
  CFG_VLESS=0
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(jq '[.. | objects | has("sockopt")] | any' <<<"$output")" = "false" ]
}

@test "sockopt: only explicitly set keys are emitted" {
  CFG_SOCKOPT='{"tcpKeepAliveInterval":30}'
  run xray_render
  [ "$status" -eq 0 ]
  [ "$(jq -c '.inbounds[0].streamSettings.sockopt' <<<"$output")" = "$CFG_SOCKOPT" ]
}

@test "sockopt: client exports stay unchanged" {
  select_output_protocols
  local before_xray before_singbox
  before_xray="$(client_xray_json)"
  before_singbox="$(client_singbox_json)"
  CFG_SOCKOPT="$(profile)"
  [ "$(client_xray_json)" = "$before_xray" ]
  [ "$(client_singbox_json)" = "$before_singbox" ]
}

@test "sockopt: direct sing-box rendering refuses Xray-only overrides" {
  CFG_SOCKOPT="$(profile)"
  run singbox_render
  [ "$status" -ne 0 ]
  [[ "$output" == *"only by Xray"* ]]
}

@test "sockopt: install saves overrides without replacing credentials" {
  saved_node
  local uuid key password
  uuid="$CFG_VLESS_UUID" key="$CFG_REALITY_PRIVATE_KEY" password="$CFG_SS_PASSWORD"
  # Replace the saved profile with a legacy state before the first CLI change.
  state_json | jq 'del(.sockopt)' >"$TB_STATE_FILE"
  run_toastbox install -y --no-firewall --tcp-keepalive-idle 120 --tcp-keepalive-interval 30 --tcp-user-timeout 120000
  [ "$status" -eq 0 ]
  assert_profile
  [ "$(jq -r '.vless.uuid' "$TB_STATE_FILE")" = "$uuid" ]
  [ "$(jq -r '.vless.private_key' "$TB_STATE_FILE")" = "$key" ]
  [ "$(jq -r '.ss.password' "$TB_STATE_FILE")" = "$password" ]
}

@test "sockopt: re-install and update replay state after external JSON edits" {
  saved_node
  local command
  for command in install update; do
    jq 'del(.inbounds[].streamSettings.sockopt)' "$TB_XRAY_CONFIG" >"$BATS_TEST_TMPDIR/edit.json"
    cp "$BATS_TEST_TMPDIR/edit.json" "$TB_XRAY_CONFIG"
    run_toastbox "$command" -y
    [ "$status" -eq 0 ]
    assert_profile
  done
}

@test "sockopt: rotation changes credentials but preserves overrides" {
  saved_node
  local uuid="$CFG_VLESS_UUID"
  run_toastbox rotate -y
  [ "$status" -eq 0 ]
  assert_profile
  [ "$(jq -r '.vless.uuid' "$TB_STATE_FILE")" != "$uuid" ]
}

@test "sockopt: partial updates and per-field resets preserve other settings" {
  saved_node
  run_toastbox install -y --tcp-keepalive-idle 240 --tcp-user-timeout 0
  [ "$status" -eq 0 ]
  local expected='{"tcpKeepAliveIdle":240,"tcpKeepAliveInterval":30}'
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = "$expected" ]
  [ "$(jq -c '.inbounds[0].streamSettings.sockopt' "$TB_XRAY_CONFIG")" = "$expected" ]
  run_toastbox install -y --reset-sockopt
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = '{}' ]
  [ "$(jq '[.. | objects | has("sockopt")] | any' "$TB_XRAY_CONFIG")" = "false" ]
}

@test "sockopt: reset runs before explicit flags regardless of CLI order" {
  saved_node
  run_toastbox install -y --tcp-keepalive-idle 240 --reset-sockopt
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = '{"tcpKeepAliveIdle":240}' ]
  run_toastbox install -y --reset-sockopt --tcp-user-timeout 60000
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = '{"tcpUserTimeout":60000}' ]
}

@test "sockopt: invalid config or failed restart leaves previous state and config" {
  saved_node
  local before_state before_config
  before_state="$(<"$TB_STATE_FILE")"
  before_config="$(<"$TB_XRAY_CONFIG")"
  export FAKE_CORE_REJECT=1
  run_toastbox install -y --tcp-keepalive-idle 240
  [ "$status" -ne 0 ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before_config" ]
  unset FAKE_CORE_REJECT
  export MOCK_RESTART_FAILS=1
  run_toastbox install -y --tcp-keepalive-idle 240
  [ "$status" -ne 0 ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before_config" ]
}

@test "sockopt: switching to sing-box requires an explicit reset" {
  saved_node
  run_toastbox install -y --core sing-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"--reset-sockopt"* ]]
  [ ! -s "$MOCK_LOG" ]
  assert_profile
  run_toastbox install -y --core sing-box --reset-sockopt
  [ "$status" -eq 0 ]
  [ "$(jq -r '.core' "$TB_STATE_FILE")" = "sing-box" ]
  [ "$(jq -c '.sockopt' "$TB_STATE_FILE")" = '{}' ]
  [ "$(jq '[.. | objects | has("sockopt")] | any' "$TB_SINGBOX_CONFIG")" = "false" ]
}

@test "sockopt: incompatible saved core is rejected before update installs anything" {
  CFG_SOCKOPT="$(profile)"
  CFG_CORE=sing-box
  state_save
  run_toastbox update
  [ "$status" -ne 0 ]
  [[ "$output" == *"only by Xray"* ]]
  [ ! -s "$MOCK_LOG" ]
}

@test "sockopt: saved settings are visible in text and JSON output" {
  saved_node
  run_toastbox show
  [ "$status" -eq 0 ]
  [[ "$output" == *"TCP sockopt"*"tcpKeepAliveIdle"* ]]
  run_toastbox show --format json
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sockopt' <<<"$output")" = "$(profile)" ]
  local language
  for language in en zh; do
    run_toastbox help --lang "$language"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--tcp-keepalive-idle"*"--reset-sockopt"* ]]
  done
}
