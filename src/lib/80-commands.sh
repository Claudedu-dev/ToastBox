# shellcheck shell=bash
#
# Command line parsing, parameter resolution and the commands themselves.

# ---------------------------------------------------------------------------
# Core dispatch
# ---------------------------------------------------------------------------

# core_fn CORE OPERATION [ARGS...] -> xray_OPERATION / singbox_OPERATION
core_fn() {
  local core="$1" op="$2"
  shift 2
  case "$core" in
    xray) "xray_$op" "$@" ;;
    sing-box) "singbox_$op" "$@" ;;
    *) die err_core "$core" ;;
  esac
}

core_call() { core_fn "$CFG_CORE" "$@"; }

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

opt_reset() {
  OPT_COMMAND=""
  OPT_CORE=""
  OPT_PROTOCOLS=""
  OPT_SERVER_ADDR=""
  OPT_NAME=""
  OPT_LISTEN=""
  OPT_VLESS_PORT=""
  OPT_REALITY_SNI=""
  OPT_REALITY_TARGET=""
  OPT_SKIP_TARGET_CHECK=0
  OPT_SS_PORT=""
  OPT_SS_METHOD=""
  OPT_SS_NETWORK=""
  OPT_BLOCK_BT=""
  OPT_ALLOW_PRIVATE=""
  OPT_CORE_VERSION=""
  OPT_NO_FIREWALL=0
  OPT_FORMAT=""
  OPT_QR=0
  OPT_PURGE=0
  # shellcheck disable=SC2034  # consumed by parse_args, read by tb_init_lang
  OPT_LANG=""
  OPT_YES=0
}

parse_args() {
  local arg var
  while (($# > 0)); do
    arg="$1"
    shift
    # --option=value -> --option value
    if [[ "$arg" == --*=* ]]; then
      set -- "${arg#*=}" "$@"
      arg="${arg%%=*}"
    fi

    var=""
    case "$arg" in
      --core) var=OPT_CORE ;;
      --protocols | --protocol) var=OPT_PROTOCOLS ;;
      --server-addr) var=OPT_SERVER_ADDR ;;
      --name) var=OPT_NAME ;;
      --listen) var=OPT_LISTEN ;;
      --vless-port) var=OPT_VLESS_PORT ;;
      --reality-sni) var=OPT_REALITY_SNI ;;
      --reality-target) var=OPT_REALITY_TARGET ;;
      --ss-port) var=OPT_SS_PORT ;;
      --ss-method) var=OPT_SS_METHOD ;;
      --ss-network) var=OPT_SS_NETWORK ;;
      --core-version) var=OPT_CORE_VERSION ;;
      --format) var=OPT_FORMAT ;;
      # Already handled by tb_init_lang; parsed here only to consume it.
      --lang) var=OPT_LANG ;;
    esac
    if [[ -n "$var" ]]; then
      (($# > 0)) || die err_missing_value "$arg"
      printf -v "$var" '%s' "$1"
      shift
      continue
    fi

    case "$arg" in
      install | show | update | rotate | uninstall | menu | help | version)
        [[ -z "$OPT_COMMAND" ]] || die err_unknown_arg "$arg"
        OPT_COMMAND="$arg"
        ;;
      -h | --help) OPT_COMMAND="help" ;;
      -V | --version) OPT_COMMAND="version" ;;
      -y | --yes) OPT_YES=1 ;;
      --skip-target-check) OPT_SKIP_TARGET_CHECK=1 ;;
      --block-bt) OPT_BLOCK_BT=1 ;;
      --no-block-bt) OPT_BLOCK_BT=0 ;;
      --allow-private) OPT_ALLOW_PRIVATE=1 ;;
      --no-allow-private) OPT_ALLOW_PRIVATE=0 ;;
      --no-firewall) OPT_NO_FIREWALL=1 ;;
      --qr) OPT_QR=1 ;;
      --purge) OPT_PURGE=1 ;;
      *) die err_unknown_arg "$arg" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Normalizers: print the canonical form of a value, fail when it is invalid.
# They double as validators for both flags and interactive answers.
# ---------------------------------------------------------------------------

