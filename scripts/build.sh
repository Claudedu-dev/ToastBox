#!/usr/bin/env bash
#
# Bundles src/main.sh and src/lib/*.sh into the single-file release.
#
#   scripts/build.sh           write ./toastbox.sh
#   scripts/build.sh --check   fail if ./toastbox.sh is out of date
#   scripts/build.sh FILE      write FILE instead

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main="$root/src/main.sh"
target="$root/toastbox.sh"
check=0

case "${1:-}" in
  --check) check=1 ;;
  "") ;;
  *) target="$1" ;;
esac

bundle() {
  cat <<'EOF'
#!/usr/bin/env bash
#
# ToastBox - deploy VLESS-TCP-REALITY-Vision and Shadowsocks-2022 nodes
# with Xray or sing-box on Debian / Ubuntu.
#
# https://github.com/Claudedu-dev/ToastBox
#
# GENERATED FILE - DO NOT EDIT.
# Built from src/ by scripts/build.sh; change the sources and rebuild.

EOF
  # The part of main.sh between its header comment and the module loader.
  awk '
    /^# @build:begin-loader/ { exit }
    started { print }
    /^set -euo pipefail/ { started = 1; print }
  ' "$main"

  printf 'TB_BUILT=1\n'
  local lib
  for lib in "$root"/src/lib/*.sh; do
    printf '\n# ===== src/lib/%s =====\n' "$(basename "$lib")"
    # The shell directive only matters for the standalone module.
    grep -v '^# shellcheck shell=bash$' "$lib"
  done
  printf '\n# ===== src/main.sh =====\n'

  awk '
    after { print }
    /^# @build:end-loader/ { after = 1 }
  ' "$main"
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
bundle >"$tmp"
bash -n "$tmp"

if [[ "$check" == "1" ]]; then
  if ! diff -u "$target" "$tmp" >&2; then
    echo "toastbox.sh is out of date: run scripts/build.sh and commit the result." >&2
    exit 1
  fi
  echo "toastbox.sh is up to date."
else
  install -m 755 "$tmp" "$target"
  echo "Wrote $target ($(wc -l <"$target") lines)."
fi
