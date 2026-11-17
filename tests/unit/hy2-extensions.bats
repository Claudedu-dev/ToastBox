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
    MOCK_SYSTEMCTL_ENABLE_FAILS
}

state() { jq -r "$1" "$TB_STATE_FILE"; }
calls() { cat "$MOCK_LOG"; }

# Creates a Certbot-like archive + live symlink tree under $TOASTBOX_CERTBOT_LIVE_DIR.
make_certbot_lineage() {
  local lineage="$1" sni="$2" ver="${3:-1}" ca_pem="${4:-}"
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/$lineage"
  local archive="$BATS_TEST_TMPDIR/letsencrypt/archive/$lineage"
  mkdir -p "$live" "$archive"
  tls_generate_self_signed "203.0.113.10" "$sni"
  if [[ -n "$ca_pem" ]]; then
    printf '%s\n%s\n' "$TLS_CERT_PEM" "$ca_pem" >"$archive/fullchain${ver}.pem"
  else
    printf '%s\n' "$TLS_CERT_PEM" >"$archive/fullchain${ver}.pem"
  fi
  printf '%s\n' "$TLS_KEY_PEM" >"$archive/privkey${ver}.pem"
  ln -sfn "../../archive/$lineage/fullchain${ver}.pem" "$live/fullchain.pem"
  ln -sfn "../../archive/$lineage/privkey${ver}.pem" "$live/privkey.pem"
}

make_fake_toastbox_entry() {
  cat >"$TB_SELF_PATH" <<EOF
#!/usr/bin/env bash
export TOASTBOX_SOURCE_ONLY=1
source "$REPO_ROOT/src/main.sh"
source "$REPO_ROOT/tests/unit/mocks.bash"
tb_main "\$@"
EOF
  chmod +x "$TB_SELF_PATH"
}

@test "files import records stable Certbot live symlink path rather than archive version path" {
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local cert="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org/fullchain.pem"
  local key="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org/privkey.pem"

  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$cert" --hy2-key "$key" --hy2-sni docs.example.org
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_file)" = "$cert" ]
  [ "$(state .hy2.key_file)" = "$key" ]
  [[ "$(state .hy2.cert_file)" != *"/archive/"* ]]
  [ "$(state .hy2.certbot_hook)" = "false" ]
}

@test "refresh-cert skips unchanged certs, refreshes intermediate chain and key changes, and keeps stopped cores stopped" {
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org"
  local cert="$live/fullchain.pem" key="$live/privkey.pem"

  run_toastbox install -y --core xray --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$cert" --hy2-key "$key" --hy2-sni docs.example.org \
    --hy2-hop-ports 20000-20010 --hy2-hop-interval 15
  [ "$status" -eq 0 ]
  local pw_before hop_before sha_before cert_before cfg_before
  pw_before="$(state .hy2.password)"
  hop_before="$(state .hy2.hop.ports)"
  sha_before="$(state .hy2.cert_sha256)"
  cert_before="$(state .hy2.cert)"
  cfg_before="$(<"$TB_XRAY_CONFIG")"

  # Unchanged files: no restart and config untouched.
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  [[ "$(calls)" != *"restart"* ]]
  [ "$(<"$TB_XRAY_CONFIG")" = "$cfg_before" ]

  # Intermediate chain changes while leaf SHA-256 stays identical -> must refresh.
  tls_generate_self_signed "203.0.113.10" "extra-ca.example.org"
  local archive="$BATS_TEST_TMPDIR/letsencrypt/archive/toastweb-docs.example.org"
  cat "$archive/fullchain1.pem" >"$archive/fullchain2.pem"
  printf '%s\n' "$TLS_CERT_PEM" >>"$archive/fullchain2.pem"
  cp "$archive/privkey1.pem" "$archive/privkey2.pem"
  ln -sfn "../../archive/toastweb-docs.example.org/fullchain2.pem" "$cert"
  ln -sfn "../../archive/toastweb-docs.example.org/privkey2.pem" "$key"

  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_sha256)" = "$sha_before" ]
  [ "$(state .hy2.cert)" != "$cert_before" ]
  [ "$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificate | length' "$TB_XRAY_CONFIG")" -gt "$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificate | length' <<<"$cfg_before")" ]
  [[ "$(calls)" == *"restart xray"* ]]

  # Stopped service must remain stopped on refresh-cert while updating config & state.
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 3
  export MOCK_SERVICE_INACTIVE=1
  : >"$MOCK_LOG"
  run_toastbox refresh-cert
  [ "$status" -eq 0 ]
  [[ "$(calls)" != *"restart"* ]]
  [ "$(state .hy2.cert_sha256)" != "$sha_before" ]
  [ "$(state .hy2.password)" = "$pw_before" ]
  [ "$(state .hy2.hop.ports)" = "$hop_before" ]
  [[ "$(<"$TB_XRAY_CONFIG")" == *"$(state .hy2.cert | sed -n '2p')"* ]]
}