norm_core() {
  case "$1" in
    1 | xray | Xray) printf 'xray' ;;
    2 | sing-box | singbox) printf 'sing-box' ;;
    *) return 1 ;;
  esac
}

PARSED_VLESS=0
PARSED_SS=0

# parse_protocols "vless,ss": result in PARSED_VLESS / PARSED_SS.
parse_protocols() {
  local item
  local -a items=()
  PARSED_VLESS=0
  PARSED_SS=0
  IFS=',+ ' read -r -a items <<<"$1"
  ((${#items[@]} > 0)) || return 1
  for item in "${items[@]}"; do
    case "$item" in
      1 | all | both) PARSED_VLESS=1 PARSED_SS=1 ;;
      2 | vless | reality | vless-reality) PARSED_VLESS=1 ;;
      3 | ss | ss2022 | shadowsocks | shadowsocks-2022) PARSED_SS=1 ;;
      *) return 1 ;;
    esac
  done
}

norm_protocols() {
  local -a out=()
  parse_protocols "$1" || return 1
  [[ "$PARSED_VLESS" == "1" ]] && out+=(vless)
  [[ "$PARSED_SS" == "1" ]] && out+=(ss)
  join_by , "${out[@]}"
}

norm_port() {
  valid_port "$1" && printf '%d' "$((10#$1))"
}

norm_domain() {
  valid_domain "$1" && printf '%s' "${1,,}"
}

norm_host() {
  local host="$1"
  host="${host#[}"
  host="${host%]}"
  valid_host "$host" && printf '%s' "$host"
}

norm_host_port() {
  valid_host_port "$1" && printf '%s' "$1"
}

norm_listen() {
  local addr="$1"
  addr="${addr#[}"
  addr="${addr%]}"
  { valid_ipv4 "$addr" || valid_ipv6 "$addr" || [[ "$addr" == "::" ]]; } && printf '%s' "$addr"
}

norm_ss_method() {
  case "$1" in
    1) printf '%s' "${TB_SS_METHODS[0]}" ;;
    2) printf '%s' "${TB_SS_METHODS[1]}" ;;
    3) printf '%s' "${TB_SS_METHODS[2]}" ;;
    *) valid_ss_method "$1" && printf '%s' "$1" ;;
  esac
}

norm_ss_network() {
  case "$1" in
    both | tcp,udp | udp,tcp | all) printf 'both' ;;
    tcp | udp) printf '%s' "$1" ;;
    *) return 1 ;;
  esac
}

norm_format() {
  case "$1" in
    text | json | links | xray) printf '%s' "$1" ;;
    sing-box | singbox) printf 'sing-box' ;;
    *) return 1 ;;
  esac
}

norm_version() {
  [[ "$1" =~ ^v?[0-9]+(\.[0-9]+){1,2}([-~][0-9A-Za-z.]+)?$ ]] && printf '%s' "${1#v}"
}

