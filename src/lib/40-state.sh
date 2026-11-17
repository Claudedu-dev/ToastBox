# shellcheck shell=bash
#
# The node description (CFG_*) and its persistence in state.json.
#
# state.json is the single source of truth for a deployed node: the server
# configuration, the share links and the client configurations are all
# rendered from it, which is what makes re-runs idempotent and lets
# `toastbox show` reprint everything later.

TB_STATE_SCHEMA=1
TB_HAS_STATE=0

cfg_reset() {
  CFG_CORE=""
  CFG_SERVER_ADDR=""
  CFG_NODE_NAME=""
  CFG_LISTEN=""
  CFG_BLOCK_BT=0
  CFG_ALLOW_PRIVATE=0
  # Optional Xray TCP listener settings. Empty means core/system defaults.
  CFG_SOCKOPT='{}'

  CFG_VLESS=0
  CFG_VLESS_PORT=""
  CFG_VLESS_UUID=""
  CFG_REALITY_SNI=""
  CFG_REALITY_TARGET=""
  CFG_REALITY_PRIVATE_KEY=""
  CFG_REALITY_PUBLIC_KEY=""
  CFG_REALITY_SHORT_ID=""

  CFG_SS=0
  CFG_SS_PORT=""
  CFG_SS_METHOD=""
  CFG_SS_PASSWORD=""
  CFG_SS_NETWORK=""

  CFG_HY2=0
  CFG_HY2_PORT=""
  CFG_HY2_PASSWORD=""
  CFG_HY2_TLS=""
  CFG_HY2_SNI=""
  CFG_HY2_CERT=""
  CFG_HY2_KEY=""
  CFG_HY2_CERT_SHA256=""
  CFG_HY2_OBFS=""
  CFG_HY2_OBFS_PASSWORD=""
  CFG_HY2_MASQUERADE=""
  CFG_HY2_CERT_FILE=""
  CFG_HY2_KEY_FILE=""
  CFG_HY2_CERTBOT_HOOK=0
  CFG_HY2_ACME=0
  CFG_HY2_ACME_DOMAIN=""
  CFG_HY2_ACME_EMAIL=""
  CFG_HY2_ACME_LINEAGE=""
  CFG_HY2_HOP_PORTS=""
  CFG_HY2_HOP_INTERVAL_MIN=30
  CFG_HY2_HOP_INTERVAL_MAX=30

  CFG_FW_RULES=()
}
cfg_reset

# Prints the state document for the current CFG_* values.
state_json() {
  jq -n \
    --argjson schema "$TB_STATE_SCHEMA" \
    --arg core "$CFG_CORE" \
    --arg server_addr "$CFG_SERVER_ADDR" \
    --arg node_name "$CFG_NODE_NAME" \
    --arg listen "$CFG_LISTEN" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --argjson sockopt "$CFG_SOCKOPT" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg vless_uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target "$CFG_REALITY_TARGET" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg public_key "$CFG_REALITY_PUBLIC_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$CFG_SS_NETWORK" \
    --arg hy2 "$CFG_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_tls "$CFG_HY2_TLS" \
    --arg hy2_sni "$CFG_HY2_SNI" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_key "$CFG_HY2_KEY" \
    --arg hy2_cert_sha256 "$CFG_HY2_CERT_SHA256" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_masquerade "$CFG_HY2_MASQUERADE" \
    --arg hy2_cert_file "$CFG_HY2_CERT_FILE" \
    --arg hy2_key_file "$CFG_HY2_KEY_FILE" \
    --arg hy2_certbot_hook "$CFG_HY2_CERTBOT_HOOK" \
    --arg hy2_acme "$CFG_HY2_ACME" \
    --arg hy2_acme_domain "$CFG_HY2_ACME_DOMAIN" \
    --arg hy2_acme_email "$CFG_HY2_ACME_EMAIL" \
    --arg hy2_acme_lineage "$CFG_HY2_ACME_LINEAGE" \
    --arg hy2_hop_ports "$CFG_HY2_HOP_PORTS" \
    --arg hy2_hop_min "$CFG_HY2_HOP_INTERVAL_MIN" \
    --arg hy2_hop_max "$CFG_HY2_HOP_INTERVAL_MAX" \
    --args '
    def port: if . == "" then null else tonumber end;
    {
      schema: $schema,
      core: $core,
      server_addr: $server_addr,
      node_name: $node_name,
      listen: $listen,
      block_bt: ($block_bt == "1"),
      allow_private: ($allow_private == "1"),
      sockopt: $sockopt,
      vless: {
        enabled: ($vless == "1"),
        port: ($vless_port | port),
        uuid: $vless_uuid,
        sni: $sni,
        target: $target,
        private_key: $private_key,
        public_key: $public_key,
        short_id: $short_id
      },
      ss: {
        enabled: ($ss == "1"),
        port: ($ss_port | port),
        method: $ss_method,
        password: $ss_password,
        network: $ss_network
      },
      hy2: {
        enabled: ($hy2 == "1"),
        port: ($hy2_port | port),
        password: $hy2_password,
        tls: $hy2_tls,
        sni: $hy2_sni,
        cert: $hy2_cert,
        key: $hy2_key,
        cert_sha256: $hy2_cert_sha256,
        obfs: $hy2_obfs,
        obfs_password: $hy2_obfs_password,
        masquerade: $hy2_masquerade,
        cert_file: $hy2_cert_file,
        key_file: $hy2_key_file,
        certbot_hook: ($hy2_certbot_hook == "1"),
        acme: (if $hy2_acme == "1" then {
          enabled: true,
          domain: $hy2_acme_domain,
          email: $hy2_acme_email,
          lineage: $hy2_acme_lineage
        } else {
          enabled: false
        } end),
        hop: {
          ports: $hy2_hop_ports,
          interval_min: ($hy2_hop_min | tonumber),
          interval_max: ($hy2_hop_max | tonumber)
        }
      },
      firewall: {rules: $ARGS.positional}
    }' "${CFG_FW_RULES[@]}"
}