@test "refresh-cert rejects legacy files state without source paths and rolls back on state_save failure" {
  tls_generate_self_signed "203.0.113.10" "docs.example.org"
  printf '%s\n' "$TLS_CERT_PEM" >"$BATS_TEST_TMPDIR/cert.pem"
  printf '%s\n' "$TLS_KEY_PEM" >"$BATS_TEST_TMPDIR/key.pem"

  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$BATS_TEST_TMPDIR/cert.pem" --hy2-key "$BATS_TEST_TMPDIR/key.pem"
  [ "$status" -eq 0 ]
  local sha_before cfg_before
  sha_before="$(state .hy2.cert_sha256)"
  cfg_before="$(<"$TB_SINGBOX_CONFIG")"

  # Simulate legacy state missing cert_file/key_file: show/update work, refresh-cert explains clearly.
  jq '.hy2.cert_file = "" | .hy2.key_file = ""' "$TB_STATE_FILE" >"$BATS_TEST_TMPDIR/state.tmp"
  mv "$BATS_TEST_TMPDIR/state.tmp" "$TB_STATE_FILE"
  [ "$(state .hy2.enabled)" = "true" ]
  [ "$(state .hy2.tls)" = "files" ]
  run_toastbox show --format json
  [ "$status" -eq 0 ]
  run_toastbox refresh-cert
  [ "$status" -ne 0 ]
  [[ "$output" == *"external certificate source paths"* && "$output" == *"--hy2-cert"* ]]

  # Restore source paths, rotate cert files, and simulate state_save failure -> rolls back config & service.
  run_toastbox install -y --hy2-cert "$BATS_TEST_TMPDIR/cert.pem" --hy2-key "$BATS_TEST_TMPDIR/key.pem"
  [ "$status" -eq 0 ]
  sha_before="$(state .hy2.cert_sha256)"
  cfg_before="$(<"$TB_SINGBOX_CONFIG")"
  tls_generate_self_signed "203.0.113.10" "docs.example.org"
  printf '%s\n' "$TLS_CERT_PEM" >"$BATS_TEST_TMPDIR/cert.pem"
  printf '%s\n' "$TLS_KEY_PEM" >"$BATS_TEST_TMPDIR/key.pem"

  : >"$MOCK_LOG"
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    state_save() { return 1; }
    tb_main refresh-cert
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not save node state to $TB_STATE_FILE"* ]]
  [ "$(state .hy2.cert_sha256)" = "$sha_before" ]
  [ "$(<"$TB_SINGBOX_CONFIG")" = "$cfg_before" ]
  [ "$(grep -c '^restart sing-box$' "$MOCK_LOG")" -eq 2 ]
}

@test "certbot deploy hook validates lineage, ignores unrelated renewals, preserves sibling hooks, and cleans up on disable/uninstall" {
  make_fake_toastbox_entry
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org"
  local sibling="$BATS_TEST_TMPDIR/letsencrypt/renewal-hooks/deploy/toastweb.sh"
  mkdir -p "$(dirname "$sibling")"
  printf '#!/usr/bin/env bash\necho toastweb\n' >"$sibling"
  chmod +x "$sibling"

  # Non-certbot path cannot enable certbot hook.
  tls_generate_self_signed "203.0.113.10" "docs.example.org"
  printf '%s\n' "$TLS_CERT_PEM" >"$BATS_TEST_TMPDIR/custom.pem"
  printf '%s\n' "$TLS_KEY_PEM" >"$BATS_TEST_TMPDIR/custom.key"
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$BATS_TEST_TMPDIR/custom.pem" --hy2-key "$BATS_TEST_TMPDIR/custom.key" --hy2-cert-hook certbot
  [ "$status" -ne 0 ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]

  # Install with valid Certbot pair & certbot hook.
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$live/fullchain.pem" --hy2-key "$live/privkey.pem" --hy2-cert-hook certbot
  [ "$status" -eq 0 ]
  [ -x "$TB_CERTBOT_HOOK_PATH" ]
  [ "$(state .hy2.certbot_hook)" = "true" ]
  local sha1
  sha1="$(state .hy2.cert_sha256)"

  # Rotate live files to version 2, invoke hook for an UNRELATED lineage -> must skip and exit 0.
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 2
  run env RENEWED_LINEAGE="$TOASTBOX_CERTBOT_LIVE_DIR/other.example.org" "$TB_CERTBOT_HOOK_PATH"
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_sha256)" = "$sha1" ]

  # Invoke hook for MATCHING lineage -> refreshes certificate.
  run env RENEWED_LINEAGE="$live" "$TB_CERTBOT_HOOK_PATH"
  [ "$status" -eq 0 ]
  [ "$(state .hy2.cert_sha256)" != "$sha1" ]

  # Missing entrypoint on matching lineage fails non-zero cleanly.
  chmod -x "$TB_SELF_PATH"
  run env RENEWED_LINEAGE="$live" "$TB_CERTBOT_HOOK_PATH"
  [ "$status" -ne 0 ]
  chmod +x "$TB_SELF_PATH"

  # --hy2-cert-hook none removes our hook, keeps sibling toastweb.sh and certs untouched.
  run_toastbox install -y --hy2-cert-hook none
  [ "$status" -eq 0 ]
  [ "$(state .hy2.certbot_hook)" = "false" ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]
  [ -f "$sibling" ]
  [ -e "$live/fullchain.pem" ]

  # Re-enable hook, then test switching to self-signed clears source/hook state and removes hook.
  run_toastbox install -y --hy2-cert-hook certbot
  [ "$status" -eq 0 ]
  [ -e "$TB_CERTBOT_HOOK_PATH" ]
  run_toastbox install -y --hy2-tls self-signed
  [ "$status" -eq 0 ]
  [ "$(state .hy2.certbot_hook)" = "false" ]
  [ "$(state .hy2.cert_file)" = "" ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]
  [ -e "$live/fullchain.pem" ]
}