norm_name() {
  [[ -n "$1" && ${#1} -le 64 && "$1" != *$'\n'* ]] && printf '%s' "$1"
}

# normalize_opt VAR NORMALIZER FLAG: canonicalizes a flag value in place.
normalize_opt() {
  local var="$1" normalizer="$2" flag="$3" value
  [[ -n "${!var}" ]] || return 0
  value="$("$normalizer" "${!var}")" || die err_invalid_option "$flag" "${!var}"
  printf -v "$var" '%s' "$value"
}

validate_options() {
  normalize_opt OPT_CORE norm_core --core
  normalize_opt OPT_PROTOCOLS norm_protocols --protocols
  normalize_opt OPT_SERVER_ADDR norm_host --server-addr
  normalize_opt OPT_NAME norm_name --name
  normalize_opt OPT_LISTEN norm_listen --listen
  normalize_opt OPT_VLESS_PORT norm_port --vless-port
  normalize_opt OPT_REALITY_SNI norm_domain --reality-sni
  normalize_opt OPT_REALITY_TARGET norm_host_port --reality-target
  normalize_opt OPT_SS_PORT norm_port --ss-port
  normalize_opt OPT_SS_METHOD norm_ss_method --ss-method
  normalize_opt OPT_SS_NETWORK norm_ss_network --ss-network
  normalize_opt OPT_CORE_VERSION norm_version --core-version
  normalize_opt OPT_FORMAT norm_format --format
}

# ask_valid VAR DEFAULT NORMALIZER MSG_KEY [ARGS...]
# Prompts until NORMALIZER accepts the answer. Without a terminal the
# default is used as-is and must already be valid.
ask_valid() {
  local var="$1" default="$2" normalizer="$3" reply value
  shift 3
  while :; do
    reply="$(ask "$default" "$@")"
    if value="$("$normalizer" "$reply")"; then
      printf -v "$var" '%s' "$value"
      return 0
    fi
    [[ "$TB_INTERACTIVE" == "1" ]] || die err_invalid_value "$reply"
    log_warn warn_invalid_input "$reply"
  done
}

# ---------------------------------------------------------------------------
# Parameter resolution for `install`
# Precedence: command line flag > interactive answer > saved state > default.
# ---------------------------------------------------------------------------

resolve_core() {
  if [[ -n "$OPT_CORE" ]]; then
    CFG_CORE="$OPT_CORE"
  else
    ask_valid CFG_CORE "${CFG_CORE:-xray}" norm_core prompt_core
  fi
}

resolve_protocols() {
  local current="vless,ss" chosen
  if [[ "$TB_HAS_STATE" == "1" ]]; then
    case "$CFG_VLESS$CFG_SS" in
      10) current="vless" ;;
      01) current="ss" ;;
    esac
  fi
  if [[ -n "$OPT_PROTOCOLS" ]]; then
    chosen="$OPT_PROTOCOLS"
  else
    ask_valid chosen "$current" norm_protocols prompt_protocols
  fi
  parse_protocols "$chosen"
  CFG_VLESS="$PARSED_VLESS"
  CFG_SS="$PARSED_SS"
}

resolve_server_addr() {
  local default="$CFG_SERVER_ADDR"
  if [[ -n "$OPT_SERVER_ADDR" ]]; then
    CFG_SERVER_ADDR="$OPT_SERVER_ADDR"
    return 0
  fi
  if [[ -z "$default" ]]; then
    log_info info_detect_addr
    default="$(detect_server_addr || true)"
  fi
  if [[ "$TB_INTERACTIVE" != "1" && -z "$default" ]]; then
    die err_server_addr_required
  fi
  ask_valid CFG_SERVER_ADDR "$default" norm_host prompt_server_addr
}

# Runs the target probe and reports the outcome. Returns 0 when the target
# is fine or the user decided to keep it.
accept_reality_target() {
  local sni="$1" target="$2" rc=0
  if [[ "$OPT_SKIP_TARGET_CHECK" == "1" ]]; then
    return 0
  fi
  log_info info_probing_target "$target" "$sni"
  probe_reality_target "$sni" "$target" || rc=$?
  case "$rc" in
    0)
      [[ "$TB_TARGET_H2" == "1" ]] || log_warn warn_target_no_h2 "$target"
      log_ok ok_target "$target"
      return 0
      ;;
    1) log_err err_target_unreachable "$target" ;;
    2) log_err err_target_no_tls13 "$target" ;;
    *) log_err err_target_cert "$target" "$sni" ;;
  esac
  # --yes must not wave a broken target through: that needs the explicit
  # --skip-target-check.
  [[ "$TB_INTERACTIVE" == "1" ]] && confirm n prompt_target_anyway
}

resolve_vless() {
  local sni target old_sni="$CFG_REALITY_SNI" old_target="$CFG_REALITY_TARGET"

  if [[ -n "$OPT_VLESS_PORT" ]]; then
    CFG_VLESS_PORT="$OPT_VLESS_PORT"
  else
    ask_valid CFG_VLESS_PORT "${CFG_VLESS_PORT:-443}" norm_port prompt_vless_port
  fi

  if [[ "$TB_INTERACTIVE" == "1" && -z "$OPT_REALITY_SNI" ]]; then
    printf '%s\n' "$(msg help_reality_sni)" >&2
  fi
  while :; do
    if [[ -n "$OPT_REALITY_SNI" ]]; then
      sni="$OPT_REALITY_SNI"
    else
      [[ "$TB_INTERACTIVE" == "1" || -n "$old_sni" ]] || die err_sni_required
      ask_valid sni "$old_sni" norm_domain prompt_reality_sni
    fi

    if [[ -n "$OPT_REALITY_TARGET" ]]; then
      target="$OPT_REALITY_TARGET"
    elif [[ "$sni" == "$old_sni" && -n "$old_target" ]]; then
      target="$old_target"
    else
      target="$sni:443"
    fi

    if accept_reality_target "$sni" "$target"; then
      break
    fi
    # Only an interactively typed name can be corrected by asking again.
    [[ "$TB_INTERACTIVE" == "1" && -z "$OPT_REALITY_SNI" ]] || die err_target_rejected
  done
  CFG_REALITY_SNI="$sni"
  CFG_REALITY_TARGET="$target"
}

