#!/usr/bin/env bats

load helper

setup() { load_toastbox; }

@test "valid_port accepts 1-65535 only" {
  valid_port 1
  valid_port 443
  valid_port 65535
  valid_port 0443
  refute valid_port 0
  refute valid_port 65536
  refute valid_port 44a
  refute valid_port ""
  refute valid_port -1
}

@test "valid_domain" {
  valid_domain www.example.com
  valid_domain a-b.example.co.uk
  refute valid_domain localhost
  refute valid_domain "exa mple.com"
  refute valid_domain "-bad.example.com"
  refute valid_domain "example.com/path"
  refute valid_domain "203.0.113.1"
}

@test "valid_ipv4 and valid_ipv6" {
  valid_ipv4 203.0.113.1
  refute valid_ipv4 256.1.1.1
  refute valid_ipv4 1.2.3
  valid_ipv6 2001:db8::1
  valid_ipv6 ::1
  refute valid_ipv6 www.example.com
  refute valid_ipv6 12:34
}

@test "valid_host_port, host_of and port_of" {
  valid_host_port www.example.com:443
  valid_host_port 203.0.113.1:8443
  valid_host_port "[2001:db8::1]:443"
  refute valid_host_port www.example.com
  refute valid_host_port www.example.com:0
  refute valid_host_port "2001:db8::1:443x"
  [ "$(host_of www.example.com:443)" = "www.example.com" ]
  [ "$(port_of www.example.com:443)" = "443" ]
  [ "$(host_of '[2001:db8::1]:8443')" = "2001:db8::1" ]
  [ "$(port_of '[2001:db8::1]:8443')" = "8443" ]
}

@test "uri_host brackets IPv6 literals only" {
  [ "$(uri_host 203.0.113.1)" = "203.0.113.1" ]
  [ "$(uri_host node.example.com)" = "node.example.com" ]
  [ "$(uri_host 2001:db8::1)" = "[2001:db8::1]" ]
}

@test "is_private_ipv4" {
  is_private_ipv4 10.0.0.5
  is_private_ipv4 172.16.0.1
  is_private_ipv4 172.31.255.1
  is_private_ipv4 192.168.1.1
  is_private_ipv4 100.64.0.1
  is_private_ipv4 100.127.0.1
  refute is_private_ipv4 172.32.0.1
  refute is_private_ipv4 100.128.0.1
  refute is_private_ipv4 203.0.113.1
}

@test "ver_ge compares versions numerically" {
  ver_ge 26.11.9 26.7.11
  ver_ge 26.7.11 26.7.11
  ver_ge v26.7.11 26.7.11
  ver_ge 1.14.4 1.12.0
  ver_ge 1.15.0-alpha.13 1.12.0
  refute ver_ge 26.7.9 26.7.11
  refute ver_ge 25.12.31 26.7.11
  refute ver_ge 1.9.7 1.12.0
}

@test "valid_short_id: even number of hex digits, at most 16" {
  valid_short_id ""
  valid_short_id ab
  valid_short_id 0123456789abcdef
  refute valid_short_id abc
  refute valid_short_id 0123456789abcdef01
  refute valid_short_id xy
}

@test "valid_ss_password checks the decoded key length per method" {
  valid_ss_password 2022-blake3-aes-128-gcm "8JCsPssfgS8tiRwiMlhARg=="
  refute valid_ss_password 2022-blake3-aes-256-gcm "8JCsPssfgS8tiRwiMlhARg=="
  valid_ss_password 2022-blake3-aes-256-gcm "$(openssl rand -base64 32)"
  valid_ss_password 2022-blake3-chacha20-poly1305 "$(openssl rand -base64 32)"
  refute valid_ss_password 2022-blake3-aes-128-gcm "not base64!"
  refute valid_ss_password 2022-blake3-aes-128-gcm ""
}

@test "normalizers canonicalize accepted spellings" {
  [ "$(norm_core 1)" = "xray" ]
  [ "$(norm_core singbox)" = "sing-box" ]
  refute norm_core v2ray
  [ "$(norm_protocols all)" = "vless,ss" ]
  [ "$(norm_protocols ss,vless)" = "vless,ss" ]
  [ "$(norm_protocols 2)" = "vless" ]
  [ "$(norm_protocols shadowsocks)" = "ss" ]
  refute norm_protocols trojan
  refute norm_protocols ""
  [ "$(norm_port 0443)" = "443" ]
  [ "$(norm_domain WWW.Example.COM)" = "www.example.com" ]
  [ "$(norm_host '[2001:db8::1]')" = "2001:db8::1" ]
  [ "$(norm_ss_method 2)" = "2022-blake3-aes-256-gcm" ]
  refute norm_ss_method aes-256-gcm
  [ "$(norm_ss_network tcp,udp)" = "both" ]
  [ "$(norm_format singbox)" = "sing-box" ]
  [ "$(norm_version v26.11.9)" = "26.11.9" ]
  [ "$(norm_version 1.15.0-alpha.13)" = "1.15.0-alpha.13" ]
  refute norm_version latest
}
