# Shared setup for the unit tests: loads the modules without running
# tb_main and points every path at a per-test temporary directory.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

load_toastbox() {
  export TOASTBOX_SOURCE_ONLY=1
  export TOASTBOX_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export TOASTBOX_XRAY_BIN="$BATS_TEST_TMPDIR/bin/xray"
  export TOASTBOX_XRAY_CONFIG="$BATS_TEST_TMPDIR/xray/config.json"
  export TOASTBOX_SINGBOX_BIN="$BATS_TEST_TMPDIR/bin/sing-box"
  export TOASTBOX_SINGBOX_CONFIG="$BATS_TEST_TMPDIR/sing-box/config.json"
  export TOASTBOX_SELF_PATH="$BATS_TEST_TMPDIR/bin/toastbox"
  export NO_COLOR=1
  unset TOASTBOX_LANG
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/src/main.sh"
  # Keep errexit (bats relies on it) but drop the rest of strict mode,
  # which bats-internal code is not written for.
  set +u +o pipefail
  TB_LANG="en"
  opt_reset
  cfg_reset
}

install_fake_cores() {
  cp "$REPO_ROOT/tests/fixtures/fake-xray" "$TOASTBOX_XRAY_BIN"
  cp "$REPO_ROOT/tests/fixtures/fake-sing-box" "$TOASTBOX_SINGBOX_BIN"
}

# A fully specified node, as state.json would describe it.
sample_node() {
  CFG_CORE="xray"
  CFG_SERVER_ADDR="203.0.113.10"
  CFG_NODE_NAME="ToastBox"
  CFG_LISTEN=""
  CFG_BLOCK_BT=0
  CFG_ALLOW_PRIVATE=0
  CFG_VLESS=1
  CFG_VLESS_PORT=443
  CFG_VLESS_UUID="5783a3e7-e373-51cd-8642-c83782b807c5"
  CFG_REALITY_SNI="www.example.com"
  CFG_REALITY_TARGET="www.example.com:443"
  CFG_REALITY_PRIVATE_KEY="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  CFG_REALITY_PUBLIC_KEY="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
  CFG_REALITY_SHORT_ID="0123456789abcdef"
  CFG_SS=1
  CFG_SS_PORT=28443
  CFG_SS_METHOD="2022-blake3-aes-128-gcm"
  CFG_SS_PASSWORD="8JCsPssfgS8tiRwiMlhARg=="
  CFG_SS_NETWORK="both"
  CFG_FW_RULES=()
}

# run_toastbox ARGS...: runs tb_main in a fresh, strict-mode shell with the
# host-touching functions replaced by tests/unit/mocks.bash.
run_toastbox() {
  run bash -c '
    export TOASTBOX_SOURCE_ONLY=1
    source "$1/src/main.sh"
    source "$1/tests/unit/mocks.bash"
    shift
    tb_main "$@"
  ' _ "$REPO_ROOT" "$@"
}

# `! cmd` does not fail a bats test unless it is the last line; this does.
refute() {
  if "$@"; then
    echo "expected failure: $*" >&2
    return 1
  fi
}
