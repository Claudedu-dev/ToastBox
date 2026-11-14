# shellcheck shell=bash
#
# Xray: installation through the official XTLS/Xray-install script and
# server configuration rendering.
#
# Field names follow the current documentation (xtls.github.io):
#   inbound settings      users        (was: clients)
#   streamSettings        method: raw  (was: network: tcp)
#   realitySettings       target       (was: dest)
# which is why TB_XRAY_MIN_VERSION exists.

xray_service() { printf 'xray'; }
xray_process() { printf 'xray'; }
xray_config_path() { printf '%s' "$TB_XRAY_CONFIG"; }
xray_min_version() { printf '%s' "$TB_XRAY_MIN_VERSION"; }

xray_is_installed() { [[ -x "$TB_XRAY_BIN" ]]; }

# "Xray 26.11.9 (Xray, Penetrates Everything.) ..." -> 26.11.9
xray_version() {
  "$TB_XRAY_BIN" version 2>/dev/null | awk 'NR == 1 {print $2}'
}

xray_run_installer() {
  local script="$TB_TMP/xray-install.sh"
  if [[ ! -s "$script" ]]; then
    tb_download "$TB_XRAY_INSTALLER_URL" "$script" || die err_download "$TB_XRAY_INSTALLER_URL"
  fi
  bash "$script" "$@" >&2
}

# xray_install [VERSION]: installs or upgrades. The official installer
# creates the dedicated `xray` user, the systemd units and the directories
# with the permissions it expects.
xray_install() {
  local version="${1:-}"
  local -a args=(install)
  if [[ -n "$version" ]]; then
    args+=(--version "v${version#v}")
  fi
  xray_run_installer "${args[@]}"
}

xray_remove() {
  local purge="$1"
  local -a args=(remove)
  [[ "$purge" == "1" ]] && args+=(--purge)
  xray_run_installer "${args[@]}"
}

xray_validate() {
  "$TB_XRAY_BIN" run -test -c "$1"
}

# The service runs as the unprivileged `xray` user: the configuration holds
# the REALITY private key, so it is readable by root and that group only.
xray_install_config() {
  local src="$1" dir tmp mode="644" group="root"
  dir="$(dirname "$TB_XRAY_CONFIG")"
  tmp="$TB_XRAY_CONFIG.toastbox-new"
  # Without the dedicated group (Xray not installed by the official script)
  # the file has to stay world-readable for the service user.
  if getent group xray >/dev/null 2>&1; then
    mode="640"
    group="xray"
  fi
  install -d "$dir"
  install_owned "$mode" "$group" "$src" "$tmp"
  mv -f "$tmp" "$TB_XRAY_CONFIG"
}

# Xray loads exactly one file, so nothing else can leak into the node.
xray_extra_configs() { :; }

xray_render() {
  local ss_network
  case "$CFG_SS_NETWORK" in
    tcp) ss_network="tcp" ;;
    udp) ss_network="udp" ;;
    *) ss_network="tcp,udp" ;;
  esac

  jq -n \
    --arg listen "$CFG_LISTEN" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --argjson sockopt "$CFG_SOCKOPT" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target "$CFG_REALITY_TARGET" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$ss_network" \
    --args '
    def with_listen: if $listen == "" then . else {listen: $listen} + . end;
    # routeOnly: the sniffed protocol is used for routing only, the
    # destination of the connection is left untouched.
    def with_sniffing:
      if $block_bt == "1"
      then . + {sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}
      else . end;

    {
      log: {access: "none", logLevel: "warning"},
      inbounds: [
        (if $vless == "1" then
          {
            tag: "vless-reality",
            port: ($vless_port | tonumber),
            protocol: "vless",
            settings: {
              users: [{id: $uuid, flow: "xtls-rprx-vision"}],
              decryption: "none"
            },
            streamSettings: {
              method: "raw",
              security: "reality",
              realitySettings: {
                target: $target,
                serverNames: [$sni],
                privateKey: $private_key,
                shortIds: [$short_id]
              }
            } + (if $sockopt == {} then {} else {sockopt: $sockopt} end)
          } | with_listen | with_sniffing
        else empty end),
        (if $ss == "1" then
          {
            tag: "ss-2022",
            port: ($ss_port | tonumber),
            protocol: "shadowsocks",
            settings: {
              network: $ss_network,
              method: $ss_method,
              password: $ss_password
            }
          }
          # Socket overrides affect the TCP listener only, never UDP.
          + (if $sockopt != {} and $ss_network != "udp"
             then {streamSettings: {sockopt: $sockopt}} else {} end)
          | with_listen | with_sniffing
        else empty end)
      ],
      outbounds: [
        {tag: "direct", protocol: "freedom"},
        {tag: "block", protocol: "blackhole"}
      ],
      routing: {
        rules: [
          (if $block_bt == "1"
           then {protocol: ["bittorrent"], outboundTag: "block"} else empty end),
          (if $allow_private == "1"
           then empty else {ip: $ARGS.positional, outboundTag: "block"} end)
        ]
      }
    }' "${TB_PRIVATE_CIDRS[@]}"
}
