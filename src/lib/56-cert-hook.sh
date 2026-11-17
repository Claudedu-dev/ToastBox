# shellcheck shell=bash
#
# Certbot deploy hook management for Hysteria 2 imported public certificates.

certbot_live_root() {
  local dir
  if [[ -d "$TB_CERTBOT_LIVE_DIR" ]]; then
    dir="$(tls_abs_path "$TB_CERTBOT_LIVE_DIR" || printf '%s' "${TB_CERTBOT_LIVE_DIR%/}")"
  else
    dir="${TB_CERTBOT_LIVE_DIR%/}"
  fi
  printf '%s' "${dir%/}"
}

# certbot_lineage_from_pair CERT_FILE KEY_FILE: validates that both files point
# to the same standard <live>/<lineage>/(fullchain|privkey).pem pair and prints
# the lineage name.
certbot_lineage_from_pair() {
  local cert_file="$1" key_file="$2" live rest lineage
  live="$(certbot_live_root)"
  [[ -n "$live" && "$cert_file" == "$live/"*"/fullchain.pem" ]] || return 1
  rest="${cert_file#"$live"/}"
  lineage="${rest%/fullchain.pem}"
  [[ -n "$lineage" && "$lineage" != "." && "$lineage" != ".." && "$lineage" != */* ]] || return 1
  [[ "$key_file" == "$live/$lineage/privkey.pem" ]] || return 1
  printf '%s' "$lineage"
}

certbot_hook_is_ours() {
  local path="${1:-$TB_CERTBOT_HOOK_PATH}"
  [[ -f "$path" ]] && grep -qF "$TB_CERTBOT_HOOK_MARKER" "$path"
}

certbot_can_install_entrypoint() {
  [[ -x "$TB_SELF_PATH" ]] && return 0
  [[ "${TB_BUILT:-0}" == "1" && -f "${BASH_SOURCE[0]:-}" ]] && return 0
  [[ -n "${TB_SRC_DIR:-}" && -f "$TB_SRC_DIR/../scripts/build.sh" ]] && return 0
  return 1
}

certbot_build_entrypoint() {
  local dir tmp
  dir="$(dirname "$TB_SELF_PATH")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-self.XXXXXX")" || return 1
  if ! bash "$TB_SRC_DIR/../scripts/build.sh" "$tmp" >/dev/null 2>&1 ||
    ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$TB_SELF_PATH"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
  log_ok ok_self_installed "$TB_SELF_PATH"
}

certbot_ensure_entrypoint() {
  local src="${BASH_SOURCE[0]:-}"
  if [[ "${TB_BUILT:-0}" == "1" && -f "$src" ]]; then
    self_install
    return $?
  fi
  if [[ -n "${TB_SRC_DIR:-}" && -f "$TB_SRC_DIR/../scripts/build.sh" ]]; then
    certbot_build_entrypoint
    return $?
  fi
  [[ -x "$TB_SELF_PATH" ]] && return 0
  return 1
}

certbot_hook_preflight() {
  if [[ -e "$TB_CERTBOT_HOOK_PATH" ]] && ! certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    die err_hy2_foreign_hook "$TB_CERTBOT_HOOK_PATH"
  fi
  certbot_can_install_entrypoint || die err_hy2_hook_needs_self "$TB_SELF_PATH"
}

certbot_hook_render() {
  cat <<EOF
#!/usr/bin/env bash
$TB_CERTBOT_HOOK_MARKER
set -euo pipefail

state_file="\${TOASTBOX_STATE_DIR:-/etc/toastbox}/state.json"
entry="\${TOASTBOX_SELF_PATH:-$TB_SELF_PATH}"
renewed="\${RENEWED_LINEAGE:-}"

[[ -n "\$renewed" ]] || exit 0
[[ -r "\$state_file" ]] || exit 0

eval "\$(jq -r '
  if (.hy2.enabled // false) == true and (.hy2.tls // "") == "files" and (.hy2.certbot_hook // false) == true
  then @sh "cert_file=\(.hy2.cert_file // "")"
  else "cert_file="
  end
' "\$state_file" 2>/dev/null || echo 'cert_file=')"

[[ -n "\${cert_file:-}" ]] || exit 0
expected_lineage="\$(dirname -- "\$cert_file")"
renewed="\${renewed%/}"
expected_lineage="\${expected_lineage%/}"

if [[ "\$renewed" != "\$expected_lineage" ]]; then
  exit 0
fi

if [[ ! -x "\$entry" ]]; then
  echo "ToastBox entrypoint is missing or not executable: \$entry" >&2
  exit 1
fi

exec "\$entry" refresh-cert
EOF
}

certbot_hook_install() {
  local dir tmp
  if [[ -e "$TB_CERTBOT_HOOK_PATH" ]] && ! certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    log_err err_hy2_foreign_hook "$TB_CERTBOT_HOOK_PATH"
    return 1
  fi
  dir="$(dirname "$TB_CERTBOT_HOOK_PATH")"
  install -d -m 755 "$dir" || return 1
  tmp="$(mktemp "$dir/.toastbox-hook.XXXXXX")" || return 1
  if ! certbot_hook_render >"$tmp" ||
    ! install_owned 755 root root "$tmp" "${tmp}.owned" ||
    ! mv -f "${tmp}.owned" "$TB_CERTBOT_HOOK_PATH"; then
    rm -f "$tmp" "${tmp}.owned"
    return 1
  fi
  rm -f "$tmp"
}

certbot_hook_remove() {
  if certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    rm -f "$TB_CERTBOT_HOOK_PATH"
  fi
}

certbot_hook_backup() {
  local dir="$1"
  install -d -m 700 "$dir" || return 1
  if certbot_hook_is_ours "$TB_CERTBOT_HOOK_PATH"; then
    cp -p "$TB_CERTBOT_HOOK_PATH" "$dir/toastbox-hy2.sh"
  fi
}

certbot_hook_restore() {
  local dir="$1" target_dir
  certbot_hook_remove
  if [[ -f "$dir/toastbox-hy2.sh" ]]; then
    target_dir="$(dirname "$TB_CERTBOT_HOOK_PATH")"
    install -d -m 755 "$target_dir" || true
    install_owned 755 root root "$dir/toastbox-hy2.sh" "$TB_CERTBOT_HOOK_PATH" || true
  fi
}
