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

XRAY_CFG_OWNER="root"
XRAY_CFG_GROUP="root"
XRAY_CFG_MODE="600"

xray_is_dedicated_group() {
  case "$1" in
    "" | root | nogroup | nobody | users) return 1 ;;
    *) getent group "$1" >/dev/null 2>&1 ;;
  esac
}

xray_first_dedicated_group() {
  local -a groups=()
  local grp
  [[ -n "$1" ]] || return 1
  IFS=' ' read -r -a groups <<<"$1"
  for grp in "${groups[@]}"; do
    if xray_is_dedicated_group "$grp"; then
      printf '%s' "$grp"
      return 0
    fi
  done
  return 1
}

# Resolves owner, group and mode for TB_XRAY_CONFIG from the xray systemd
# unit so credentials are never exposed world-readable (0644).
xray_config_perms() {
  local svc svc_user="" svc_group="" supp_groups="" dyn_user=""
  local primary_gid="" primary_grp="" grp=""
  XRAY_CFG_OWNER="root"
  XRAY_CFG_GROUP="root"
  XRAY_CFG_MODE="600"

  svc="$(xray_service)"
  if service_unit_exists "$svc"; then
    svc_user="$(service_unit_prop "$svc" User)"
    svc_group="$(service_unit_prop "$svc" Group)"
    supp_groups="$(service_unit_prop "$svc" SupplementaryGroups)"
    dyn_user="$(service_unit_prop "$svc" DynamicUser)"

    # When the unit runs as root, keep the configuration strictly root-only.
    if [[ "$dyn_user" != "yes" ]] &&
      [[ -z "$svc_user" || "$svc_user" == "root" || "$svc_user" == "0" ]]; then
      return 0
    fi

    if xray_is_dedicated_group "$svc_group"; then
      XRAY_CFG_GROUP="$svc_group"
      XRAY_CFG_MODE="640"
      return 0
    fi

    if [[ "$dyn_user" == "yes" ]]; then
      if grp="$(xray_first_dedicated_group "$supp_groups")"; then
        XRAY_CFG_GROUP="$grp"
        XRAY_CFG_MODE="640"
        return 0
      fi
      log_err err_xray_dynamic_user "$svc" "$TB_XRAY_CONFIG"
      return 1
    fi

    primary_gid="$(getent passwd "$svc_user" 2>/dev/null | awk -F: 'NR == 1 {print $4}')"
    if [[ -z "$primary_gid" ]]; then
      log_err err_xray_service_user "$svc" "$svc_user"
      return 1
    fi
    primary_grp="$(getent group "$primary_gid" 2>/dev/null | awk -F: 'NR == 1 {print $1}')"
    if [[ -z "$svc_group" ]] && xray_is_dedicated_group "$primary_grp"; then
      XRAY_CFG_GROUP="$primary_grp"
      XRAY_CFG_MODE="640"
      return 0
    fi

    if grp="$(xray_first_dedicated_group "$supp_groups")"; then
      XRAY_CFG_GROUP="$grp"
      XRAY_CFG_MODE="640"
      return 0
    fi

    # Service runs as an unprivileged user without a dedicated group (e.g.
    # nobody or a system account in nogroup): restrict reads to that UID only.
    XRAY_CFG_OWNER="$svc_user"
    XRAY_CFG_GROUP="root"
    XRAY_CFG_MODE="600"
    return 0
  fi

  # Fallback when systemd is unavailable or the unit is not installed yet.
  if getent group xray >/dev/null 2>&1; then
    XRAY_CFG_GROUP="xray"
    XRAY_CFG_MODE="640"
  elif getent passwd xray >/dev/null 2>&1; then
    XRAY_CFG_OWNER="xray"
    XRAY_CFG_GROUP="root"
    XRAY_CFG_MODE="600"
  fi
  return 0
}

