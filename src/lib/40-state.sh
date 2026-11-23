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

  CFG_XHTTP=0
  CFG_XHTTP_TLS=""
  CFG_XHTTP_LISTEN=""
  CFG_XHTTP_PORT=""
  CFG_XHTTP_PUBLIC_PORT=""
  CFG_XHTTP_CONNECT_ADDR=""
  CFG_XHTTP_UUID=""
  CFG_XHTTP_HOST=""
  CFG_XHTTP_PATH=""
  CFG_XHTTP_MODE=""
  CFG_XHTTP_CLIENT_MODE=""
  CFG_XHTTP_ALPN=""
  CFG_XHTTP_CERT=""
  CFG_XHTTP_KEY=""
  CFG_XHTTP_CERT_SHA256=""
  CFG_XHTTP_CERT_FILE=""
  CFG_XHTTP_KEY_FILE=""
  CFG_XHTTP_CERTBOT_HOOK=0
  CFG_XHTTP_WS=0
  CFG_XHTTP_WS_PORT=""
  CFG_XHTTP_WS_PUBLIC_PORT=""
  CFG_XHTTP_WS_PATH=""
  CFG_XHTTP_WS_HEARTBEAT="$TB_XHTTP_DEFAULT_WS_HEARTBEAT"

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
    --arg xhttp "$CFG_XHTTP" \
    --arg xhttp_tls "$CFG_XHTTP_TLS" \
    --arg xhttp_listen "$CFG_XHTTP_LISTEN" \
    --arg xhttp_port "$CFG_XHTTP_PORT" \
    --arg xhttp_public_port "$CFG_XHTTP_PUBLIC_PORT" \
    --arg xhttp_connect_addr "$CFG_XHTTP_CONNECT_ADDR" \
    --arg xhttp_uuid "$CFG_XHTTP_UUID" \
    --arg xhttp_host "$CFG_XHTTP_HOST" \
    --arg xhttp_path "$CFG_XHTTP_PATH" \
    --arg xhttp_mode "$CFG_XHTTP_MODE" \
    --arg xhttp_client_mode "$CFG_XHTTP_CLIENT_MODE" \
    --arg xhttp_alpn "$CFG_XHTTP_ALPN" \
    --arg xhttp_cert "$CFG_XHTTP_CERT" \
    --arg xhttp_key "$CFG_XHTTP_KEY" \
    --arg xhttp_cert_sha256 "$CFG_XHTTP_CERT_SHA256" \
    --arg xhttp_cert_file "$CFG_XHTTP_CERT_FILE" \
    --arg xhttp_key_file "$CFG_XHTTP_KEY_FILE" \
    --arg xhttp_certbot_hook "$CFG_XHTTP_CERTBOT_HOOK" \
    --arg xhttp_ws "$CFG_XHTTP_WS" \
    --arg xhttp_ws_port "$CFG_XHTTP_WS_PORT" \
    --arg xhttp_ws_public_port "$CFG_XHTTP_WS_PUBLIC_PORT" \
    --arg xhttp_ws_path "$CFG_XHTTP_WS_PATH" \
    --arg xhttp_ws_heartbeat "$CFG_XHTTP_WS_HEARTBEAT" \
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
      xhttp: {
        enabled: ($xhttp == "1"),
        tls: $xhttp_tls,
        listen: $xhttp_listen,
        port: ($xhttp_port | port),
        public_port: ($xhttp_public_port | port),
        connect_addr: $xhttp_connect_addr,
        uuid: $xhttp_uuid,
        host: $xhttp_host,
        path: $xhttp_path,
        mode: $xhttp_mode,
        client_mode: $xhttp_client_mode,
        alpn: $xhttp_alpn,
        cert: $xhttp_cert,
        key: $xhttp_key,
        cert_sha256: $xhttp_cert_sha256,
        cert_file: $xhttp_cert_file,
        key_file: $xhttp_key_file,
        certbot_hook: ($xhttp_certbot_hook == "1"),
        ws: {
          enabled: ($xhttp_ws == "1"),
          port: ($xhttp_ws_port | port),
          public_port: ($xhttp_ws_public_port | port),
          path: $xhttp_ws_path,
          heartbeat: ($xhttp_ws_heartbeat | tonumber)
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

check_xhttp_core_support() {
  if [[ "$1" != "xray" && "$CFG_XHTTP" == "1" ]]; then
    die err_xhttp_core "$1"
  fi
}

xhttp_state_valid() {
  [[ "$CFG_XHTTP_WS_HEARTBEAT" =~ ^[0-9]+$ ]] &&
    ((10#$CFG_XHTTP_WS_HEARTBEAT >= 1 && 10#$CFG_XHTTP_WS_HEARTBEAT <= 3600)) || return 1
  if [[ "$CFG_XHTTP" == "1" ]]; then
    [[ "$CFG_XHTTP_TLS" == "none" || "$CFG_XHTTP_TLS" == "files" ]] || return 1
    if [[ -n "$CFG_XHTTP_LISTEN" ]]; then
      if [[ "$CFG_XHTTP_TLS" == "none" ]]; then
        hy2_hop_is_loopback "$CFG_XHTTP_LISTEN" || return 1
      fi
      valid_host "$CFG_XHTTP_LISTEN" || [[ "$CFG_XHTTP_LISTEN" == "::" ]] || return 1
    elif [[ "$CFG_XHTTP_TLS" == "none" ]]; then
      return 1
    fi
    if [[ "$CFG_XHTTP_TLS" == "files" ]]; then
      [[ -n "$CFG_XHTTP_CERT" && -n "$CFG_XHTTP_KEY" ]] || return 1
    fi
    valid_port "$CFG_XHTTP_PORT" || return 1
    valid_port "$CFG_XHTTP_PUBLIC_PORT" || return 1
    if [[ -n "$CFG_XHTTP_CONNECT_ADDR" ]]; then
      valid_host "$CFG_XHTTP_CONNECT_ADDR" || return 1
    fi
    valid_uuid "$CFG_XHTTP_UUID" || return 1
    valid_domain "$CFG_XHTTP_HOST" || return 1
    valid_xhttp_path "$CFG_XHTTP_PATH" || return 1
    in_list "$CFG_XHTTP_MODE" "${TB_XHTTP_MODES[@]}" || return 1
    in_list "$CFG_XHTTP_CLIENT_MODE" "${TB_XHTTP_MODES[@]}" || return 1
    in_list "$CFG_XHTTP_ALPN" "${TB_XHTTP_ALPNS[@]}" || return 1
    if [[ "$CFG_XHTTP_WS" == "1" ]]; then
      valid_port "$CFG_XHTTP_WS_PORT" || return 1
      valid_port "$CFG_XHTTP_WS_PUBLIC_PORT" || return 1
      valid_xhttp_path "$CFG_XHTTP_WS_PATH" || return 1
      ! xhttp_paths_conflict "$CFG_XHTTP_PATH" "$CFG_XHTTP_WS_PATH" || return 1
    fi
  fi
  return 0
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
    def ws_hb_int(defv):
      if . == null then defv
      elif (type == "number") and (. == floor) and . >= 1 and . <= 3600 then .
      else error("invalid xhttp ws heartbeat")
      end;
    if (.schema | type) != "number" then error("missing schema") else . end
    | if (.hy2.hop != null) and ((.hy2.hop | type) != "object") then error("invalid hy2.hop") else . end
    | if (.hy2.hop.ports != null) and ((.hy2.hop.ports | type) != "string") then error("invalid hy2.hop.ports") else . end
    | if (.hy2.certbot_hook != null) and ((.hy2.certbot_hook | type) != "boolean") then error("invalid hy2.certbot_hook") else . end
    | if (.hy2.acme != null) and ((.hy2.acme | type) != "object") then error("invalid hy2.acme") else . end
    | if (.hy2.acme.enabled != null) and ((.hy2.acme.enabled | type) != "boolean") then error("invalid hy2.acme.enabled") else . end
    | if (.xhttp != null) and ((.xhttp | type) != "object") then error("invalid xhttp") else . end
    | if (.xhttp.enabled != null) and ((.xhttp.enabled | type) != "boolean") then error("invalid xhttp.enabled") else . end
    | if (.xhttp.certbot_hook != null) and ((.xhttp.certbot_hook | type) != "boolean") then error("invalid xhttp.certbot_hook") else . end
    | if (.xhttp.ws != null) and ((.xhttp.ws | type) != "object") then error("invalid xhttp.ws") else . end
    | if (.xhttp.ws.enabled != null) and ((.xhttp.ws.enabled | type) != "boolean") then error("invalid xhttp.ws.enabled") else . end
    | ((.hy2.hop.interval_min | hop_int(30))) as $hmin
    | ((.hy2.hop.interval_max | hop_int(30))) as $hmax
    | ((.xhttp.ws.heartbeat | ws_hb_int('"$TB_XHTTP_DEFAULT_WS_HEARTBEAT"'))) as $xhb
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
      @sh "CFG_XHTTP=\(.xhttp.enabled | flag)",
      @sh "CFG_XHTTP_TLS=\(.xhttp.tls | text)",
      @sh "CFG_XHTTP_LISTEN=\(.xhttp.listen | text)",
      @sh "CFG_XHTTP_PORT=\(.xhttp.port | text)",
      @sh "CFG_XHTTP_PUBLIC_PORT=\(.xhttp.public_port | text)",
      @sh "CFG_XHTTP_CONNECT_ADDR=\(.xhttp.connect_addr | text)",
      @sh "CFG_XHTTP_UUID=\(.xhttp.uuid | text)",
      @sh "CFG_XHTTP_HOST=\(.xhttp.host | text)",
      @sh "CFG_XHTTP_PATH=\(.xhttp.path | text)",
      @sh "CFG_XHTTP_MODE=\(.xhttp.mode | text)",
      @sh "CFG_XHTTP_CLIENT_MODE=\(.xhttp.client_mode | text)",
      @sh "CFG_XHTTP_ALPN=\(.xhttp.alpn | text)",
      @sh "CFG_XHTTP_CERT=\(.xhttp.cert | text)",
      @sh "CFG_XHTTP_KEY=\(.xhttp.key | text)",
      @sh "CFG_XHTTP_CERT_SHA256=\(.xhttp.cert_sha256 | text)",
      @sh "CFG_XHTTP_CERT_FILE=\(.xhttp.cert_file | text)",
      @sh "CFG_XHTTP_KEY_FILE=\(.xhttp.key_file | text)",
      @sh "CFG_XHTTP_CERTBOT_HOOK=\(.xhttp.certbot_hook | flag)",
      @sh "CFG_XHTTP_WS=\(.xhttp.ws.enabled | flag)",
      @sh "CFG_XHTTP_WS_PORT=\(.xhttp.ws.port | text)",
      @sh "CFG_XHTTP_WS_PUBLIC_PORT=\(.xhttp.ws.public_port | text)",
      @sh "CFG_XHTTP_WS_PATH=\(.xhttp.ws.path | text)",
      @sh "CFG_XHTTP_WS_HEARTBEAT=\($xhb | tostring)",
      "CFG_FW_RULES=(" + ((.firewall.rules // []) | map(@sh) | join(" ")) + ")"
  ' "$TB_STATE_FILE" 2>/dev/null)" || die err_state_corrupt "$TB_STATE_FILE"

  eval "$assignments"
  if ! hy2_hop_validate_saved "$CFG_HY2_HOP_PORTS" "$CFG_HY2_HOP_INTERVAL_MIN" "$CFG_HY2_HOP_INTERVAL_MAX" ||
    ! xhttp_state_valid; then
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