@test "certbot deploy hook refuses missing entrypoint and foreign hooks without ToastBox marker" {
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org"

  # When neither bundle nor scripts/build.sh nor TB_SELF_PATH exists (pipe mode), preflight refuses hook.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    certbot_can_install_entrypoint() { return 1; }
    tb_main install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
      --hy2-cert "$2/fullchain.pem" --hy2-key "$2/privkey.pem" --hy2-cert-hook certbot
  ' _ "$REPO_ROOT" "$live"
  [ "$status" -ne 0 ]
  [[ "$output" == *"toastbox.sh"* ]]

  # Foreign deploy hook must never be overwritten or deleted.
  make_fake_toastbox_entry
  mkdir -p "$(dirname "$TB_CERTBOT_HOOK_PATH")"
  printf '#!/usr/bin/env bash\necho custom-admin-hook\n' >"$TB_CERTBOT_HOOK_PATH"
  chmod +x "$TB_CERTBOT_HOOK_PATH"
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-cert "$live/fullchain.pem" --hy2-key "$live/privkey.pem" --hy2-cert-hook certbot
  [ "$status" -ne 0 ]
  [[ "$output" == *"unmanaged deploy hook"* ]]
  grep -q 'custom-admin-hook' "$TB_CERTBOT_HOOK_PATH"

  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10
  [ "$status" -eq 0 ]
  grep -q 'custom-admin-hook' "$TB_CERTBOT_HOOK_PATH"
}

@test "hop lifecycle: persistence, --no-firewall NAT, SS/UDP conflicts, core switch, disable and leftover uninstall" {
  export MOCK_FW_BACKEND="ufw"

  # Reject hop options when Hy2 is disabled.
  run_toastbox install -y --core xray --protocols vless --server-addr 203.0.113.10 \
    --reality-sni www.example.com --hy2-hop-ports 20000-20100
  [ "$status" -ne 0 ]
  [[ "$output" == *"hy2"* ]]

  # Reject loopback listen with hop.
  run_toastbox install -y --core xray --protocols hy2 --server-addr 203.0.113.10 \
    --listen 127.0.0.1 --hy2-hop-ports 20000-20100
  [ "$status" -ne 0 ]

  # Reject SS UDP port overlap, allow SS TCP-only overlap and VLESS TCP overlap.
  run_toastbox install -y --core xray --protocols ss,hy2 --server-addr 203.0.113.10 \
    --ss-port 20050 --ss-network both --hy2-hop-ports 20000-20100
  [ "$status" -ne 0 ]
  run_toastbox install -y --core xray --protocols vless,ss,hy2 --server-addr 203.0.113.10 \
    --reality-sni www.example.com --vless-port 20010 --ss-port 20050 --ss-network tcp \
    --hy2-port 443 --hy2-hop-ports 20000-20100
  [ "$status" -eq 0 ]

  # Reject live foreign UDP listener inside hop range.
  export MOCK_BUSY_PORT="udp:20080:dnsmasq"
  run_toastbox install -y --hy2-hop-ports 20000-20100
  [ "$status" -ne 0 ]
  [[ "$output" == *"20080/udp"*"dnsmasq"* ]]
  unset MOCK_BUSY_PORT

  # --no-firewall skips ufw but still runs hop NAT & creates systemd resources.
  : >"$MOCK_LOG"
  run_toastbox install -y --no-firewall --hy2-hop-interval 15-45
  [ "$status" -eq 0 ]
  [[ "$(calls)" != *"fw_open"* ]]
  [[ "$(calls)" == *"hy2_hop_apply"* ]]
  [ "$(state .hy2.hop.ports)" = "20000-20100" ]
  [ "$(state .hy2.hop.interval_min)" = "15" ]
  [ "$(state .hy2.hop.interval_max)" = "45" ]
  [ -x "$TB_HY2_HOP_HELPER" ]
  [ -f "$TB_HY2_HOP_STATE" ]
  [ -f "$(hy2_hop_unit_path)" ]
  [ -f "$(hy2_hop_dropin_path xray)" ]
  grep -q 'PartOf=xray.service' "$(hy2_hop_unit_path)"
  grep -q 'Requires=toastbox-hy2-hop.service' "$(hy2_hop_dropin_path xray)"

  # Re-run, update, and rotate preserve hop settings.
  run_toastbox install -y --name hop-node
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "20000-20100" ]
  [ "$(state '.hy2.hop.interval_min')" = "15" ]
  run_toastbox update
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "20000-20100" ]
  run_toastbox rotate -y
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "20000-20100" ]

  # Text show displays hop + client version note + SG UDP ports; json stays machine-clean.
  run_toastbox show
  [ "$status" -eq 0 ]
  [[ "$output" == *"20000-20100/udp"* ]]
  [[ "$output" == *"15-45s"* ]]
  [[ "$output" == *"sing-box 1.14.0+"* ]]
  [[ "$output" == *"443,20000-20100"* ]]
  run_toastbox show --format json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hy2.hop.ports' <<<"$output")" = "20000-20100" ]

  # Core switch to sing-box moves drop-in & PartOf, and uninstalling unused xray preserves hop!
  make_fake_toastbox_entry
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org"
  run_toastbox install -y --core sing-box --hy2-cert "$live/fullchain.pem" --hy2-key "$live/privkey.pem" --hy2-cert-hook certbot
  [ "$status" -eq 0 ]
  [ ! -e "$(hy2_hop_dropin_path xray)" ]
  [ -f "$(hy2_hop_dropin_path sing-box)" ]
  grep -q 'PartOf=sing-box.service' "$(hy2_hop_unit_path)"

  run_toastbox uninstall -y --core xray
  [ "$status" -eq 0 ]
  [ -f "$TB_HY2_HOP_STATE" ]
  [ -f "$(hy2_hop_unit_path)" ]
  [ -f "$(hy2_hop_dropin_path sing-box)" ]
  [ -f "$TB_CERTBOT_HOOK_PATH" ]

  # Disabling Hy2 cleans hop & hook resources AND clears automation state so re-enabling Hy2 later won't auto-re-enable.
  run_toastbox install -y --protocols vless
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "" ]
  [ "$(state .hy2.certbot_hook)" = "false" ]
  [ ! -e "$TB_HY2_HOP_STATE" ]
  [ ! -e "$TB_HY2_HOP_HELPER" ]
  [ ! -e "$(hy2_hop_unit_path)" ]
  [ ! -e "$(hy2_hop_dropin_path sing-box)" ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]

  run_toastbox install -y --protocols all
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "" ]
  [ "$(state .hy2.certbot_hook)" = "false" ]
  [ ! -e "$TB_HY2_HOP_STATE" ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]
}

