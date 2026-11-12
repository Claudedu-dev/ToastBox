# shellcheck shell=bash
#
# Credential generation and validation.

valid_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# X25519 keys as both cores print and read them: 32 bytes, base64url
# without padding (43 characters).
valid_reality_key() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{43}$ ]]
}

# Up to 8 bytes of hex; the digit count must be even.
valid_short_id() {
  [[ "$1" =~ ^([0-9a-fA-F]{2}){0,8}$ ]]
}

valid_ss_method() { in_list "$1" "${TB_SS_METHODS[@]}"; }

ss_key_length() {
  case "$1" in
    2022-blake3-aes-128-gcm) printf '16' ;;
    *) printf '32' ;;
  esac
}

# A Shadowsocks 2022 password is a base64 pre-shared key whose decoded
# length is fixed by the method.
valid_ss_password() {
  local method="$1" password="$2" bytes
  [[ "$password" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  bytes="$(printf '%s' "$password" | openssl base64 -d -A 2>/dev/null | wc -c)"
  [[ "${bytes//[[:space:]]/}" == "$(ss_key_length "$method")" ]]
}

gen_ss_password() {
  openssl rand -base64 "$(ss_key_length "$1")"
}

gen_short_id() {
  openssl rand -hex 8
}

gen_uuid() {
  local uuid=""
  case "$CFG_CORE" in
    xray) uuid="$("$TB_XRAY_BIN" uuid 2>/dev/null || true)" ;;
    sing-box) uuid="$("$TB_SINGBOX_BIN" generate uuid 2>/dev/null || true)" ;;
  esac
  if ! valid_uuid "$uuid"; then
    uuid="$(cat /proc/sys/kernel/random/uuid)"
  fi
  printf '%s' "$uuid"
}

GEN_PRIVATE_KEY=""
GEN_PUBLIC_KEY=""

# parse_keypair OUTPUT: extracts a key pair from `xray x25519` or
# `sing-box generate reality-keypair` output. The labels changed over time:
#   Private key: / Public key:               (older Xray)
#   PrivateKey: / Password:                  (Xray 25.x)
#   PrivateKey: / Password (PublicKey):      (current Xray)
#   PrivateKey: / PublicKey:                 (sing-box)
# so lines are matched by label rather than by position.
parse_keypair() {
  local output="$1"
  GEN_PRIVATE_KEY="$(printf '%s\n' "$output" |
    awk -F': *' 'tolower($1) ~ /^private ?key$/ {print $NF; exit}')"
  GEN_PUBLIC_KEY="$(printf '%s\n' "$output" |
    awk -F': *' 'tolower($1) ~ /^(public ?key|password)/ {print $NF; exit}')"
  valid_reality_key "$GEN_PRIVATE_KEY" && valid_reality_key "$GEN_PUBLIC_KEY"
}

# Generates a REALITY key pair with the active core, so the encoding always
# matches what that core expects. Result in GEN_PRIVATE_KEY / GEN_PUBLIC_KEY.
gen_reality_keypair() {
  local output=""
  case "$CFG_CORE" in
    xray) output="$("$TB_XRAY_BIN" x25519 2>/dev/null || true)" ;;
    sing-box) output="$("$TB_SINGBOX_BIN" generate reality-keypair 2>/dev/null || true)" ;;
  esac
  parse_keypair "$output"
}

# Fills in whatever credentials are still missing for the enabled protocols.
ensure_credentials() {
  if [[ "$CFG_VLESS" == "1" ]]; then
    valid_uuid "$CFG_VLESS_UUID" || CFG_VLESS_UUID="$(gen_uuid)"
    if ! valid_reality_key "$CFG_REALITY_PRIVATE_KEY" || ! valid_reality_key "$CFG_REALITY_PUBLIC_KEY"; then
      gen_reality_keypair || die err_keypair "$CFG_CORE"
      CFG_REALITY_PRIVATE_KEY="$GEN_PRIVATE_KEY"
      CFG_REALITY_PUBLIC_KEY="$GEN_PUBLIC_KEY"
    fi
    if [[ -z "$CFG_REALITY_SHORT_ID" ]] || ! valid_short_id "$CFG_REALITY_SHORT_ID"; then
      CFG_REALITY_SHORT_ID="$(gen_short_id)"
    fi
  fi
  if [[ "$CFG_SS" == "1" ]]; then
    # Also catches a method change: the key length differs between methods.
    if ! valid_ss_password "$CFG_SS_METHOD" "$CFG_SS_PASSWORD"; then
      CFG_SS_PASSWORD="$(gen_ss_password "$CFG_SS_METHOD")"
    fi
  fi
}

clear_credentials() {
  CFG_VLESS_UUID=""
  CFG_REALITY_PRIVATE_KEY=""
  CFG_REALITY_PUBLIC_KEY=""
  CFG_REALITY_SHORT_ID=""
  CFG_SS_PASSWORD=""
}
