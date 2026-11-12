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
      firewall: {rules: $ARGS.positional}
    }' "${CFG_FW_RULES[@]}"
}

state_save() {
  local tmp
  install -d -m 700 "$TB_STATE_DIR"
  tmp="$(mktemp "$TB_STATE_DIR/.state.XXXXXX")"
  chmod 600 "$tmp"
  state_json >"$tmp"
  mv -f "$tmp" "$TB_STATE_FILE"
}

# Loads state.json into CFG_*. Returns 1 when there is no state yet.
state_load() {
  local assignments
  TB_HAS_STATE=0
  [[ -f "$TB_STATE_FILE" ]] || return 1

  # @sh quotes every value for the shell, so eval only ever sees literals.
  assignments="$(jq -r '
    def flag: if . == true then "1" else "0" end;
    def text: if . == null then "" else tostring end;
    if (.schema | type) != "number" then error("missing schema") else . end
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
      "CFG_FW_RULES=(" + ((.firewall.rules // []) | map(@sh) | join(" ")) + ")"
  ' "$TB_STATE_FILE" 2>/dev/null)" || die err_state_corrupt "$TB_STATE_FILE"

  eval "$assignments"
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
  install -d -m 700 "$TB_STATE_DIR" "$TB_BACKUP_DIR"
  dest="$TB_BACKUP_DIR/$prefix-$(date +%Y%m%d-%H%M%S)-$$.json"
  cp -p "$src" "$dest"
  chmod 600 "$dest"
  # Newest first; drop everything after the fifth.
  find "$TB_BACKUP_DIR" -maxdepth 1 -type f -name "$prefix-*.json" -printf '%T@ %p\n' |
    sort -rn | awk 'NR > 5 {sub(/^[^ ]+ /, ""); print}' |
    while IFS= read -r old; do
      rm -f "$old"
    done
  printf '%s' "$dest"
}