@test "hop rollback restores prior NAT rules, units, drop-in and core config on failure" {
  run_toastbox install -y --core xray --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-port 443 --hy2-hop-ports 20000-20010
  [ "$status" -eq 0 ]
  local before_hop before_cfg before_state
  before_hop="$(<"$TB_HY2_HOP_STATE")"
  before_cfg="$(<"$TB_XRAY_CONFIG")"
  before_state="$(<"$TB_STATE_FILE")"

  # Partial/failed NAT application leaves prior config, unit and state intact.
  export MOCK_HY2_HOP_FAILS=1
  run_toastbox install -y --hy2-hop-ports 30000-30010
  [ "$status" -ne 0 ]
  [ "$(<"$TB_HY2_HOP_STATE")" = "$before_hop" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before_cfg" ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  unset MOCK_HY2_HOP_FAILS

  # Core restart failure after hop update also rolls back hop files, drop-ins and rules.
  export MOCK_RESTART_FAILS=1
  run_toastbox install -y --core sing-box --hy2-hop-ports 30000-30010
  [ "$status" -ne 0 ]
  [ "$(<"$TB_HY2_HOP_STATE")" = "$before_hop" ]
  [ "$(<"$TB_XRAY_CONFIG")" = "$before_cfg" ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  [ -f "$(hy2_hop_dropin_path xray)" ]
  [ ! -e "$(hy2_hop_dropin_path sing-box)" ]
  unset MOCK_RESTART_FAILS

  # Full node uninstall cleans up hop files.
  run_toastbox uninstall -y
  [ "$status" -eq 0 ]
  [ ! -e "$TB_HY2_HOP_STATE" ]
  [ ! -e "$TB_HY2_HOP_HELPER" ]
  [ ! -e "$(hy2_hop_unit_path)" ]
}

@test "real NAT helper executes standalone, handles nft/iptables/ip6tables, explicit DNAT vs wildcard REDIRECT, and partial rollback" {
  local mockbin="$BATS_TEST_TMPDIR/natbin"
  local natlog="$BATS_TEST_TMPDIR/nat.log"
  mkdir -p "$mockbin"
  export NATLOG="$natlog"

  # Install mock nft + iptables + ip6tables on PATH.
  cat >"$mockbin/nft" <<'EOF'
#!/usr/bin/env bash
echo "nft $*" >>"$NATLOG"
if [[ "${1:-}" == "list" && "${2:-}" == "table" ]]; then
  exit "${MOCK_NFT_EXISTS:-1}"
fi
if [[ "${1:-}" == "-f" ]]; then
  cat >>"$NATLOG"
fi
exit "${MOCK_NFT_FAIL:-0}"
EOF
  cat >"$mockbin/iptables" <<'EOF'
#!/usr/bin/env bash
echo "iptables $*" >>"$NATLOG"
if [[ "$*" == *"-L PREROUTING -n --line-numbers"* ]]; then
  printf 'Chain PREROUTING (policy ACCEPT)\n'
  printf 'num  target     prot opt source   destination\n'
  printf '1    OTHER      udp  --  0.0.0.0/0 0.0.0.0/0\n'
  printf '2    TOASTBOX-HY2 udp -- 0.0.0.0/0 0.0.0.0/0\n'
  printf '5    TOASTBOX-HY2 udp -- 0.0.0.0/0 0.0.0.0/0\n'
  exit 0
fi
if [[ "$*" == *"-L TOASTBOX-HY2 -n"* ]]; then
  exit "${MOCK_IPT_CHAIN_EXISTS:-1}"
fi
exit 0
EOF
  cat >"$mockbin/ip6tables" <<'EOF'
#!/usr/bin/env bash
echo "ip6tables $*" >>"$NATLOG"
if [[ "$*" == *"-L PREROUTING -n --line-numbers"* ]]; then
  exit 0
fi
if [[ "$*" == *"-L TOASTBOX-HY2 -n"* ]]; then
  exit "${MOCK_IPT6_CHAIN_EXISTS:-1}"
fi
if [[ -n "${MOCK_IPT6_FAIL:-}" && "$*" == *"-A "* ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$mockbin/nft" "$mockbin/iptables" "$mockbin/ip6tables"

  # 1. nft backend: wildcard dual-stack with listen port subtracted.
  PATH="$mockbin:$PATH"
  CFG_HY2=1
  CFG_HY2_PORT=443
  CFG_HY2_HOP_PORTS="443,20000-20010"
  CFG_LISTEN=""
  ipv6_enabled() { return 0; }
  HY2_HOP_BACKEND="nftables"
  local json_file="$BATS_TEST_TMPDIR/hop.json"
  hy2_hop_render_json >"$json_file"
  hy2_hop_write_helper "$TB_HY2_HOP_HELPER"

  # Verify generated helper passes bash -n and runs standalone with env -i (no source tree).
  bash -n "$TB_HY2_HOP_HELPER"
  : >"$natlog"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" "$TB_HY2_HOP_HELPER" apply "$json_file"
  [ "$status" -eq 0 ]
  grep -q 'add table ip toastbox_hy2' "$natlog"
  grep -q 'add rule ip toastbox_hy2 prerouting fib daddr type local udp dport 20000-20010 redirect to :443' "$natlog"
  grep -q 'add rule ip6 toastbox_hy2 prerouting fib daddr type local udp dport 20000-20010 redirect to :443' "$natlog"
  ! grep -q 'udp dport 443 redirect' "$natlog"
  ! grep -q 'hook output' "$natlog"
  ! grep -q 'flush ruleset' "$natlog"

  # Explicit IPv6 listen uses dnat to [ip]:port on ip6 only.
  CFG_LISTEN="2001:db8::1"
  hy2_hop_render_json >"$json_file"
  : >"$natlog"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" MOCK_NFT_EXISTS=0 "$TB_HY2_HOP_HELPER" apply "$json_file"
  [ "$status" -eq 0 ]
  grep -q 'delete table ip toastbox_hy2' "$natlog"
  ! grep -q 'add table ip toastbox_hy2' "$natlog"
  grep -q 'ip6 daddr 2001:db8::1 udp dport 20000-20010 dnat to \[2001:db8::1\]:443' "$natlog"

  # 2. iptables fallback + colon port range + reverse line-number deletion + partial failure rollback.
  rm -f "$mockbin/nft"
  CFG_LISTEN=""
  CFG_HY2_HOP_PORTS="20000-20010,30000"
  HY2_HOP_BACKEND="iptables"
  hy2_hop_render_json >"$json_file"

  : >"$natlog"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" MOCK_IPT_CHAIN_EXISTS=0 "$TB_HY2_HOP_HELPER" apply "$json_file"
  [ "$status" -eq 0 ]
  # Highest PREROUTING jump rule (line 5) deleted before line 2; rule 1 (OTHER) never touched.
  local del5 del2
  del5="$(grep -n 'iptables -w -t nat -D PREROUTING 5' "$natlog" | cut -d: -f1)"
  del2="$(grep -n 'iptables -w -t nat -D PREROUTING 2' "$natlog" | cut -d: -f1)"
  [ "$del5" -lt "$del2" ]
  ! grep -q 'PREROUTING 1' "$natlog"
  grep -q 'iptables -w -t nat -A TOASTBOX-HY2 -p udp -j REDIRECT --to-ports 443' "$natlog"
  grep -q 'iptables -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p udp --dport 20000:20010 -j TOASTBOX-HY2' "$natlog"
  grep -q 'iptables -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p udp --dport 30000 -j TOASTBOX-HY2' "$natlog"
  ! grep -q 'OUTPUT' "$natlog"

  # Explicit IPv4 uses DNAT and omits ip6tables.
  CFG_LISTEN="203.0.113.10"
  HY2_HOP_BACKEND="iptables"
  hy2_hop_render_json >"$json_file"
  : >"$natlog"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" "$TB_HY2_HOP_HELPER" apply "$json_file"
  [ "$status" -eq 0 ]
  grep -q 'iptables -w -t nat -A TOASTBOX-HY2 -p udp -j DNAT --to-destination 203.0.113.10:443' "$natlog"
  grep -q 'iptables -w -t nat -A PREROUTING -d 203.0.113.10 -p udp --dport 20000:20010 -j TOASTBOX-HY2' "$natlog"
  ! grep -q 'ip6tables.*-N TOASTBOX-HY2' "$natlog"

  # Partial failure: ip6tables fails after iptables succeeded -> cleans up iptables chain too!
  CFG_LISTEN=""
  hy2_hop_render_json >"$json_file"
  : >"$natlog"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" MOCK_IPT6_FAIL=1 MOCK_IPT_CHAIN_EXISTS=0 "$TB_HY2_HOP_HELPER" apply "$json_file"
  [ "$status" -ne 0 ]
  grep -q 'iptables -w -t nat -X TOASTBOX-HY2' "$natlog"
}

@test "hop installation succeeds and renders IPv4-only NAT rules when IPv6 is disabled" {
  export MOCK_NO_IPV6=1
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-port 443 --hy2-hop-ports 20000-20010 --hy2-hop-interval 20
  [ "$status" -eq 0 ]
  [ "$(state .hy2.hop.ports)" = "20000-20010" ]
  [ -f "$TB_HY2_HOP_STATE" ]
  [ "$(jq -r '.ipv4' "$TB_HY2_HOP_STATE")" = "true" ]
  [ "$(jq -r '.ipv6' "$TB_HY2_HOP_STATE")" = "false" ]

  local mockbin="$BATS_TEST_TMPDIR/natv4" natlog="$BATS_TEST_TMPDIR/natv4.log"
  mkdir -p "$mockbin"
  cat >"$mockbin/nft" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "list" && "${2:-}" == "table" ]]; then exit 1; fi
if [[ "${1:-}" == "-f" ]]; then cat >>"$NATLOG"; fi
exit 0
EOF
  chmod +x "$mockbin/nft"
  run env -i PATH="$mockbin:/usr/bin:/bin" NATLOG="$natlog" "$TB_HY2_HOP_HELPER" apply "$TB_HY2_HOP_STATE"
  [ "$status" -eq 0 ]
  grep -q 'add table ip toastbox_hy2' "$natlog"
  ! grep -q 'ip6' "$natlog"
}

@test "source-mode --hy2-cert-hook certbot replaces legacy toastbox entrypoint so hook can run refresh-cert" {
  make_certbot_lineage "toastweb-docs.example.org" "docs.example.org" 1
  local live="$TOASTBOX_CERTBOT_LIVE_DIR/toastweb-docs.example.org"

  install -d -m 755 "$(dirname "$TB_SELF_PATH")"
  cat >"$TB_SELF_PATH" <<'EOF'
#!/usr/bin/env bash
echo "unknown command: ${1:-}" >&2
exit 2
EOF
  chmod 755 "$TB_SELF_PATH"

  # Source 56-cert-hook.sh after mocks.bash so real certbot_ensure_entrypoint / certbot_build_entrypoint run.
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    source "$1/src/lib/56-cert-hook.sh"
    tb_main install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
      --hy2-cert "$2/fullchain.pem" --hy2-key "$2/privkey.pem" --hy2-cert-hook certbot
  ' _ "$REPO_ROOT" "$live"
  [ "$status" -eq 0 ]
  [ -x "$TB_SELF_PATH" ]
  grep -q 'TB_BUILT=1' "$TB_SELF_PATH"
  grep -q 'cmd_refresh_cert' "$TB_SELF_PATH"
  ! grep -q 'unknown command:' "$TB_SELF_PATH"
  run env -u TOASTBOX_SOURCE_ONLY "$TB_SELF_PATH" --lang en --help </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"refresh-cert"* ]]

  # Invoking the deploy hook executes the replaced single-file entrypoint with refresh-cert
  # (in unprivileged/non-systemd unit env it reaches require_root or require_systemd, never unknown command).
  run env -u TOASTBOX_SOURCE_ONLY RENEWED_LINEAGE="$live" "$TB_CERTBOT_HOOK_PATH"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [[ "$output" != *"unknown command"* && "$output" != *"Unknown option or argument"* ]]
}

