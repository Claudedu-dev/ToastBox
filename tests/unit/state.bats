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

@test "hy2 state round-trips multiline PEM certificates and settings" {
  sample_node
  sample_hy2
  state_save
  local before
  before="$(state_json)"

  cfg_reset
  state_load
  [ "$CFG_HY2" = "1" ]
  [ "$CFG_HY2_PORT" = "443" ]
  [ "$CFG_HY2_PASSWORD" = "hy2-secret-password" ]
  [ "$CFG_HY2_TLS" = "self-signed" ]
  [ "$CFG_HY2_SNI" = "hy2.example.com" ]
  [ "$CFG_HY2_OBFS" = "salamander" ]
  [ "$CFG_HY2_OBFS_PASSWORD" = "obfs-secret-password" ]
  [ "$CFG_HY2_MASQUERADE" = "https://www.example.com" ]
  [[ "$CFG_HY2_CERT" == *"BEGIN CERTIFICATE"* ]]
  [[ "$CFG_HY2_KEY" == *"BEGIN PRIVATE KEY"* ]]
  [ "$(state_json)" = "$before" ]
}

@test "legacy state files without hy2 default hy2 to disabled" {
  sample_node
  mkdir -p "$TB_STATE_DIR"
  state_json | jq 'del(.hy2)' >"$TB_STATE_FILE"
  cfg_reset
  state_load
  [ "$TB_HAS_STATE" = "1" ]
  [ "$CFG_HY2" = "0" ]
  [ -z "$CFG_HY2_PORT" ]
  [ -z "$CFG_HY2_CERT" ]
  [ "$CFG_HY2_CERTBOT_HOOK" = "0" ]
  [ -z "$CFG_HY2_CERT_FILE" ]
  [ -z "$CFG_HY2_HOP_PORTS" ]
  [ "$CFG_HY2_HOP_INTERVAL_MIN" = "30" ]
  [ "$CFG_HY2_HOP_INTERVAL_MAX" = "30" ]
}

@test "hy2 cert source, certbot_hook and hop fields round-trip and legacy without hop loads defaults" {
  sample_node
  sample_hy2
  CFG_HY2_TLS="files"
  CFG_HY2_CERT_FILE="/etc/letsencrypt/live/toastweb-docs.example.org/fullchain.pem"
  CFG_HY2_KEY_FILE="/etc/letsencrypt/live/toastweb-docs.example.org/privkey.pem"
  CFG_HY2_CERTBOT_HOOK=1
  CFG_HY2_HOP_PORTS="20000-20100,30000"
  CFG_HY2_HOP_INTERVAL_MIN=15
  CFG_HY2_HOP_INTERVAL_MAX=45
  state_save
  local before
  before="$(state_json)"

  cfg_reset
  state_load
  [ "$CFG_HY2_CERT_FILE" = "/etc/letsencrypt/live/toastweb-docs.example.org/fullchain.pem" ]
  [ "$CFG_HY2_KEY_FILE" = "/etc/letsencrypt/live/toastweb-docs.example.org/privkey.pem" ]
  [ "$CFG_HY2_CERTBOT_HOOK" = "1" ]
  [ "$CFG_HY2_HOP_PORTS" = "20000-20100,30000" ]
  [ "$CFG_HY2_HOP_INTERVAL_MIN" = "15" ]
  [ "$CFG_HY2_HOP_INTERVAL_MAX" = "45" ]
  [ "$(state_json)" = "$before" ]

  # Removing .hy2.hop simulates pre-hop schema-1 state files.
  state_json | jq 'del(.hy2.hop, .hy2.cert_file, .hy2.key_file, .hy2.certbot_hook)' >"$TB_STATE_FILE"
  cfg_reset
  state_load
  [ "$CFG_HY2_CERTBOT_HOOK" = "0" ]
  [ -z "$CFG_HY2_HOP_PORTS" ]
  [ "$CFG_HY2_HOP_INTERVAL_MIN" = "30" ]
  [ "$CFG_HY2_HOP_INTERVAL_MAX" = "30" ]
}

@test "malformed saved hy2.hop or certbot_hook fails state_load cleanly" {
  sample_node
  sample_hy2
  state_save
  cp "$TB_STATE_FILE" "$BATS_TEST_TMPDIR/good.json"

  local bad
  for bad in \
    '.hy2.hop = "bad"' \
    '.hy2.hop.ports = "20000"' \
    '.hy2.hop.ports = "20100-20000"' \
    '.hy2.hop.interval_min = 4' \
    '.hy2.hop.interval_min = 50 | .hy2.hop.interval_max = 20' \
    '.hy2.certbot_hook = "yes"'; do
    jq "$bad" "$BATS_TEST_TMPDIR/good.json" >"$TB_STATE_FILE"
    run state_load
    [ "$status" -ne 0 ]
    [[ "$output" == *"damaged"* ]]
  done
}