state_save() {
  local tmp
  install -d -m 700 "$TB_STATE_DIR" || return 1
  tmp="$(mktemp "$TB_STATE_DIR/.state.XXXXXX")" || return 1
  if ! chmod 600 "$tmp" || ! state_json >"$tmp" || ! mv -f "$tmp" "$TB_STATE_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

# Only these Linux TCP options are supported. Values are JSON integers;
# zero is represented by an absent key, not an explicit socket override.
sockopt_valid() {
  jq -e '
    type == "object" and all(to_entries[];
      (.key == "tcpKeepAliveIdle" or .key == "tcpKeepAliveInterval" or .key == "tcpUserTimeout")
      and (.value | type == "number")
      and (.value == (.value | floor)) and .value > 0
      and .value <= (if .key == "tcpUserTimeout" then 2147483647 else 32767 end)
    )' <<<"$1" >/dev/null 2>&1
}

check_sockopt_support() {
  if [[ "$1" != "xray" && "$CFG_SOCKOPT" != '{}' ]]; then
    die err_sockopt_core "$1"
  fi
}

# Loads state.json into CFG_*. Returns 1 when there is no state yet.
state_load() {
  local assignments sockopt
  TB_HAS_STATE=0
  [[ -f "$TB_STATE_FILE" ]] || return 1

  # Additive schema-1 field: older nodes have no custom sockopt. Reject
  # malformed options before any command can rewrite their configuration.
  if ! sockopt="$(jq -c 'if .sockopt == null then {} else .sockopt end' "$TB_STATE_FILE" 2>/dev/null)" ||
    ! sockopt_valid "$sockopt"; then
    die err_state_corrupt "$TB_STATE_FILE"
  fi

  # @sh quotes every value for the shell, so eval only ever sees literals.
  assignments="$(jq -r '
    def flag: if . == true then "1" else "0" end;
    def text: if . == null then "" else tostring end;
    def hop_int(defv):
      if . == null then defv
      elif (type == "number") and (. == floor) and . >= 5 and . <= 2147483647 then .
      else error("invalid hy2 hop interval")
      end;
    if (.schema | type) != "number" then error("missing schema") else . end
    | if (.hy2.hop != null) and ((.hy2.hop | type) != "object") then error("invalid hy2.hop") else . end
    | if (.hy2.hop.ports != null) and ((.hy2.hop.ports | type) != "string") then error("invalid hy2.hop.ports") else . end
    | if (.hy2.certbot_hook != null) and ((.hy2.certbot_hook | type) != "boolean") then error("invalid hy2.certbot_hook") else . end
    | if (.hy2.acme != null) and ((.hy2.acme | type) != "object") then error("invalid hy2.acme") else . end
    | if (.hy2.acme.enabled != null) and ((.hy2.acme.enabled | type) != "boolean") then error("invalid hy2.acme.enabled") else . end
    | ((.hy2.hop.interval_min | hop_int(30))) as $hmin
    | ((.hy2.hop.interval_max | hop_int(30))) as $hmax
    | if $hmin > $hmax then error("invalid hy2 hop interval range") else . end
    | @sh "CFG_CORE=\(.core | text)",
      @sh "CFG_SERVER_ADDR=\(.server_addr | text)",
      @sh "CFG_NODE_NAME=\(.node_name | text)",
      @sh "CFG_LISTEN=\(.listen | text)",
      @sh "CFG_BLOCK_BT=\(.block_bt | flag)",
      @sh "CFG_ALLOW_PRIVATE=\(.allow_private | flag)",
      @sh "CFG_VLESS=\(.vless.enabled | flag)",
      @sh "CFG_VLESS_PORT=\(.vless.port | text)",
      @sh "CFG_VLESS_UUID=\(.vless.uuid | text)",
      @sh "CFG_REALITY_SNI=\(.vless.sni | text)",
      @sh "CFG_REALITY_TARGET=\(.vless.target | text)",
      @sh "CFG_REALITY_PRIVATE_KEY=\(.vless.private_key | text)",
      @sh "CFG_REALITY_PUBLIC_KEY=\(.vless.public_key | text)",
      @sh "CFG_REALITY_SHORT_ID=\(.vless.short_id | text)",
      @sh "CFG_SS=\(.ss.enabled | flag)",
      @sh "CFG_SS_PORT=\(.ss.port | text)",
      @sh "CFG_SS_METHOD=\(.ss.method | text)",
      @sh "CFG_SS_PASSWORD=\(.ss.password | text)",
      @sh "CFG_SS_NETWORK=\(.ss.network | text)",
      @sh "CFG_HY2=\(.hy2.enabled | flag)",
      @sh "CFG_HY2_PORT=\(.hy2.port | text)",
      @sh "CFG_HY2_PASSWORD=\(.hy2.password | text)",
      @sh "CFG_HY2_TLS=\(.hy2.tls | text)",
      @sh "CFG_HY2_SNI=\(.hy2.sni | text)",
      @sh "CFG_HY2_CERT=\(.hy2.cert | text)",
      @sh "CFG_HY2_KEY=\(.hy2.key | text)",
      @sh "CFG_HY2_CERT_SHA256=\(.hy2.cert_sha256 | text)",
      @sh "CFG_HY2_OBFS=\(.hy2.obfs | text)",
      @sh "CFG_HY2_OBFS_PASSWORD=\(.hy2.obfs_password | text)",
      @sh "CFG_HY2_MASQUERADE=\(.hy2.masquerade | text)",
      @sh "CFG_HY2_CERT_FILE=\(.hy2.cert_file | text)",
      @sh "CFG_HY2_KEY_FILE=\(.hy2.key_file | text)",
      @sh "CFG_HY2_CERTBOT_HOOK=\(.hy2.certbot_hook | flag)",
      @sh "CFG_HY2_ACME=\(.hy2.acme.enabled | flag)",
      @sh "CFG_HY2_ACME_DOMAIN=\(.hy2.acme.domain | text)",
      @sh "CFG_HY2_ACME_EMAIL=\(.hy2.acme.email | text)",
      @sh "CFG_HY2_ACME_LINEAGE=\(.hy2.acme.lineage | text)",
      @sh "CFG_HY2_HOP_PORTS=\(.hy2.hop.ports | text)",
      @sh "CFG_HY2_HOP_INTERVAL_MIN=\($hmin | tostring)",
      @sh "CFG_HY2_HOP_INTERVAL_MAX=\($hmax | tostring)",
      "CFG_FW_RULES=(" + ((.firewall.rules // []) | map(@sh) | join(" ")) + ")"
  ' "$TB_STATE_FILE" 2>/dev/null)" || die err_state_corrupt "$TB_STATE_FILE"

  eval "$assignments"
  if ! hy2_hop_validate_saved "$CFG_HY2_HOP_PORTS" "$CFG_HY2_HOP_INTERVAL_MIN" "$CFG_HY2_HOP_INTERVAL_MAX"; then
    die err_state_corrupt "$TB_STATE_FILE"
  fi
  CFG_SOCKOPT="$sockopt"
  TB_HAS_STATE=1
}

state_remove() {
  rm -f "$TB_STATE_FILE"
}

# backup_file PATH PREFIX: copies PATH into the backup directory and keeps
# the five most recent copies for that prefix. Prints the backup path.
backup_file() {
  local src="$1" prefix="$2" dest old
  [[ -f "$src" ]] || return 0
  install -d -m 700 "$TB_STATE_DIR" "$TB_BACKUP_DIR" || return 1
  dest="$TB_BACKUP_DIR/$prefix-$(date +%Y%m%d-%H%M%S)-$$.json"
  if ! cp -p "$src" "$dest" || ! chmod 600 "$dest"; then
    rm -f "$dest"
    return 1
  fi
  # Newest first; drop everything after the fifth.
  find "$TB_BACKUP_DIR" -maxdepth 1 -type f -name "$prefix-*.json" -printf '%T@ %p\n' |
    sort -rn | awk 'NR > 5 {sub(/^[^ ]+ /, ""); print}' |
    while IFS= read -r old; do
      rm -f "$old"
    done || true
  printf '%s' "$dest"
}
