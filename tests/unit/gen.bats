#!/usr/bin/env bats

load helper

setup() {
  load_toastbox
  install_fake_cores
}

PRIV="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
PUB="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

@test "parse_keypair: current Xray output" {
  parse_keypair "PrivateKey: $PRIV
Password (PublicKey): $PUB
Hash32: 4v8lEJj1Qn2e0xXyXyXyXyXyXyXyXyXyXyXyXyXyXyX"
  [ "$GEN_PRIVATE_KEY" = "$PRIV" ]
  [ "$GEN_PUBLIC_KEY" = "$PUB" ]
}

@test "parse_keypair: Xray 25.x output (PrivateKey / Password)" {
  parse_keypair "PrivateKey: $PRIV
Password: $PUB
Hash32: 4v8lEJj1Qn2e0xXyXyXyXyXyXyXyXyXyXyXyXyXyXyX"
  [ "$GEN_PRIVATE_KEY" = "$PRIV" ]
  [ "$GEN_PUBLIC_KEY" = "$PUB" ]
}

@test "parse_keypair: legacy Xray output (Private key / Public key)" {
  parse_keypair "Private key: $PRIV
Public key: $PUB"
  [ "$GEN_PRIVATE_KEY" = "$PRIV" ]
  [ "$GEN_PUBLIC_KEY" = "$PUB" ]
}

@test "parse_keypair: sing-box output" {
  parse_keypair "PrivateKey: $PRIV
PublicKey: $PUB"
  [ "$GEN_PRIVATE_KEY" = "$PRIV" ]
  [ "$GEN_PUBLIC_KEY" = "$PUB" ]
}

@test "parse_keypair rejects garbage and truncated keys" {
  refute parse_keypair ""
  refute parse_keypair "command not found"
  refute parse_keypair "PrivateKey: short
PublicKey: $PUB"
}

@test "gen_reality_keypair works with both cores" {
  CFG_CORE="xray"
  gen_reality_keypair
  valid_reality_key "$GEN_PRIVATE_KEY"
  valid_reality_key "$GEN_PUBLIC_KEY"
  local first="$GEN_PRIVATE_KEY"
  CFG_CORE="sing-box"
  gen_reality_keypair
  valid_reality_key "$GEN_PRIVATE_KEY"
  [ "$GEN_PRIVATE_KEY" != "$first" ]
}

@test "gen_reality_keypair fails when the core is missing" {
  rm -f "$TOASTBOX_XRAY_BIN"
  CFG_CORE="xray"
  refute gen_reality_keypair
}

@test "gen_uuid falls back to the kernel when the core is missing" {
  rm -f "$TOASTBOX_XRAY_BIN"
  CFG_CORE="xray"
  valid_uuid "$(gen_uuid)"
}

@test "generated Shadowsocks keys match the method" {
  local method
  for method in "${TB_SS_METHODS[@]}"; do
    valid_ss_password "$method" "$(gen_ss_password "$method")"
  done
  valid_short_id "$(gen_short_id)"
  [ "$(gen_short_id | tr -d '\n' | wc -c)" -eq 16 ]
}

@test "ensure_credentials fills only what is missing" {
  sample_node
  ensure_credentials
  [ "$CFG_VLESS_UUID" = "5783a3e7-e373-51cd-8642-c83782b807c5" ]
  [ "$CFG_REALITY_PRIVATE_KEY" = "$PRIV" ]
  [ "$CFG_SS_PASSWORD" = "8JCsPssfgS8tiRwiMlhARg==" ]

  clear_credentials
  ensure_credentials
  valid_uuid "$CFG_VLESS_UUID"
  valid_reality_key "$CFG_REALITY_PRIVATE_KEY"
  valid_reality_key "$CFG_REALITY_PUBLIC_KEY"
  [ "$CFG_REALITY_PRIVATE_KEY" != "$PRIV" ]
  valid_short_id "$CFG_REALITY_SHORT_ID"
  valid_ss_password "$CFG_SS_METHOD" "$CFG_SS_PASSWORD"
}

@test "ensure_credentials regenerates the key when the method changes" {
  sample_node
  CFG_SS_METHOD="2022-blake3-aes-256-gcm"
  ensure_credentials
  [ "$CFG_SS_PASSWORD" != "8JCsPssfgS8tiRwiMlhARg==" ]
  valid_ss_password 2022-blake3-aes-256-gcm "$CFG_SS_PASSWORD"
}

@test "ensure_credentials leaves disabled protocols alone" {
  sample_node
  clear_credentials
  CFG_VLESS=0
  ensure_credentials
  [ -z "$CFG_VLESS_UUID" ]
  [ -z "$CFG_REALITY_PRIVATE_KEY" ]
  valid_ss_password "$CFG_SS_METHOD" "$CFG_SS_PASSWORD"
}