resolve_ss() {
  local default_port="$CFG_SS_PORT"
  if [[ -n "$OPT_SS_PORT" ]]; then
    CFG_SS_PORT="$OPT_SS_PORT"
  else
    if [[ -z "$default_port" ]]; then
      default_port="$(random_free_port)" || die err_no_free_port
    fi
    ask_valid CFG_SS_PORT "$default_port" norm_port prompt_ss_port
  fi

  if [[ -n "$OPT_SS_METHOD" ]]; then
    CFG_SS_METHOD="$OPT_SS_METHOD"
  else
    ask_valid CFG_SS_METHOD "${CFG_SS_METHOD:-${TB_SS_METHODS[0]}}" norm_ss_method prompt_ss_method
  fi

  if [[ -n "$OPT_SS_NETWORK" ]]; then
    CFG_SS_NETWORK="$OPT_SS_NETWORK"
  elif [[ -z "$CFG_SS_NETWORK" ]]; then
    CFG_SS_NETWORK="both"
  fi
}

resolve_params() {
  resolve_core
  resolve_protocols
  resolve_server_addr

  [[ -n "$OPT_NAME" ]] && CFG_NODE_NAME="$OPT_NAME"
  [[ -n "$CFG_NODE_NAME" ]] || CFG_NODE_NAME="ToastBox"
  [[ -n "$OPT_LISTEN" ]] && CFG_LISTEN="$OPT_LISTEN"
  [[ -n "$OPT_BLOCK_BT" ]] && CFG_BLOCK_BT="$OPT_BLOCK_BT"
  [[ -n "$OPT_ALLOW_PRIVATE" ]] && CFG_ALLOW_PRIVATE="$OPT_ALLOW_PRIVATE"

  if [[ "$CFG_VLESS" == "1" ]]; then resolve_vless; fi
  if [[ "$CFG_SS" == "1" ]]; then resolve_ss; fi

  if [[ "$CFG_VLESS" == "1" && "$CFG_SS" == "1" &&
    "$CFG_VLESS_PORT" == "$CFG_SS_PORT" && "$CFG_SS_NETWORK" != "udp" ]]; then
    die err_port_same "$CFG_VLESS_PORT"
  fi
  return 0
}

print_plan() {
  printf '\n%s\n' "$(msg plan_title)" >&2
  printf '  %s: %s\n' "$(msg label_core)" "$CFG_CORE" >&2
  printf '  %s: %s\n' "$(msg label_server)" "$CFG_SERVER_ADDR" >&2
  if [[ "$CFG_VLESS" == "1" ]]; then
    printf '  VLESS-REALITY-Vision: %s/tcp, SNI %s, %s %s\n' \
      "$CFG_VLESS_PORT" "$CFG_REALITY_SNI" "$(msg label_target)" "$CFG_REALITY_TARGET" >&2
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    printf '  Shadowsocks 2022: %s (%s), %s\n' \
      "$CFG_SS_PORT" "$CFG_SS_NETWORK" "$CFG_SS_METHOD" >&2
  fi
  printf '\n' >&2
}

# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

