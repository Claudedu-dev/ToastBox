#!/usr/bin/env bats

load helper

setup() { load_toastbox; }

@test "state_load reports a missing state" {
  refute state_load
  [ "$TB_HAS_STATE" = "0" ]
}

@test "state round-trips every field" {
  sample_node
  CFG_CORE="sing-box"
  CFG_NODE_NAME="it's \"quoted\" \$HOME"
  CFG_LISTEN="203.0.113.10"
  CFG_BLOCK_BT=1
  CFG_ALLOW_PRIVATE=1
  CFG_SS_NETWORK="tcp"
  CFG_FW_RULES=("443/tcp" "28443/tcp")
  state_save
  local before
  before="$(state_json)"

  cfg_reset
  state_load
  [ "$TB_HAS_STATE" = "1" ]
  [ "$CFG_CORE" = "sing-box" ]
  [ "$CFG_NODE_NAME" = "it's \"quoted\" \$HOME" ]
  [ "$CFG_VLESS" = "1" ]
  [ "$CFG_VLESS_PORT" = "443" ]
  [ "$CFG_BLOCK_BT" = "1" ]
  [ "${#CFG_FW_RULES[@]}" -eq 2 ]
  [ "${CFG_FW_RULES[1]}" = "28443/tcp" ]
  [ "$(state_json)" = "$before" ]
}

@test "a disabled protocol survives the round trip without a port" {
  sample_node
  CFG_SS=0
  CFG_SS_PORT=""
  CFG_SS_METHOD=""
  CFG_SS_PASSWORD=""
  state_save
  cfg_reset
  state_load
  [ "$CFG_SS" = "0" ]
  [ -z "$CFG_SS_PORT" ]
  [ "${#CFG_FW_RULES[@]}" -eq 0 ]
}

@test "the state file is private" {
  sample_node
  state_save
  [ "$(stat -c %a "$TB_STATE_FILE")" = "600" ]
  [ "$(stat -c %a "$TB_STATE_DIR")" = "700" ]
}

@test "state values are never evaluated as shell code" {
  sample_node
  CFG_NODE_NAME='$(touch '"$BATS_TEST_TMPDIR"'/pwned)`id`'
  state_save
  cfg_reset
  state_load
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  [ "$CFG_NODE_NAME" = '$(touch '"$BATS_TEST_TMPDIR"'/pwned)`id`' ]
}

@test "a damaged state file is an error, not an empty node" {
  mkdir -p "$TB_STATE_DIR"
  echo '{"core": "xray"' >"$TB_STATE_FILE"
  run state_load
  [ "$status" -ne 0 ]
  [[ "$output" == *"damaged"* ]]
  echo '{"core": "xray"}' >"$TB_STATE_FILE"
  run state_load
  [ "$status" -ne 0 ]
}

@test "backup_file keeps the five newest copies" {
  local i src="$BATS_TEST_TMPDIR/config.json"
  for i in 1 2 3 4 5 6 7; do
    echo "{\"n\": $i}" >"$src"
    backup_file "$src" "xray-config" >/dev/null
    touch -d "2026-01-0$i 00:00:00" "$TB_BACKUP_DIR"/xray-config-*-$$.json 2>/dev/null || true
    # Distinct names: the timestamp has one-second resolution.
    mv "$TB_BACKUP_DIR"/xray-config-*-$$.json "$TB_BACKUP_DIR/xray-config-2026010$i-000000-1.json"
  done
  [ "$(find "$TB_BACKUP_DIR" -name 'xray-config-*.json' | wc -l)" -eq 5 ]
  [ -e "$TB_BACKUP_DIR/xray-config-20260107-000000-1.json" ]
  [ ! -e "$TB_BACKUP_DIR/xray-config-20260101-000000-1.json" ]
}

@test "backup_file is a no-op for a missing file" {
  run backup_file "$BATS_TEST_TMPDIR/nope.json" "xray-config"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
