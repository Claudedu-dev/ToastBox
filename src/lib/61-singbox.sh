# shellcheck shell=bash
#
# sing-box: installation from the official APT repository and server
# configuration rendering.
#
# Only the current configuration format is written (sing-box.sagernet.org):
# no legacy inbound fields (`sniff`, `domain_strategy`) and no special
# outbounds (`block`, `dns`), which were replaced by rule actions in 1.11.

singbox_service() { printf 'sing-box'; }
singbox_process() { printf 'sing-box'; }
singbox_config_path() { printf '%s' "$TB_SINGBOX_CONFIG"; }
singbox_min_version() { printf '%s' "$TB_SINGBOX_MIN_VERSION"; }

singbox_is_installed() { [[ -x "$TB_SINGBOX_BIN" ]]; }

# "sing-box version 1.14.4" -> 1.14.4
singbox_version() {
  "$TB_SINGBOX_BIN" version 2>/dev/null | awk 'NR == 1 {print $3}'
}

singbox_setup_repo() {
  install -d -m 755 /etc/apt/keyrings
  tb_download "$TB_SINGBOX_KEY_URL" "$TB_SINGBOX_KEYRING" || die err_download "$TB_SINGBOX_KEY_URL"
  chmod a+r "$TB_SINGBOX_KEYRING"
  cat >"$TB_SINGBOX_APT_SOURCE" <<EOF
Types: deb
URIs: $TB_SINGBOX_APT_URL
Suites: *
Components: *
Enabled: yes
Signed-By: $TB_SINGBOX_KEYRING
EOF
}

# singbox_install [VERSION]: installs or upgrades the `sing-box` package.
#
# The package ships /etc/sing-box/config.json as a sample (a Shadowsocks
# inbound with a published password) but does not start the service, so
# nothing is exposed until ToastBox has replaced that file.
singbox_install() {
  local version="${1:-}" package="sing-box"
  singbox_setup_repo
  apt-get update >&2 || die err_apt_update
  if [[ -n "$version" ]]; then
    # Debian versions use "~" where the release tag has "-".
    version="${version#v}"
    package="sing-box=${version//-/\~}"
  fi
  apt_install --allow-downgrades "$package" || die err_apt_install "$package"
}

singbox_remove() {
  local purge="$1"
  if [[ "$purge" == "1" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sing-box >&2 || true
    rm -rf "$(dirname "$TB_SINGBOX_CONFIG")" /var/lib/sing-box
    rm -f "$TB_SINGBOX_APT_SOURCE" "$TB_SINGBOX_KEYRING"
  else
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sing-box >&2 || true
  fi
}

singbox_validate() {
  "$TB_SINGBOX_BIN" check -c "$1"
}

# The packaged unit runs sing-box as root, so root-only permissions work.
singbox_install_config() {
  local src="$1" dir tmp
  dir="$(dirname "$TB_SINGBOX_CONFIG")"
  # The temporary name must not end in .json: the service merges every
  # *.json file in this directory.
  tmp="$TB_SINGBOX_CONFIG.toastbox-new"
  install -d "$dir"
  install_owned 600 root "$src" "$tmp"
  mv -f "$tmp" "$TB_SINGBOX_CONFIG"
}

# The unit starts sing-box with `-C /etc/sing-box`, which merges all JSON
# files in that directory. Lists the ones ToastBox does not manage.
singbox_extra_configs() {
  local dir file
  dir="$(dirname "$TB_SINGBOX_CONFIG")"
  [[ -d "$dir" ]] || return 0
  for file in "$dir"/*.json; do
    [[ -e "$file" && "$file" != "$TB_SINGBOX_CONFIG" ]] && printf '%s\n' "$file"
  done
  return 0
}

singbox_render() {
  local listen="$CFG_LISTEN"
  if [[ -z "$listen" ]]; then
    # `listen` is required. "::" is dual-stack, but fails to bind on hosts
    # where IPv6 is disabled.
    if ipv6_enabled; then listen="::"; else listen="0.0.0.0"; fi
  fi

  jq -n \
    --arg listen "$listen" \
    --arg block_bt "$CFG_BLOCK_BT" \
    --arg allow_private "$CFG_ALLOW_PRIVATE" \
    --arg vless "$CFG_VLESS" \
    --arg vless_port "$CFG_VLESS_PORT" \
    --arg uuid "$CFG_VLESS_UUID" \
    --arg sni "$CFG_REALITY_SNI" \
    --arg target_host "$(host_of "$CFG_REALITY_TARGET")" \
    --arg target_port "$(port_of "$CFG_REALITY_TARGET")" \
    --arg private_key "$CFG_REALITY_PRIVATE_KEY" \
    --arg short_id "$CFG_REALITY_SHORT_ID" \
    --arg ss "$CFG_SS" \
    --arg ss_port "$CFG_SS_PORT" \
    --arg ss_method "$CFG_SS_METHOD" \
    --arg ss_password "$CFG_SS_PASSWORD" \
    --arg ss_network "$CFG_SS_NETWORK" '
    {
      log: {level: "warn", timestamp: true},
      inbounds: [
        (if $vless == "1" then
          {
            type: "vless",
            tag: "vless-reality",
            listen: $listen,
            listen_port: ($vless_port | tonumber),
            users: [{name: "toastbox", uuid: $uuid, flow: "xtls-rprx-vision"}],
            tls: {
              enabled: true,
              server_name: $sni,
              reality: {
                enabled: true,
                handshake: {server: $target_host, server_port: ($target_port | tonumber)},
                private_key: $private_key,
                short_id: [$short_id]
              }
            }
          }
        else empty end),
        (if $ss == "1" then
          {
            type: "shadowsocks",
            tag: "ss-2022",
            listen: $listen,
            listen_port: ($ss_port | tonumber)
          }
          # An absent `network` means TCP and UDP.
          + (if $ss_network == "tcp" or $ss_network == "udp" then {network: $ss_network} else {} end)
          + {method: $ss_method, password: $ss_password}
        else empty end)
      ],
      outbounds: [
        {type: "direct", tag: "direct"}
      ],
      route: {
        rules: [
          (if $block_bt == "1" then
            {action: "sniff"},
            {protocol: "bittorrent", action: "reject"}
          else empty end),
          (if $allow_private == "1"
           then empty else {ip_is_private: true, action: "reject"} end)
        ],
        final: "direct"
      }
    }'
}
