# shellcheck shell=bash
#
# TLS certificate generation, import, validation and SHA-256 pinning for
# Hysteria 2. Certificates and keys are stored as PEM text in state.json and
# embedded directly in the core configurations.

TLS_CERT_PEM=""
TLS_KEY_PEM=""
TLS_CERT_SHA256=""

# Normalizes PATH to an absolute path without dereferencing symlinks (important
# for Certbot /etc/letsencrypt/live/<lineage> symlinks).
tls_abs_path() {
  local path="$1" dir base
  [[ -n "$path" ]] || return 1
  if has_cmd realpath && realpath -s / >/dev/null 2>&1; then
    realpath -s "$path" 2>/dev/null && return 0
  fi
  dir="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  dir="$(cd -L -- "$dir" 2>/dev/null && pwd -L)" || return 1
  printf '%s/%s' "${dir%/}" "$base"
}

# Prints the lowercase 64-hex SHA-256 fingerprint of the leaf certificate
# in CERT_FILE.
tls_cert_sha256_file() {
  local cert_file="$1" fp
  fp="$(openssl x509 -noout -fingerprint -sha256 -in "$cert_file" 2>/dev/null |
    sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$fp"
}

tls_cert_sha256_pem() {
  local cert_pem="$1" fp
  fp="$(openssl x509 -noout -fingerprint -sha256 <<<"$cert_pem" 2>/dev/null |
    sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')"
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$fp"
}

# tls_cert_matches_name CERT_FILE HOST_OR_IP: checks whether the leaf
# certificate is valid for the given domain name or IP literal.
tls_cert_matches_name() {
  local cert_file="$1" name="${2#[}" match_out=""
  name="${name%]}"
  [[ -n "$name" ]] || return 1
  if valid_ipv4 "$name" || valid_ipv6 "$name"; then
    match_out="$(openssl x509 -noout -checkip "$name" -in "$cert_file" 2>/dev/null || true)"
  else
    match_out="$(openssl x509 -noout -checkhost "$name" -in "$cert_file" 2>/dev/null || true)"
  fi
  [[ "$match_out" == *"does match certificate"* ]]
}

tls_pem_matches_name() {
  local cert_pem="$1" name="$2" tmp
  tb_mktemp_dir
  tmp="$TB_TMP/tls-check.crt"
  printf '%s\n' "$cert_pem" >"$tmp"
  tls_cert_matches_name "$tmp" "$name"
}

# Extracts the first concrete DNS name from SAN (or CN) in CERT_FILE.
tls_cert_first_dns_name() {
  local cert_file="$1" san="" cn=""
  san="$(openssl x509 -noout -ext subjectAltName -in "$cert_file" 2>/dev/null |
    grep -oE 'DNS:[^,[:space:]]+' | head -n1 | sed 's/^DNS://' || true)"
  if [[ -n "$san" ]] && valid_domain "$san"; then
    printf '%s' "${san,,}"
    return 0
  fi
  cn="$(openssl x509 -noout -subject -nameopt RFC2253 -in "$cert_file" 2>/dev/null |
    sed -n 's/^subject=.*CN=\([^,]*\).*/\1/p')"
  if [[ -n "$cn" ]] && valid_domain "$cn"; then
    printf '%s' "${cn,,}"
    return 0
  fi
  return 1
}