# The service usually runs as the unprivileged `xray` user: the configuration
# holds the REALITY private key, so access is restricted to root and the
# service identity (never world-readable).
xray_install_config() {
  local src="$1" dir tmp
  dir="$(dirname "$TB_XRAY_CONFIG")"
  tmp="$TB_XRAY_CONFIG.toastbox-new"
  xray_config_perms || return 1
  if [[ ! -d "$dir" ]]; then
    install -d -m 755 "$dir" || return 1
  fi
  if ! install_owned "$XRAY_CFG_MODE" "$XRAY_CFG_OWNER" "$XRAY_CFG_GROUP" "$src" "$tmp" ||
    ! mv -f "$tmp" "$TB_XRAY_CONFIG"; then
    rm -f "$tmp"
    return 1
  fi
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
    --arg hy2 "$CFG_HY2" \
    --arg hy2_port "$CFG_HY2_PORT" \
    --arg hy2_password "$CFG_HY2_PASSWORD" \
    --arg hy2_cert "$CFG_HY2_CERT" \
    --arg hy2_key "$CFG_HY2_KEY" \
    --arg hy2_obfs "$CFG_HY2_OBFS" \
    --arg hy2_obfs_password "$CFG_HY2_OBFS_PASSWORD" \
    --arg hy2_masquerade "$CFG_HY2_MASQUERADE" \
    --arg xhttp "$CFG_XHTTP" \
    --arg xhttp_tls "$CFG_XHTTP_TLS" \
    --arg xhttp_listen "$CFG_XHTTP_LISTEN" \
    --arg xhttp_port "$CFG_XHTTP_PORT" \
    --arg xhttp_uuid "$CFG_XHTTP_UUID" \
    --arg xhttp_host "$CFG_XHTTP_HOST" \
    --arg xhttp_path "$CFG_XHTTP_PATH" \
    --arg xhttp_mode "$CFG_XHTTP_MODE" \
    --arg xhttp_cert "$CFG_XHTTP_CERT" \
    --arg xhttp_key "$CFG_XHTTP_KEY" \
    --arg xhttp_ws "$CFG_XHTTP_WS" \
    --arg xhttp_ws_port "$CFG_XHTTP_WS_PORT" \
    --arg xhttp_ws_path "$CFG_XHTTP_WS_PATH" \
    --arg xhttp_ws_heartbeat "$CFG_XHTTP_WS_HEARTBEAT" \
    --args '
    def with_listen: if $listen == "" then . else {listen: $listen} + . end;
    def with_xhttp_listen:
      if $xhttp_listen != "" then {listen: $xhttp_listen} + .
      elif $listen != "" then {listen: $listen} + .
      else . end;
    # routeOnly: the sniffed protocol is used for routing only, the
    # destination of the connection is left untouched.
    def with_sniffing:
      if $block_bt == "1"
      then . + {sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}
      else . end;
    def pem_lines: sub("\n+$"; "") | split("\n");

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
            streamSettings: ({
              method: "raw",
              security: "reality",
              realitySettings: {
                target: $target,
                serverNames: [$sni],
                privateKey: $private_key,
                shortIds: [$short_id]
              }
            } + (if $sockopt == {} then {} else {sockopt: $sockopt} end))
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
        else empty end),
        (if $hy2 == "1" then
          {
            tag: "hysteria2",
            port: ($hy2_port | tonumber),
            protocol: "hysteria",
            settings: {
              version: 2,
              users: [{auth: $hy2_password}]
            },
            streamSettings: ({
              method: "hysteria",
              security: "tls",
              tlsSettings: {
                alpn: ["h3"],
                certificates: [
                  {
                    certificate: ($hy2_cert | pem_lines),
                    key: ($hy2_key | pem_lines)
                  }
                ]
              },
              hysteriaSettings: ({
                version: 2
              } + (if $hy2_masquerade != "" then {
                masquerade: {
                  type: "proxy",
                  url: $hy2_masquerade,
                  rewriteHost: true
                }
              } else {} end))
            } + (if $hy2_obfs == "salamander" then {
              finalmask: {
                udp: [
                  {
                    type: "salamander",
                    settings: {password: $hy2_obfs_password}
                  }
                ]
              }
            } else {} end))
          } | with_listen | with_sniffing
        else empty end),
        (if $xhttp == "1" then
          {
            tag: "vless-xhttp",
            port: ($xhttp_port | tonumber),
            protocol: "vless",
            settings: {
              users: [{id: $xhttp_uuid}],
              decryption: "none"
            },
            streamSettings: (
              if $xhttp_tls == "files" then
                {
                  method: "xhttp",
                  security: "tls",
                  tlsSettings: {
                    serverName: $xhttp_host,
                    rejectUnknownSni: true,
                    alpn: ["h2", "http/1.1"],
                    certificates: [
                      {
                        certificate: ($xhttp_cert | pem_lines),
                        key: ($xhttp_key | pem_lines)
                      }
                    ]
                  },
                  xhttpSettings: {
                    host: $xhttp_host,
                    path: $xhttp_path,
                    mode: $xhttp_mode
                  }
                } + (if $sockopt == {} then {} else {sockopt: $sockopt} end)
              else
                {
                  method: "xhttp",
                  security: "none",
                  xhttpSettings: {
                    path: $xhttp_path,
                    mode: $xhttp_mode
                  }
                }
              end
            )
          } | with_xhttp_listen | with_sniffing
        else empty end),
        (if $xhttp == "1" and $xhttp_ws == "1" then
          {
            tag: "vless-ws-keepalive",
            port: ($xhttp_ws_port | tonumber),
            protocol: "vless",
            settings: {
              users: [{id: $xhttp_uuid}],
              decryption: "none"
            },
            streamSettings: (
              if $xhttp_tls == "files" then
                {
                  method: "websocket",
                  security: "tls",
                  tlsSettings: {
                    serverName: $xhttp_host,
                    rejectUnknownSni: true,
                    alpn: ["http/1.1"],
                    certificates: [
                      {
                        certificate: ($xhttp_cert | pem_lines),
                        key: ($xhttp_key | pem_lines)
                      }
                    ]
                  },
                  wsSettings: {
                    host: $xhttp_host,
                    path: $xhttp_ws_path,
                    heartbeatPeriod: ($xhttp_ws_heartbeat | tonumber)
                  }
                } + (if $sockopt == {} then {} else {sockopt: $sockopt} end)
              else
                {
                  method: "websocket",
                  security: "none",
                  wsSettings: {
                    path: $xhttp_ws_path,
                    heartbeatPeriod: ($xhttp_ws_heartbeat | tonumber)
                  }
                }
              end
            )
          } | with_xhttp_listen | with_sniffing
        else empty end)
      ],
      outbounds: [
        ({tag: "direct", protocol: "freedom"}
         + (if $allow_private == "1"
            then {settings: {finalRules: [{action: "allow"}]}}
            else {} end)),
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