preflight_ports() {
  local own procs
  own="$(core_call process)"
  if [[ "$CFG_VLESS" == "1" ]]; then
    if procs="$(port_conflict tcp "$CFG_VLESS_PORT" "$own")"; then
      die err_port_in_use "$CFG_VLESS_PORT/tcp" "$procs"
    fi
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    if [[ "$CFG_SS_NETWORK" != "udp" ]] && procs="$(port_conflict tcp "$CFG_SS_PORT" "$own")"; then
      die err_port_in_use "$CFG_SS_PORT/tcp" "$procs"
    fi
    if [[ "$CFG_SS_NETWORK" != "tcp" ]] && procs="$(port_conflict udp "$CFG_SS_PORT" "$own")"; then
      die err_port_in_use "$CFG_SS_PORT/udp" "$procs"
    fi
  fi
  return 0
}

# ensure_core [force]: installs the core when it is missing, when a specific
# version was requested or when forced (update), then checks that it is
# recent enough for the configuration we write.
ensure_core() {
  local force="${1:-0}" version min
  if [[ "$force" == "1" || -n "$OPT_CORE_VERSION" ]] || ! core_call is_installed; then
    log_info info_installing_core "$CFG_CORE"
    core_call install "$OPT_CORE_VERSION" || die err_core_install "$CFG_CORE"
  fi
  core_call is_installed || die err_core_install "$CFG_CORE"
  version="$(core_call version || true)"
  min="$(core_call min_version)"
  if [[ -z "$version" ]] || ! ver_ge "$version" "$min"; then
    die err_core_too_old "$CFG_CORE" "${version:-?}" "$min"
  fi
  log_ok ok_core_ready "$CFG_CORE" "$version"
}

# Renders, validates, installs and activates the configuration. If the
# service does not come up, the previous configuration is restored.
apply_config() {
  local new="$TB_TMP/config.json" path svc backup="" output
  path="$(core_call config_path)"
  svc="$(core_call service)"

  core_call render >"$new" || die err_render
  if ! output="$(core_call validate "$new" 2>&1)"; then
    printf '%s\n' "$output" >&2
    die err_validate "$CFG_CORE"
  fi

  backup="$(backup_file "$path" "$CFG_CORE-config")"
  core_call install_config "$new"
  log_info info_restarting "$svc"
  if service_restart_checked "$svc"; then
    log_ok ok_service_running "$svc"
    return 0
  fi

  log_err err_service_start "$svc"
  service_show_log "$svc"
  if [[ -n "$backup" ]]; then
    core_call install_config "$backup"
    service_restart_checked "$svc" || true
    log_warn warn_rolled_back "$backup"
  fi
  return 1
}

sync_firewall() {
  local -a rules=()
  if [[ "$OPT_NO_FIREWALL" == "1" ]]; then
    return 0
  fi
  [[ "$CFG_VLESS" == "1" ]] && rules+=("$CFG_VLESS_PORT/tcp")
  if [[ "$CFG_SS" == "1" ]]; then
    [[ "$CFG_SS_NETWORK" != "udp" ]] && rules+=("$CFG_SS_PORT/tcp")
    [[ "$CFG_SS_NETWORK" != "tcp" ]] && rules+=("$CFG_SS_PORT/udp")
  fi
  fw_sync "${rules[@]}"
}

post_install_notes() {
  local extra
  extra="$(core_call extra_configs)"
  if [[ -n "$extra" ]]; then
    log_warn warn_extra_configs "$(printf '%s' "$extra" | tr '\n' ' ')"
  fi
  # Shadowsocks 2022 rejects packets whose timestamp is too far off.
  if [[ "$CFG_SS" == "1" ]] && ! clock_synchronized; then
    log_warn warn_clock
  fi
}

require_state() {
  state_load || die err_no_state
}