# Builds a comma-separated OpenSSL subjectAltName list from the server
# address and optional SNI, deduplicating identical entries.
tls_build_san() {
  local server_addr="${1#[}" sni="${2#[}" item entry
  local -a entries=()
  server_addr="${server_addr%]}"
  sni="${sni%]}"
  for item in "$sni" "$server_addr"; do
    [[ -n "$item" ]] || continue
    if valid_ipv4 "$item" || valid_ipv6 "$item"; then
      entry="IP:$item"
    else
      entry="DNS:$item"
    fi
    in_list "$entry" "${entries[@]}" || entries+=("$entry")
  done
  if ((${#entries[@]} == 0)); then
    entries+=("DNS:localhost")
  fi
  join_by , "${entries[@]}"
}

# tls_generate_self_signed SERVER_ADDR [SNI]: creates an ECDSA P-256
# self-signed certificate valid for 10 years, storing PEM text and leaf
# SHA-256 fingerprint in TLS_CERT_PEM / TLS_KEY_PEM / TLS_CERT_SHA256.
tls_generate_self_signed() {
  local server_addr="${1#[}" sni="${2#[}" cn san cnf key_file cert_file
  server_addr="${server_addr%]}"
  sni="${sni%]}"
  tb_mktemp_dir
  cnf="$TB_TMP/tls.cnf"
  key_file="$TB_TMP/tls-gen.key"
  cert_file="$TB_TMP/tls-gen.crt"
  rm -f "$cnf" "$key_file" "$cert_file"

  cn="${sni:-${server_addr:-localhost}}"
  san="$(tls_build_san "$server_addr" "$sni")"
  cat >"$cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no

[dn]
CN = $cn

[v3_ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = $san
EOF

  (
    umask 077
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$key_file" 2>/dev/null &&
      openssl req -new -x509 -sha256 -days 3650 -key "$key_file" -config "$cnf" -out "$cert_file" 2>/dev/null
  ) || {
    rm -f "$cnf" "$key_file" "$cert_file"
    return 1
  }

  TLS_CERT_PEM="$(tr -d '\r' <"$cert_file")"
  TLS_KEY_PEM="$(tr -d '\r' <"$key_file")"
  TLS_CERT_SHA256="$(tls_cert_sha256_file "$cert_file")" || {
    rm -f "$cnf" "$key_file" "$cert_file"
    return 1
  }
  rm -f "$cnf" "$key_file" "$cert_file"
}

# tls_validate_pair_files CERT_FILE KEY_FILE: checks that CERT_FILE is an
# unexpired PEM certificate chain, KEY_FILE is an unencrypted private key,
# and their public keys match. Populates TLS_CERT_PEM / TLS_KEY_PEM /
# TLS_CERT_SHA256.
tls_validate_pair_files() {
  local cert_file="$1" key_file="$2" tmp_cert tmp_key cert_pub key_pub
  tb_mktemp_dir
  tmp_cert="$TB_TMP/tls-import.crt"
  tmp_key="$TB_TMP/tls-import.key"
  [[ -f "$cert_file" && -r "$cert_file" ]] || return 1
  [[ -f "$key_file" && -r "$key_file" ]] || return 1

  tr -d '\r' <"$cert_file" >"$tmp_cert"
  (
    umask 077
    tr -d '\r' <"$key_file" >"$tmp_key"
  )

  if ! openssl x509 -noout -checkend 0 -in "$tmp_cert" >/dev/null 2>&1 ||
    ! openssl pkey -in "$tmp_key" -passin pass: -noout >/dev/null 2>&1; then
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  fi

  cert_pub="$(openssl x509 -noout -pubkey -in "$tmp_cert" 2>/dev/null || true)"
  key_pub="$(openssl pkey -pubout -in "$tmp_key" -passin pass: 2>/dev/null || true)"
  if [[ -z "$cert_pub" || "$cert_pub" != "$key_pub" ]]; then
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  fi

  TLS_CERT_SHA256="$(tls_cert_sha256_file "$tmp_cert")" || {
    rm -f "$tmp_cert" "$tmp_key"
    return 1
  }
  TLS_CERT_PEM="$(<"$tmp_cert")"
  TLS_KEY_PEM="$(<"$tmp_key")"
  rm -f "$tmp_cert" "$tmp_key"
}

tls_validate_pem_pair() {
  local cert_pem="$1" key_pem="$2" tmp_cert tmp_key
  [[ -n "$cert_pem" && -n "$key_pem" ]] || return 1
  tb_mktemp_dir
  tmp_cert="$TB_TMP/tls-mem.crt"
  tmp_key="$TB_TMP/tls-mem.key"
  printf '%s\n' "$cert_pem" >"$tmp_cert"
  (
    umask 077
    printf '%s\n' "$key_pem" >"$tmp_key"
  )
  local rc=0
  tls_validate_pair_files "$tmp_cert" "$tmp_key" || rc=$?
  rm -f "$tmp_cert" "$tmp_key"
  return "$rc"
}
