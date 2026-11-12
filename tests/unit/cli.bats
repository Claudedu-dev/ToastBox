#!/usr/bin/env bats

load helper

setup() { load_toastbox; }

# Runs the real entry point (strict mode, no mocks) without a terminal.
tb() {
  run env -u TOASTBOX_SOURCE_ONLY bash -c 'bash "$0" "$@" </dev/null' "$REPO_ROOT/src/main.sh" "$@"
}

# Same, with extra environment assignments: tb_env VAR=value... -- ARGS...
tb_env() {
  local -a vars=()
  while [[ "$1" != "--" ]]; do
    vars+=("$1")
    shift
  done
  shift
  run env -u TOASTBOX_SOURCE_ONLY "${vars[@]}" bash -c 'bash "$0" "$@" 2>&1 </dev/null' "$REPO_ROOT/src/main.sh" "$@"
}

@test "parse_args accepts --opt value and --opt=value" {
  parse_args install --core sing-box --vless-port=8443 --reality-sni www.example.com -y
  [ "$OPT_COMMAND" = "install" ]
  [ "$OPT_CORE" = "sing-box" ]
  [ "$OPT_VLESS_PORT" = "8443" ]
  [ "$OPT_REALITY_SNI" = "www.example.com" ]
  [ "$OPT_YES" = "1" ]
}

@test "boolean pairs can be switched off again" {
  parse_args install --block-bt --allow-private
  [ "$OPT_BLOCK_BT$OPT_ALLOW_PRIVATE" = "11" ]
  opt_reset
  parse_args install --no-block-bt --no-allow-private
  [ "$OPT_BLOCK_BT$OPT_ALLOW_PRIVATE" = "00" ]
  opt_reset
  parse_args install
  [ -z "$OPT_BLOCK_BT" ]
}

@test "validate_options canonicalizes values" {
  parse_args install --core singbox --protocols ss,vless --ss-method 2 --reality-sni WWW.Example.com --core-version v26.11.9
  validate_options
  [ "$OPT_CORE" = "sing-box" ]
  [ "$OPT_PROTOCOLS" = "vless,ss" ]
  [ "$OPT_SS_METHOD" = "2022-blake3-aes-256-gcm" ]
  [ "$OPT_REALITY_SNI" = "www.example.com" ]
  [ "$OPT_CORE_VERSION" = "26.11.9" ]
}

@test "version" {
  tb --version
  [ "$status" -eq 0 ]
  [ "$output" = "ToastBox $TB_VERSION" ]
}

@test "help is available in both languages" {
  tb --lang en help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: toastbox.sh"* ]]
  [[ "$output" == *"--reality-sni"* ]]
  tb --lang=zh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"用法：toastbox.sh"* ]]
  [[ "$output" == *"--reality-sni"* ]]
}

@test "the locale selects the language, TOASTBOX_LANG overrides it" {
  tb_env LC_ALL=zh_CN.UTF-8 -- bogus
  [[ "$output" == *"未知参数"* ]]
  tb_env LC_ALL=zh_CN.UTF-8 TOASTBOX_LANG=en -- bogus
  [[ "$output" == *"Unknown argument"* ]]
  tb_env LC_ALL=C LANG=C -- bogus
  [[ "$output" == *"Unknown argument"* ]]
}

@test "bad input is rejected with a non-zero status" {
  tb bogus
  [ "$status" -eq 1 ]
  tb install --core
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs a value"* ]]
  tb install --core v2ray
  [ "$status" -eq 1 ]
  tb install --vless-port 70000
  [ "$status" -eq 1 ]
  tb install --reality-sni "not a domain"
  [ "$status" -eq 1 ]
  tb install --reality-target www.example.com
  [ "$status" -eq 1 ]
  tb install --ss-method aes-256-gcm
  [ "$status" -eq 1 ]
  tb show --format yaml
  [ "$status" -eq 1 ]
  tb --lang fr help
  [ "$status" -eq 1 ]
  tb install show
  [ "$status" -eq 1 ]
}

@test "without a terminal and without a command, usage is printed" {
  tb
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "the single-file release is up to date and behaves the same" {
  run bash "$REPO_ROOT/scripts/build.sh" --check
  [ "$status" -eq 0 ]
  run env -u TOASTBOX_SOURCE_ONLY bash "$REPO_ROOT/toastbox.sh" --version
  [ "$output" = "ToastBox $TB_VERSION" ]
  run env -u TOASTBOX_SOURCE_ONLY bash -c 'bash "$1/toastbox.sh" --lang en help </dev/null' _ "$REPO_ROOT"
  [[ "$output" == *"Usage: toastbox.sh"* ]]
}

@test "a truncated download does nothing" {
  # Everything but the final dispatch: must define functions only.
  head -n -5 "$REPO_ROOT/toastbox.sh" >"$BATS_TEST_TMPDIR/partial.sh"
  run env -u TOASTBOX_SOURCE_ONLY bash "$BATS_TEST_TMPDIR/partial.sh" install -y
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