@test "acme: successful issuance followed by validation failure cleans temporary 80" {
  export MOCK_FW_BACKEND=ufw
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10
  [ "$status" -eq 0 ]
  local before_state before_config
  before_state="$(<"$TB_STATE_FILE")"
  before_config="$(<"$TB_SINGBOX_CONFIG")"
  make_certbot_lineage "toastbox-hy2-hy2.example.com" "hy2.example.com"
  : >"$MOCK_LOG"
  export FAKE_CORE_REJECT=1
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    acme_reusable_pair() { return 1; }
    acme_check_dns() { :; }
    acme_install_certbot() { :; }
    acme_run_certonly() { echo certonly >>"$MOCK_LOG"; }
    tb_main install -y --hy2-tls acme --hy2-acme-domain hy2.example.com \
      --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [ "$(<"$TB_STATE_FILE")" = "$before_state" ]
  [ "$(<"$TB_SINGBOX_CONFIG")" = "$before_config" ]
  [ "$(grep -E '^(fw_open|fw_close|certonly)' "$MOCK_LOG")" = "$(printf 'fw_open 80/tcp\ncertonly\nfw_close 80/tcp')" ]
  [ "$(state '.firewall.rules | index("80/tcp")')" = "null" ]
}

@test "acme: owned and administrator 80 rules are not temporarily removed" {
  local dummy_file="$BATS_TEST_TMPDIR/dummy.pem"
  : >"$dummy_file"
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    real_fw="$(declare -f fw_backend fw_open fw_close)"
    source "$1/tests/unit/mocks.bash"
    eval "$real_fw"
    ufw() {
      case "$1" in
        status) echo "Status: active" ;;
        allow) echo "allow $2" >>"$MOCK_LOG"; echo "Skipping adding existing rule" ;;
        delete) echo "delete $3" >>"$MOCK_LOG" ;;
        *) return 1 ;;
      esac
    }
    acme_check_dns() { :; }
    acme_check_port_80() { :; }
    acme_install_certbot() { :; }
    acme_run_certonly() { :; }
    dummy_path="$2"
    acme_live_cert_path() { echo "$dummy_path"; }
    acme_live_key_path() { echo "$dummy_path"; }
    tls_validate_pair_files() { :; }
    tls_cert_matches_name() { :; }
    acme_import_live_pair() { :; }
    OPT_NO_FIREWALL=0 CFG_SERVER_ADDR=203.0.113.10
    CFG_FW_RULES=(80/tcp)
    acme_provision_cert example.com admin@example.com lineage example.com
    CFG_FW_RULES=()
    acme_provision_cert example.com admin@example.com lineage example.com
  ' _ "$REPO_ROOT" "$dummy_file"
  [ "$status" -eq 0 ]
  [ "$(grep -E '^(allow|delete) ' "$MOCK_LOG")" = "allow 80/tcp" ]
}