# Keeps a copy of the single-file release as `toastbox`, so the node can be
# managed later without downloading the script again. Skipped when running
# from the source tree or from a pipe.
self_install() {
  local src="${BASH_SOURCE[0]:-}"
  [[ "${TB_BUILT:-0}" == "1" && -f "$src" ]] || return 0
  [[ "$(readlink -f "$src")" != "$(readlink -f "$TB_SELF_PATH")" ]] || return 0
  install -m 755 "$src" "$TB_SELF_PATH" && log_ok ok_self_installed "$TB_SELF_PATH"
  return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_install() {
  local prev_core core_preinstalled=0 path

  require_root
  detect_os
  require_supported_arch
  require_systemd
  tb_mktemp_dir
  install_deps

  state_load || true
  prev_core="$CFG_CORE"

  resolve_params
  if [[ "$TB_INTERACTIVE" == "1" ]]; then
    print_plan
    confirm y prompt_proceed || die err_aborted
  fi

  if [[ -n "$prev_core" && "$prev_core" != "$CFG_CORE" ]]; then
    log_warn warn_core_switch "$prev_core" "$CFG_CORE" "$prev_core"
    service_stop_disable "$(core_fn "$prev_core" service)"
  fi

  # A core that was installed by someone else may carry a configuration
  # worth keeping: ask before replacing it. (A backup is made either way.)
  core_call is_installed && core_preinstalled=1
  path="$(core_call config_path)"
  if [[ "$core_preinstalled" == "1" && "$prev_core" != "$CFG_CORE" && -s "$path" ]] &&
    [[ "$(tr -d '[:space:]' <"$path")" != "{}" ]]; then
    confirm n prompt_overwrite_config "$path" || die err_foreign_config "$path"
  fi

  preflight_ports
  ensure_core
  ensure_credentials
  apply_config || die err_apply
  sync_firewall
  state_save
  self_install
  log_ok ok_installed
  post_install_notes

  OPT_FORMAT="text"
  OPT_PROTOCOLS=""
  show_node
}

cmd_show() {
  require_root
  require_state
  show_node
}

cmd_update() {
  require_root
  require_systemd
  tb_mktemp_dir
  require_state

  ensure_core 1
  # Re-render with the current templates and restart on the new binary.
  apply_config || die err_apply
  state_save
  log_ok ok_updated "$CFG_CORE" "$(core_call version || true)"
}

cmd_rotate() {
  require_root
  require_systemd
  tb_mktemp_dir
  require_state
  core_call is_installed || die err_core_install "$CFG_CORE"

  confirm n prompt_rotate || die err_aborted
  clear_credentials
  ensure_credentials
  apply_config || die err_apply
  state_save
  log_ok ok_rotated

  OPT_FORMAT="${OPT_FORMAT:-text}"
  show_node
}

cmd_uninstall() {
  local core
  require_root
  require_systemd
  tb_mktemp_dir
  state_load || true
  core="${OPT_CORE:-$CFG_CORE}"
  [[ -n "$core" ]] || die err_no_state

  if [[ "$OPT_PURGE" == "1" ]]; then
    confirm n prompt_uninstall_purge "$core" || die err_aborted
  else
    confirm n prompt_uninstall "$core" || die err_aborted
  fi

  fw_close_all
  service_stop_disable "$(core_fn "$core" service)"
  if core_fn "$core" is_installed; then
    core_fn "$core" remove "$OPT_PURGE" || log_warn warn_remove_failed "$core"
  fi
  if [[ "$OPT_PURGE" == "1" ]]; then
    rm -rf "$TB_STATE_DIR"
  else
    state_remove
  fi
  rm -f "$TB_SELF_PATH"
  log_ok ok_uninstalled "$core"
}

cmd_menu() {
  local reply
  printf '\n%sToastBox %s%s\n\n' "$TB_C_BOLD" "$TB_VERSION" "$TB_C_RESET" >&2
  printf '%s\n' "$(msg menu_items)" >&2
  reply="$(tb_readline "$(msg prompt_menu): ")"
  case "$reply" in
    1) cmd_install ;;
    2) cmd_show ;;
    3) cmd_update ;;
    4) cmd_rotate ;;
    5) cmd_uninstall ;;
    *) exit 0 ;;
  esac
}

usage() {
  msg usage "$TB_VERSION"
}

tb_main() {
  opt_reset
  tb_init_lang "$@"
  trap tb_cleanup EXIT
  parse_args "$@"
  validate_options
  tb_detect_interactive

  case "$OPT_COMMAND" in
    install) cmd_install ;;
    show) cmd_show ;;
    update) cmd_update ;;
    rotate) cmd_rotate ;;
    uninstall) cmd_uninstall ;;
    help) usage ;;
    version) printf 'ToastBox %s\n' "$TB_VERSION" ;;
    menu | "")
      if [[ "$TB_INTERACTIVE" != "1" ]]; then
        usage >&2
        exit 2
      fi
      tb_choose_lang
      cmd_menu
      ;;
  esac
}
