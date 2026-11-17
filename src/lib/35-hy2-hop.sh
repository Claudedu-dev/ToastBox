# shellcheck shell=bash
#
# Hysteria 2 UDP port hopping: port set and interval normalization,
# conflict checks, nftables/iptables PREROUTING NAT management and systemd
# persistence. Server core configs remain single-port listeners.

HY2_HOP_V4=0
HY2_HOP_V6=0
HY2_HOP_BACKEND=""
PARSED_HOP_MIN=30
PARSED_HOP_MAX=30

# norm_hy2_hop_ports VALUE: accepts "none"/"off" or comma-separated ports and
# start-end ranges (1..65535), sorts and merges overlapping/adjacent intervals,
# and requires at least two distinct ports when enabling hopping.
norm_hy2_hop_ports() {
  local raw="$1" token s e cur_s="" cur_e="" count=0
  local -a items=() ranges=() merged_ports=()

  case "$raw" in
    none | off)
      printf 'none'
      return 0
      ;;
    "" | ,* | *, | *,,*) return 1 ;;
  esac
  [[ "$raw" != *[[:space:]]* ]] || return 1

  IFS=',' read -r -a items <<<"$raw"
  ((${#items[@]} > 0)) || return 1

  for token in "${items[@]}"; do
    if [[ "$token" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
      s="${BASH_REMATCH[1]}"
      e="${BASH_REMATCH[2]}"
      valid_port "$s" && valid_port "$e" || return 1
      s=$((10#$s))
      e=$((10#$e))
      ((s <= e)) || return 1
    elif valid_port "$token"; then
      s=$((10#$token))
      e="$s"
    else
      return 1
    fi
    ranges+=("$(printf '%05d %05d' "$s" "$e")")
  done

  while IFS=' ' read -r s e; do
    s=$((10#$s))
    e=$((10#$e))
    if [[ -z "$cur_s" ]]; then
      cur_s="$s"
      cur_e="$e"
    elif ((s <= cur_e + 1)); then
      ((e > cur_e)) && cur_e="$e"
    else
      count=$((count + cur_e - cur_s + 1))
      if ((cur_s == cur_e)); then
        merged_ports+=("$cur_s")
      else
        merged_ports+=("$cur_s-$cur_e")
      fi
      cur_s="$s"
      cur_e="$e"
    fi
  done < <(printf '%s\n' "${ranges[@]}" | sort -n -k1,1 -k2,2)

  count=$((count + cur_e - cur_s + 1))
  ((count >= 2)) || return 1
  if ((cur_s == cur_e)); then
    merged_ports+=("$cur_s")
  else
    merged_ports+=("$cur_s-$cur_e")
  fi
  join_by , "${merged_ports[@]}"
}

# norm_hy2_hop_interval VALUE: accepts integer seconds N or MIN-MAX with
# 5 <= MIN <= MAX <= 2147483647 (matching Xray's Int32Range bound).
norm_hy2_hop_interval() {
  local raw="$1" lo hi
  if [[ "$raw" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    lo="$(norm_socket_int "${BASH_REMATCH[1]}" 2147483647)" || return 1
    hi="$(norm_socket_int "${BASH_REMATCH[2]}" 2147483647)" || return 1
    ((lo >= 5 && hi >= 5 && lo <= hi)) || return 1
    if ((lo == hi)); then
      printf '%d' "$lo"
    else
      printf '%d-%d' "$lo" "$hi"
    fi
  else
    lo="$(norm_socket_int "$raw" 2147483647)" || return 1
    ((lo >= 5)) || return 1
    printf '%d' "$lo"
  fi
}

hy2_hop_parse_interval() {
  local canon
  canon="$(norm_hy2_hop_interval "$1")" || return 1
  if [[ "$canon" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    PARSED_HOP_MIN="${BASH_REMATCH[1]}"
    PARSED_HOP_MAX="${BASH_REMATCH[2]}"
  else
    PARSED_HOP_MIN="$canon"
    PARSED_HOP_MAX="$canon"
  fi
}

# hy2_hop_contains_port PORTS PORT
hy2_hop_contains_port() {
  local ports="$1" target="$((10#$2))" item s e
  local -a items=()
  [[ -n "$ports" ]] || return 1
  IFS=',' read -r -a items <<<"$ports"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      s=$((10#${item%-*}))
      e=$((10#${item#*-}))
      ((target >= s && target <= e)) && return 0
    else
      ((target == 10#$item)) && return 0
    fi
  done
  return 1
}

# hy2_hop_redirect_ranges PORTS LISTEN_PORT: prints one NAT rule port token
# ("START-END" or "PORT") per line, omitting LISTEN_PORT itself if included.
hy2_hop_redirect_ranges() {
  local ports="$1" listen_port="${2:-}" item s e
  local -a items=()
  [[ -n "$ports" ]] || return 0
  IFS=',' read -r -a items <<<"$ports"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      s=$((10#${item%-*}))
      e=$((10#${item#*-}))
    else
      s=$((10#$item))
      e="$s"
    fi
    if [[ -n "$listen_port" ]] && ((listen_port >= s && listen_port <= e)); then
      if ((s < listen_port)); then
        if ((s == listen_port - 1)); then
          printf '%d\n' "$s"
        else
          printf '%d-%d\n' "$s" "$((listen_port - 1))"
        fi
      fi
      if ((listen_port < e)); then
        if ((listen_port + 1 == e)); then
          printf '%d\n' "$e"
        else
          printf '%d-%d\n' "$((listen_port + 1))" "$e"
        fi
      fi
    else
      if ((s == e)); then
        printf '%d\n' "$s"
      else
        printf '%d-%d\n' "$s" "$e"
      fi
    fi
  done
}

# hy2_hop_port_conflicts PORTS OWN_PROCS...: prints "PORT/udp (OWNER)" lines or
# returns 1 when no foreign UDP listener overlaps the hop port set.
hy2_hop_port_conflicts() {
  local ports="$1" port owner
  local -a conflicts=()
  shift
  [[ -n "$ports" ]] || return 1
  while read -r port owner; do
    [[ -n "$port" ]] || continue
    if hy2_hop_contains_port "$ports" "$port"; then
      if [[ "$owner" == "?" ]] || ! in_list "$owner" "$@"; then
        in_list "$port/udp ($owner)" "${conflicts[@]}" || conflicts+=("$port/udp ($owner)")
      fi
    fi
  done < <(udp_listening_ports)
  ((${#conflicts[@]} > 0)) || return 1
  printf '%s' "${conflicts[*]}"
}

hy2_hop_detect_backend() {
  local forced="${TOASTBOX_HY2_HOP_BACKEND:-}"
  if [[ -n "$forced" ]]; then
    case "$forced" in
      nftables | nft)
        printf 'nftables'
        return 0
        ;;
      iptables | ipt)
        printf 'iptables'
        return 0
        ;;
      *) return 1 ;;
    esac
  fi
  if has_cmd nft; then
    printf 'nftables'
  elif has_cmd iptables; then
    printf 'iptables'
  else
    return 1
  fi
}

hy2_hop_families() {
  local listen="$1"
  HY2_HOP_V4=0
  HY2_HOP_V6=0
  if [[ -z "$listen" || "$listen" == "::" ]]; then
    HY2_HOP_V4=1
    if ipv6_enabled; then
      HY2_HOP_V6=1
    fi
  elif valid_ipv4 "$listen"; then
    HY2_HOP_V4=1
  elif valid_ipv6 "$listen"; then
    HY2_HOP_V6=1
  fi
  return 0
}

hy2_hop_is_loopback() {
  local addr="${1#[}"
  addr="${addr%]}"
  [[ "$addr" == 127.* || "$addr" == "::1" ]]
}

hy2_hop_validate_saved() {
  local ports="$1" min="$2" max="$3"
  [[ -n "$ports" ]] || return 0
  [[ "$ports" == "$(norm_hy2_hop_ports "$ports" 2>/dev/null || true)" ]] || return 1
  min="$(norm_socket_int "$min" 2147483647 2>/dev/null)" || return 1
  max="$(norm_socket_int "$max" 2147483647 2>/dev/null)" || return 1
  ((min >= 5 && min <= max))
}

hy2_hop_check_tools() {
  case "$1" in
    nftables)
      has_cmd nft || die err_hy2_hop_no_cmd nft
      ;;
    iptables)
      if [[ "$HY2_HOP_V4" == "1" ]]; then
        has_cmd iptables || die err_hy2_hop_no_cmd iptables
      fi
      if [[ "$HY2_HOP_V6" == "1" ]]; then
        has_cmd ip6tables || die err_hy2_hop_no_cmd ip6tables
      fi
      ;;
  esac
}

hy2_hop_preflight() {
  [[ "$CFG_HY2" == "1" && -n "$CFG_HY2_HOP_PORTS" ]] || return 0
  hy2_hop_is_loopback "$CFG_LISTEN" && die err_hy2_hop_loopback "$CFG_LISTEN"
  hy2_hop_families "$CFG_LISTEN"
  HY2_HOP_BACKEND="$(hy2_hop_detect_backend)" || die err_hy2_hop_no_backend
  hy2_hop_check_tools "$HY2_HOP_BACKEND"
}

hy2_hop_render_json() {
  local -a redirects=()
  local r
  hy2_hop_families "$CFG_LISTEN"
  HY2_HOP_BACKEND="${HY2_HOP_BACKEND:-$(hy2_hop_detect_backend)}"
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(hy2_hop_redirect_ranges "$CFG_HY2_HOP_PORTS" "$CFG_HY2_PORT")

  jq -n \
    --arg backend "$HY2_HOP_BACKEND" \
    --arg listen "$CFG_LISTEN" \
    --arg port "$CFG_HY2_PORT" \
    --arg ports "$CFG_HY2_HOP_PORTS" \
    --arg ipv4 "$HY2_HOP_V4" \
    --arg ipv6 "$HY2_HOP_V6" \
    --args '
    {
      schema: 1,
      backend: $backend,
      listen: $listen,
      port: ($port | tonumber),
      ports: $ports,
      redirects: $ARGS.positional,
      ipv4: ($ipv4 == "1"),
      ipv6: ($ipv6 == "1")
    }' "${redirects[@]}"
}

# ---------------------------------------------------------------------------
# Self-contained NAT apply/remove functions embedded into TB_HY2_HOP_HELPER.
# They rely solely on arguments, jq, and nft/iptables/ip6tables so systemd can
# invoke the helper cleanly after boot without needing the ToastBox source tree.
# ---------------------------------------------------------------------------

_hy2_hop_remove_nft() {
  command -v nft >/dev/null 2>&1 || return 0
  if nft list table ip toastbox_hy2 >/dev/null 2>&1; then
    nft delete table ip toastbox_hy2 || return 1
  fi
  if nft list table ip6 toastbox_hy2 >/dev/null 2>&1; then
    nft delete table ip6 toastbox_hy2 || return 1
  fi
}

_hy2_hop_remove_ipt_bin() {
  local bin="$1" num
  command -v "$bin" >/dev/null 2>&1 || return 0
  while IFS= read -r num; do
    [[ -n "$num" ]] || continue
    "$bin" -w -t nat -D PREROUTING "$num" || return 1
  done < <("$bin" -w -t nat -L PREROUTING -n --line-numbers 2>/dev/null |
    awk '$2 == "TOASTBOX-HY2" {print $1}' | sort -rn)
  if "$bin" -w -t nat -L TOASTBOX-HY2 -n >/dev/null 2>&1; then
    "$bin" -w -t nat -F TOASTBOX-HY2 || return 1
    "$bin" -w -t nat -X TOASTBOX-HY2 || return 1
  fi
}

_hy2_hop_remove_ipt() {
  local rc=0
  _hy2_hop_remove_ipt_bin iptables || rc=1
  _hy2_hop_remove_ipt_bin ip6tables || rc=1
  return "$rc"
}

_hy2_hop_remove_all() {
  local rc=0
  _hy2_hop_remove_nft || rc=1
  _hy2_hop_remove_ipt || rc=1
  return "$rc"
}

_hy2_hop_apply_nft() {
  local json_file="$1" listen port ipv4 ipv6 r script=""
  local -a redirects=()
  listen="$(jq -r '.listen // ""' "$json_file")" || return 1
  port="$(jq -r '.port' "$json_file")" || return 1
  ipv4="$(jq -r 'if .ipv4 then "1" else "0" end' "$json_file")" || return 1
  ipv6="$(jq -r 'if .ipv6 then "1" else "0" end' "$json_file")" || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(jq -r '.redirects[]' "$json_file") || return 1
  ((${#redirects[@]} > 0)) || return 1

  command -v nft >/dev/null 2>&1 || {
    echo "nft command not found" >&2
    return 1
  }

  if nft list table ip toastbox_hy2 >/dev/null 2>&1; then
    script+="delete table ip toastbox_hy2"$'\n'
  fi
  if nft list table ip6 toastbox_hy2 >/dev/null 2>&1; then
    script+="delete table ip6 toastbox_hy2"$'\n'
  fi

  if [[ "$ipv4" == "1" ]]; then
    script+="add table ip toastbox_hy2"$'\n'
    script+="add chain ip toastbox_hy2 prerouting { type nat hook prerouting priority -100; policy accept; }"$'\n'
    for r in "${redirects[@]}"; do
      if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
        script+="add rule ip toastbox_hy2 prerouting fib daddr type local udp dport $r redirect to :$port"$'\n'
      else
        script+="add rule ip toastbox_hy2 prerouting ip daddr $listen udp dport $r dnat to $listen:$port"$'\n'
      fi
    done
  fi

  if [[ "$ipv6" == "1" ]]; then
    script+="add table ip6 toastbox_hy2"$'\n'
    script+="add chain ip6 toastbox_hy2 prerouting { type nat hook prerouting priority -100; policy accept; }"$'\n'
    for r in "${redirects[@]}"; do
      if [[ -z "$listen" || "$listen" == "::" ]]; then
        script+="add rule ip6 toastbox_hy2 prerouting fib daddr type local udp dport $r redirect to :$port"$'\n'
      else
        script+="add rule ip6 toastbox_hy2 prerouting ip6 daddr $listen udp dport $r dnat to [$listen]:$port"$'\n'
      fi
    done
  fi

  nft -f - <<<"$script" || return 1
  _hy2_hop_remove_ipt || true
}

_hy2_hop_apply_ipt_family() {
  local bin="$1" family="$2" listen="$3" port="$4" r ipt_r
  shift 4
  local -a redirects=("$@")
  command -v "$bin" >/dev/null 2>&1 || {
    echo "$bin command not found" >&2
    return 1
  }

  _hy2_hop_remove_ipt_bin "$bin" || return 1
  "$bin" -w -t nat -N TOASTBOX-HY2 || return 1
  if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j REDIRECT --to-ports "$port" || return 1
  elif [[ "$family" == "ip6" ]]; then
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j DNAT --to-destination "[$listen]:$port" || return 1
  else
    "$bin" -w -t nat -A TOASTBOX-HY2 -p udp -j DNAT --to-destination "$listen:$port" || return 1
  fi

  for r in "${redirects[@]}"; do
    ipt_r="${r//-/:}"
    if [[ -z "$listen" || "$listen" == "::" || "$listen" == "0.0.0.0" ]]; then
      "$bin" -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p udp --dport "$ipt_r" -j TOASTBOX-HY2 || return 1
    else
      "$bin" -w -t nat -A PREROUTING -d "$listen" -p udp --dport "$ipt_r" -j TOASTBOX-HY2 || return 1
    fi
  done
}

_hy2_hop_apply_ipt() {
  local json_file="$1" listen port ipv4 ipv6 r
  local -a redirects=()
  listen="$(jq -r '.listen // ""' "$json_file")" || return 1
  port="$(jq -r '.port' "$json_file")" || return 1
  ipv4="$(jq -r 'if .ipv4 then "1" else "0" end' "$json_file")" || return 1
  ipv6="$(jq -r 'if .ipv6 then "1" else "0" end' "$json_file")" || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] && redirects+=("$r")
  done < <(jq -r '.redirects[]' "$json_file") || return 1
  ((${#redirects[@]} > 0)) || return 1

  if [[ "$ipv4" == "1" ]]; then
    if ! _hy2_hop_apply_ipt_family iptables ip "$listen" "$port" "${redirects[@]}"; then
      _hy2_hop_remove_ipt || true
      return 1
    fi
  else
    _hy2_hop_remove_ipt_bin iptables || true
  fi

  if [[ "$ipv6" == "1" ]]; then
    if ! _hy2_hop_apply_ipt_family ip6tables ip6 "$listen" "$port" "${redirects[@]}"; then
      _hy2_hop_remove_ipt || true
      return 1
    fi
  else
    _hy2_hop_remove_ipt_bin ip6tables || true
  fi

  _hy2_hop_remove_nft || true
}

_hy2_hop_helper_main() {
  local action="${1:-}" json_file="${2:-/etc/toastbox/hy2-hop.json}" backend
  case "$action" in
    apply)
      [[ -f "$json_file" ]] || {
        echo "missing hop state file: $json_file" >&2
        return 1
      }
      backend="$(jq -r '.backend // ""' "$json_file")" || return 1
      case "$backend" in
        nftables) _hy2_hop_apply_nft "$json_file" ;;
        iptables) _hy2_hop_apply_ipt "$json_file" ;;
        *)
          echo "unsupported hop backend: $backend" >&2
          return 1
          ;;
      esac
      ;;
    remove)
      _hy2_hop_remove_all
      ;;
    *)
      echo "usage: toastbox-hy2-hop apply|remove [FILE]" >&2
      return 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Installer / systemd integration
# ---------------------------------------------------------------------------

hy2_hop_write_helper() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-hy2-hop.XXXXXX")" || return 1
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '# Managed by ToastBox (hy2-hop-helper)\n\n'
    declare -f \
      _hy2_hop_remove_nft \
      _hy2_hop_remove_ipt_bin \
      _hy2_hop_remove_ipt \
      _hy2_hop_remove_all \
      _hy2_hop_apply_nft \
      _hy2_hop_apply_ipt_family \
      _hy2_hop_apply_ipt \
      _hy2_hop_helper_main
    printf '\n_hy2_hop_helper_main "$@"\n'
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$dest"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

hy2_hop_render_service() {
  local core_svc="$1"
  cat <<EOF
# Managed by ToastBox (hy2-hop)
[Unit]
Description=ToastBox Hysteria 2 UDP port hopping NAT rules
After=network-pre.target network.target ufw.service nftables.service netfilter-persistent.service
Before=${core_svc}.service
PartOf=${core_svc}.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$TB_HY2_HOP_HELPER apply $TB_HY2_HOP_STATE
ExecStop=$TB_HY2_HOP_HELPER remove
EOF
}

hy2_hop_render_dropin() {
  cat <<EOF
# Managed by ToastBox (hy2-hop)
[Unit]
Requires=$TB_HY2_HOP_SERVICE
After=$TB_HY2_HOP_SERVICE
EOF
}

hy2_hop_dropin_path() {
  printf '%s/%s.service.d/toastbox-hy2-hop.conf' "$TB_SYSTEMD_DIR" "$1"
}

hy2_hop_unit_path() {
  printf '%s/%s' "$TB_SYSTEMD_DIR" "$TB_HY2_HOP_SERVICE"
}

hy2_hop_write_file() {
  local mode="$1" dest="$2" dir tmp
  dir="$(dirname "$dest")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.tb.XXXXXX")" || return 1
  if ! cat >"$tmp" ||
    ! install_owned "$mode" root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$dest"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

hy2_hop_apply_rules() {
  _hy2_hop_helper_main apply "$1"
}

hy2_hop_remove_rules() {
  _hy2_hop_helper_main remove
}

hy2_hop_backup() {
  local dir="$1" svc file
  install -d -m 700 "$dir" || return 1
  [[ -f "$TB_HY2_HOP_STATE" ]] && cp -p "$TB_HY2_HOP_STATE" "$dir/hy2-hop.json"
  [[ -f "$TB_HY2_HOP_HELPER" ]] && cp -p "$TB_HY2_HOP_HELPER" "$dir/helper"
  file="$(hy2_hop_unit_path)"
  [[ -f "$file" ]] && cp -p "$file" "$dir/service"
  for svc in xray sing-box; do
    file="$(hy2_hop_dropin_path "$svc")"
    [[ -f "$file" ]] && cp -p "$file" "$dir/dropin-$svc"
  done
  return 0
}

hy2_hop_remove_dropins() {
  local svc file
  for svc in xray sing-box; do
    file="$(hy2_hop_dropin_path "$svc")"
    rm -f "$file"
    rmdir "$(dirname "$file")" 2>/dev/null || true
  done
}

hy2_hop_remove_files() {
  rm -f "$(hy2_hop_unit_path)"
  hy2_hop_remove_dropins
  rm -f "$TB_HY2_HOP_HELPER" "$TB_HY2_HOP_STATE"
}

hy2_hop_systemd_reload() {
  systemd_running || return 0
  systemctl daemon-reload >/dev/null 2>&1 || true
}

hy2_hop_systemd_stop_unit() {
  systemd_running || return 0
  systemctl stop "$TB_HY2_HOP_SERVICE" >/dev/null 2>&1 || true
}

hy2_hop_install_state() {
  local core_svc="$1" json_src="$2" other_svc="sing-box" dropin old_dropin
  [[ "$core_svc" == "sing-box" ]] && other_svc="xray"

  install -d -m 700 "$TB_STATE_DIR" || return 1
  install_owned 600 root root "$json_src" "$TB_HY2_HOP_STATE" || return 1
  hy2_hop_write_helper "$TB_HY2_HOP_HELPER" || return 1
  hy2_hop_render_service "$core_svc" | hy2_hop_write_file 644 "$(hy2_hop_unit_path)" || return 1

  dropin="$(hy2_hop_dropin_path "$core_svc")"
  hy2_hop_render_dropin | hy2_hop_write_file 644 "$dropin" || return 1

  old_dropin="$(hy2_hop_dropin_path "$other_svc")"
  rm -f "$old_dropin"
  rmdir "$(dirname "$old_dropin")" 2>/dev/null || true

  hy2_hop_systemd_reload
}

hy2_hop_disable() {
  hy2_hop_remove_dropins
  hy2_hop_systemd_reload
  hy2_hop_systemd_stop_unit
  hy2_hop_remove_rules || true
  hy2_hop_remove_files
  hy2_hop_systemd_reload
}

hy2_hop_restore() {
  local dir="$1" svc file dropin active_svc=""
  hy2_hop_remove_dropins
  hy2_hop_systemd_reload
  hy2_hop_systemd_stop_unit
  hy2_hop_remove_rules || true
  hy2_hop_remove_files

  if [[ -f "$dir/hy2-hop.json" ]]; then
    install -d -m 700 "$TB_STATE_DIR" || true
    install_owned 600 root root "$dir/hy2-hop.json" "$TB_HY2_HOP_STATE" || true
  fi
  if [[ -f "$dir/helper" ]]; then
    install -d -m 755 "$(dirname "$TB_HY2_HOP_HELPER")" || true
    install_owned 755 root root "$dir/helper" "$TB_HY2_HOP_HELPER" || true
  fi
  if [[ -f "$dir/service" ]]; then
    file="$(hy2_hop_unit_path)"
    install -d -m 755 "$(dirname "$file")" || true
    install_owned 644 root root "$dir/service" "$file" || true
  fi
  for svc in xray sing-box; do
    if [[ -f "$dir/dropin-$svc" ]]; then
      active_svc="$svc"
      dropin="$(hy2_hop_dropin_path "$svc")"
      install -d -m 755 "$(dirname "$dropin")" || true
      install_owned 644 root root "$dir/dropin-$svc" "$dropin" || true
    fi
  done
  hy2_hop_systemd_reload
  if [[ -f "$TB_HY2_HOP_STATE" ]]; then
    hy2_hop_apply_rules "$TB_HY2_HOP_STATE" || true
    if [[ -n "$active_svc" ]] && systemd_running && service_is_active "$active_svc"; then
      systemctl start "$TB_HY2_HOP_SERVICE" >/dev/null 2>&1 || true
    fi
  fi
}