@test "acme standalone: option validation, port-80/DNS guards, ECDSA issuance, cert reuse, scoped timer renewal, failure rollback and cleanup" {
  local acmebin="$BATS_TEST_TMPDIR/acmebin" cb_log="$BATS_TEST_TMPDIR/certbot.log"
  mkdir -p "$acmebin"
  export ACME_LOG="$cb_log" ACME_DNS_IPS="203.0.113.10"
  unset ACME_CERTBOT_FAIL ACME_CERTBOT_UNSUPPORTED_ECDSA MOCK_CERTBOT_SYSTEM_TIMER

  cat >"$acmebin/getent" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "ahosts" ]] || exit 2
for ip in $ACME_DNS_IPS; do
  printf '%s STREAM %s\n' "$ip" "$2"
done
EOF
  cat >"$acmebin/certbot" <<'EOF'
#!/usr/bin/env bash
echo "certbot $*" >>"$ACME_LOG"
case "${1:-}" in
  --help)
    [[ -z "${ACME_CERTBOT_UNSUPPORTED_ECDSA:-}" ]] && echo "  --key-type {rsa,ecdsa}"
    exit 0
    ;;
  certonly)
    [[ -z "${ACME_CERTBOT_FAIL:-}" ]] || exit 1
    domain="" lineage="" idx=1
    while (($# > 0)); do
      case "$1" in
        -d) domain="$2"; shift 2 ;;
        --cert-name) lineage="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    archive="$TOASTBOX_CERTBOT_ARCHIVE_DIR/$lineage"
    live="$TOASTBOX_CERTBOT_LIVE_DIR/$lineage"
    mkdir -p "$archive" "$live"
    ver="${ACME_CERT_VER:-1}"
    cat >"$archive/req${ver}.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no
[dn]
CN = $domain
[v3_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:$domain
CNF
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$archive/privkey${ver}.pem" 2>/dev/null
    openssl req -new -x509 -sha256 -days 90 -config "$archive/req${ver}.cnf" \
      -key "$archive/privkey${ver}.pem" -out "$archive/fullchain${ver}.pem" 2>/dev/null
    ln -sfn "../../archive/$lineage/fullchain${ver}.pem" "$live/fullchain.pem"
    ln -sfn "../../archive/$lineage/privkey${ver}.pem" "$live/privkey.pem"
    exit 0
    ;;
  renew)
    lineage=""
    while (($# > 0)); do
      case "$1" in
        --cert-name) lineage="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    archive="$TOASTBOX_CERTBOT_ARCHIVE_DIR/$lineage"
    live="$TOASTBOX_CERTBOT_LIVE_DIR/$lineage"
    ver=2
    cat >"$archive/req${ver}.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no
[dn]
CN = ${lineage#toastbox-hy2-}
[v3_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${lineage#toastbox-hy2-}
CNF
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$archive/privkey${ver}.pem" 2>/dev/null
    openssl req -new -x509 -sha256 -days 90 -config "$archive/req${ver}.cnf" \
      -key "$archive/privkey${ver}.pem" -out "$archive/fullchain${ver}.pem" 2>/dev/null
    ln -sfn "../../archive/$lineage/fullchain${ver}.pem" "$live/fullchain.pem"
    ln -sfn "../../archive/$lineage/privkey${ver}.pem" "$live/privkey.pem"
    RENEWED_LINEAGE="$live" "$TOASTBOX_CERTBOT_HOOK_PATH"
    exit $?
    ;;
esac
EOF
  chmod +x "$acmebin/getent" "$acmebin/certbot"
  export TOASTBOX_CERTBOT_ARCHIVE_DIR="$BATS_TEST_TMPDIR/letsencrypt/archive"
  export PATH="$acmebin:$PATH"

  # 1. Non-interactive (-y) cannot skip email, domain, or --hy2-acme-agree-tos.
  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls acme --hy2-acme-email admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--hy2-acme-agree-tos"* ]]

  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls acme --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  [[ "$output" == *"--hy2-acme-email"* ]]

  run_toastbox install -y --protocols hy2 --server-addr 203.0.113.10 --hy2-tls acme --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  [[ "$output" == *"--hy2-acme-domain"* ]]

  # 2. Option conflicts rejected cleanly.
  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls files --hy2-acme-domain hy2.example.com --hy2-cert /tmp/c --hy2-key /tmp/k
  [ "$status" -ne 0 ]
  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls acme --hy2-cert-hook none --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  run_toastbox install -y --protocols vless,hy2 --server-addr hy2.example.com --reality-sni www.example.com --vless-port 80 --hy2-tls acme --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]

  # 3. Port 80 busy and unresolvable/private DNS fail cleanly before running certbot.
  export MOCK_BUSY_PORT="tcp:80:nginx"
  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls acme --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  [[ "$output" == *"nginx"* && "$output" == *"--hy2-cert"* ]]
  [ ! -s "$cb_log" ]
  unset MOCK_BUSY_PORT

  ACME_DNS_IPS="127.0.0.1"
  run_toastbox install -y --protocols hy2 --server-addr hy2.example.com --hy2-tls acme --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  [ ! -s "$cb_log" ]
  ACME_DNS_IPS="203.0.113.10"

  # 4. Successful standalone ECDSA issuance without system timer creates scoped toastbox-hy2-certbot timer.
  make_fake_toastbox_entry
  export MOCK_FW_BACKEND="ufw"
  : >"$cb_log"
  run_toastbox install -y --core sing-box --protocols hy2 --server-addr 203.0.113.10 \
    --hy2-tls acme --hy2-acme-domain hy2.example.com --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -eq 0 ]
  grep -q -- '--standalone.*--cert-name toastbox-hy2-hy2.example.com.*-d hy2.example.com' "$cb_log"
  grep -q -- '--key-type ecdsa' "$cb_log"
  [ "$(state .hy2.tls)" = "files" ]
  [ "$(state .hy2.sni)" = "hy2.example.com" ]
  [ "$(state .hy2.acme.enabled)" = "true" ]
  [ "$(state .hy2.acme.domain)" = "hy2.example.com" ]
  [ "$(state .hy2.acme.lineage)" = "toastbox-hy2-hy2.example.com" ]
  [ "$(state .hy2.certbot_hook)" = "true" ]
  [ "$(state .hy2.cert_file)" = "$TOASTBOX_CERTBOT_LIVE_DIR/toastbox-hy2-hy2.example.com/fullchain.pem" ]
  [ "$(grep -E '^fw_(open|close) 80/tcp$' "$MOCK_LOG")" = "$(printf 'fw_open 80/tcp\nfw_close 80/tcp\nfw_open 80/tcp')" ]
  [ "$(state '.firewall.rules | index("80/tcp")')" != "null" ]
  [ -x "$TB_CERTBOT_HOOK_PATH" ]
  [ -f "$TB_SYSTEMD_DIR/$TB_HY2_ACME_SERVICE" ]
  [ -f "$TB_SYSTEMD_DIR/$TB_HY2_ACME_TIMER" ]
  grep -Fxq 'systemctl enable --now toastbox-hy2-certbot.timer' "$MOCK_LOG"
  grep -q 'renew --non-interactive --cert-name toastbox-hy2-hy2.example.com' "$TB_SYSTEMD_DIR/$TB_HY2_ACME_SERVICE"

  # Client outputs validate via system CA without insecure/pinSHA256.
  run_toastbox show --format links --protocols hy2
  [ "$status" -eq 0 ]
  [[ "$output" != *"insecure="* && "$output" != *"pinSHA256="* ]]
  run_toastbox show --format hysteria2 --protocols hy2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tls.sni' <<<"$output")" = "hy2.example.com" ]
  [ "$(jq -r '.tls.insecure // false' <<<"$output")" = "false" ]

  local sha1 pw1
  sha1="$(state .hy2.cert_sha256)"
  pw1="$(state .hy2.password)"

  # 5. Re-install reuses existing valid cert without re-calling certbot certonly.
  : >"$cb_log"
  run_toastbox install -y --hy2-tls acme --hy2-acme-domain hy2.example.com
  [ "$status" -eq 0 ]
  [ ! -s "$cb_log" ]
  [ "$(state .hy2.cert_sha256)" = "$sha1" ]
  [ "$(state .hy2.password)" = "$pw1" ]

  # A failed timer enable must roll back an existing working node.
  local before_timer_state before_timer_config
  before_timer_state="$(<"$TB_STATE_FILE")"
  before_timer_config="$(<"$TB_SINGBOX_CONFIG")"
  : >"$MOCK_LOG"
  export MOCK_SYSTEMCTL_ENABLE_FAILS=1
  run_toastbox install -y --hy2-port 9443
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not configure the ToastBox Certbot renewal timer."* ]]
  grep -Fxq 'systemctl enable --now toastbox-hy2-certbot.timer' "$MOCK_LOG"
  [ "$(<"$TB_STATE_FILE")" = "$before_timer_state" ]
  [ "$(<"$TB_SINGBOX_CONFIG")" = "$before_timer_config" ]
  unset MOCK_SYSTEMCTL_ENABLE_FAILS

  # 6. Scoped certbot renew invokes hook -> updates config & SHA-256 while preserving password.
  run "$acmebin/certbot" renew --non-interactive --cert-name toastbox-hy2-hy2.example.com
  [ "$status" -eq 0 ]
  local sha2
  sha2="$(state .hy2.cert_sha256)"
  [ "$sha2" != "$sha1" ]
  [ "$(state .hy2.password)" = "$pw1" ]

  # 7. Failed issuance on another domain preserves working node untouched.
  export ACME_CERTBOT_FAIL=1
  run_toastbox install -y --hy2-tls acme --hy2-acme-domain broken.example.com --hy2-acme-email admin@example.com --hy2-acme-agree-tos
  [ "$status" -ne 0 ]
  [ "$(state .hy2.acme.domain)" = "hy2.example.com" ]
  [ "$(state .hy2.cert_sha256)" = "$sha2" ]
  unset ACME_CERTBOT_FAIL

  # 8. Active system certbot.timer removes ToastBox dedicated timer to avoid duplicate scheduling.
  export MOCK_CERTBOT_SYSTEM_TIMER=1
  run_toastbox install -y --name reused-sys-timer
  [ "$status" -eq 0 ]
  [ ! -e "$TB_SYSTEMD_DIR/$TB_HY2_ACME_TIMER" ]
  [ ! -e "$TB_SYSTEMD_DIR/$TB_HY2_ACME_SERVICE" ]
  [ -x "$TB_CERTBOT_HOOK_PATH" ]
  unset MOCK_CERTBOT_SYSTEM_TIMER

  # Restore scoped timer, then test uninstall removes ToastBox units & hook while preserving issued certs.
  run_toastbox install -y --name restore-scoped-timer
  [ "$status" -eq 0 ]
  [ -f "$TB_SYSTEMD_DIR/$TB_HY2_ACME_TIMER" ]
  run_toastbox uninstall -y --purge
  [ "$status" -eq 0 ]
  [ ! -e "$TB_CERTBOT_HOOK_PATH" ]
  [ ! -e "$TB_SYSTEMD_DIR/$TB_HY2_ACME_TIMER" ]
  [ ! -e "$TB_SYSTEMD_DIR/$TB_HY2_ACME_SERVICE" ]
  [ -e "$TOASTBOX_CERTBOT_LIVE_DIR/toastbox-hy2-hy2.example.com/fullchain.pem" ]
}
