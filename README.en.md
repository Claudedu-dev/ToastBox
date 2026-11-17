# ToastBox

[简体中文](README.md) | English

Deploy **VLESS-TCP-REALITY-Vision**, **Shadowsocks 2022** and **Hysteria 2** nodes on Debian / Ubuntu with one command, on either [Xray](https://github.com/XTLS/Xray-core) or [sing-box](https://github.com/SagerNet/sing-box).

- Cores come from their official sources: [XTLS/Xray-install](https://github.com/XTLS/Xray-install) for Xray, the official APT repository for sing-box.
- Only the configuration format of the current documentation is written; no deprecated fields.
- A new configuration is validated by the core itself before it replaces the old one, and is rolled back if the service does not come up.
- Re-runs are idempotent: settings you do not pass keep their value, and UUIDs, keys and passwords are not regenerated.
- English and Chinese, interactive or fully unattended.

## Requirements

| Item | Requirement |
| --- | --- |
| System | Debian 11+ or Ubuntu 20.04+, with systemd |
| Architecture | amd64, arm64 |
| Privileges | root |
| Xray | 26.7.11 or newer (the latest is installed by default) |
| sing-box | 1.12.0 or newer (the latest is installed by default) |

## Quick start

```bash
curl -fsSLO https://raw.githubusercontent.com/Claudedu-dev/ToastBox/main/toastbox.sh
sudo bash toastbox.sh
```

Without arguments you get an interactive menu. After a successful deployment the script installs itself as `toastbox`:

```bash
sudo toastbox show
```

Unattended:

```bash
sudo bash toastbox.sh install -y \
  --core xray \
  --reality-sni www.example.com \
  --ss-port 28443
```

## Commands

| Command | Purpose |
| --- | --- |
| `install` | Deploy a node, or change the settings of an existing one |
| `show` | Print connection details, share links or client configurations |
| `update` | Upgrade the core and restart the node |
| `rotate` | Generate a new UUID, REALITY key pair, short ID, Shadowsocks password and Hysteria 2 auth/obfs passwords (keeps TLS certificates) |
| `refresh-cert` | Re-validate and re-import `--hy2-cert` / `--hy2-key`; restarts the active core when cert or key changes |
| `uninstall` | Remove the core and the node; `--purge` also deletes configuration, logs and backups |

### Options for `install`

| Option | Default | Meaning |
| --- | --- | --- |
| `--core xray\|sing-box` | `xray` | Core to use |
| `--protocols LIST` | `vless,ss` | `vless`, `ss`, `hy2`, `both` (`vless,ss`), `all` (all three), or comma-separated list |
| `--server-addr ADDR` | detected | IP or domain clients connect to |
| `--name NAME` | `ToastBox` | Node name in share links |
| `--listen ADDR` | all addresses | Bind to this local address |
| `--vless-port PORT` | `443` | VLESS port |
| `--reality-sni DOMAIN` | none, required | REALITY target domain |
| `--reality-target HOST:PORT` | `<sni>:443` | REALITY target |
| `--skip-target-check` | | Do not probe the target |
| `--ss-port PORT` | random | Shadowsocks port |
| `--ss-method METHOD` | `2022-blake3-aes-128-gcm` | Also `2022-blake3-aes-256-gcm`, `2022-blake3-chacha20-poly1305` |
| `--ss-network both\|tcp\|udp` | `both` | Shadowsocks listen network |
| `--hy2-port PORT` | `443` | Hysteria 2 UDP port (may match VLESS TCP or TCP-only SS port) |
| `--hy2-sni NAME` | domain server addr | Hysteria 2 TLS verification name (SNI) |
| `--hy2-tls self-signed\|files\|acme` | `self-signed` | Self-signed ECDSA cert, import PEM files, or obtain public CA cert via Certbot standalone |
| `--hy2-cert FILE` | | Certificate chain PEM to import (implies `--hy2-tls files`) |
| `--hy2-key FILE` | | Private key PEM to import (must accompany `--hy2-cert`) |
| `--hy2-cert-hook certbot\|none` | `none` | Install or remove the Certbot deploy hook `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh` |
| `--hy2-acme-domain DOMAIN` | domain addr or `--hy2-sni` | Domain for Certbot `--standalone` public cert (implies `--hy2-tls acme`) |
| `--hy2-acme-email EMAIL` | | Account email for Let's Encrypt / Certbot (required when issuing) |
| `--hy2-acme-agree-tos` | | Accept CA Subscriber Agreement for non-interactive ACME (not implied by `-y`) |
| `--hy2-hop-ports LIST\|none` | `none` | Optional Hysteria 2 UDP port-hopping ranges (e.g. `20000-20100,30000`), or `none` to clear |
| `--hy2-hop-interval SEC\|MIN-MAX` | `30` | UDP hop interval in seconds or min-max range (at least `5` s) |
| `--hy2-obfs none\|salamander` | `none` | Optional Salamander obfuscation with generated password |
| `--hy2-masquerade none\|URL` | none | HTTP/3 reverse proxy masquerade URL, or `none` to clear |
| `--hy2-renew-cert` | | Explicitly regenerate the self-signed Hysteria 2 certificate |
| `--tcp-keepalive-idle SEC` | no override | Xray TCP keepalive idle, 1–32767 seconds; `0` clears it |
| `--tcp-keepalive-interval SEC` | no override | Xray TCP keepalive interval, 1–32767 seconds; `0` clears it |
| `--tcp-user-timeout MS` | no override | Xray TCP user timeout, 1–2147483647 milliseconds; `0` clears it |
| `--reset-sockopt` | | Clear saved TCP overrides before applying explicit flags |
| `--block-bt` | off | Reject BitTorrent traffic |
| `--allow-private` | off | Allow relaying to private / loopback addresses |
| `--core-version VERSION` | latest | Install this core version |
| `--no-firewall` | | Do not touch ufw (Hysteria 2 hop NAT rules are still applied when `--hy2-hop-ports` is enabled) |
| `--overwrite-config` | | Replace a configuration ToastBox did not write; `-y` alone never does |

General: `-y` / `--yes` (never prompt), `--lang en|zh`, `--help`.

### Output formats of `show`

```bash
sudo toastbox show                          # parameters and share links
sudo toastbox show --qr                     # with QR codes
sudo toastbox show --format links           # share links only
sudo toastbox show --format xray            # complete Xray client configuration
sudo toastbox show --format sing-box        # complete sing-box client configuration
sudo toastbox show --format hysteria2       # official Hysteria 2 client configuration
sudo toastbox show --format json            # machine-readable (no private keys)
sudo toastbox show --format xray --protocols hy2   # one protocol only
```

The client configurations open a proxy on `127.0.0.1:1080` and can be saved and run as they are.

## Things to know

### Choosing a REALITY target

REALITY borrows the TLS identity of a real website. Connections that fail authentication are forwarded to that site untouched, so:

- the target must support TLS 1.3, preferably HTTP/2 as well;
- **do not pick a site behind a CDN such as Cloudflare**, or your server becomes a free relay for that CDN;
- ideally the target is hosted in the same network (ASN) as your server.

There is no built-in default domain; you have to supply one. Before deploying, the script performs a real handshake from the server and checks that the target speaks TLS 1.3 and presents a certificate valid for that name. It refuses to continue otherwise (`--skip-target-check` overrides).

### Shadowsocks 2022 is meant as a landing node

Shadowsocks has no TLS camouflage and its traffic can be classified. Put it behind a relay or tunnel; do not send it straight through a censoring firewall.

Shadowsocks 2022 also needs both clocks to roughly agree. The script warns when time synchronization is off.

### Hysteria 2 TLS certificates and renewal

- **Self-signed (`--hy2-tls self-signed`, default)**: suited for direct IP deployments. Generates a 10-year ECDSA P-256 certificate with matching SANs on first deploy. Re-runs, `update`, and `rotate` preserve the certificate (`rotate` rotates auth and obfs passwords only). Official Hysteria clients use `insecure: true` + `pinSHA256`, Xray clients use `pinnedPeerCertSha256`, and sing-box clients embed the public PEM certificate. Pass `--hy2-renew-cert` explicitly (or change `--server-addr` / `--hy2-sni` so the old SAN no longer covers it) to issue a new self-signed certificate.
- **Imported certificates (`--hy2-tls files`)**: import a certificate chain and private key managed by an external ACME / Certbot tool (for example reusing `/etc/letsencrypt/live/<domain>/fullchain.pem` and `privkey.pem` already issued for ToastWeb) via `--hy2-cert` and `--hy2-key`. Clients validate via the system CA store. ToastBox keeps `live` symlink paths intact without resolving into `archive/...1.pem`, validates the pair, and embeds a snapshot in `state.json` and the server config without modifying Certbot or ToastWeb.
  - Pass `--hy2-cert-hook certbot` to install `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh`, which runs `toastbox refresh-cert` automatically whenever that lineage renews; you can also run `sudo toastbox refresh-cert` manually (or re-import via `--hy2-cert` / `--hy2-key`). Unchanged cert/key pairs skip core restart; changed pairs regenerate server config and restart the active core (this is NOT a hitless hot-reload: active connections on that core drop briefly because certs are embedded).
- **Automatic Certbot standalone issuance (`--hy2-tls acme`, no ToastWeb / Nginx needed)**: pass `--hy2-tls acme`, `--hy2-acme-domain` (or a domain `--server-addr`), `--hy2-acme-email`, and `--hy2-acme-agree-tos` (required for non-interactive mode; `-y` alone never accepts CA ToS). ToastBox invokes `certbot certonly --standalone` (temporary HTTP-01 listener on TCP 80 during validation) to issue an ECDSA cert under its own `toastbox-hy2-<domain>` lineage and wires it into the `files` flow and deploy hook (`state.json` keeps `hy2.tls = "files"`, and clients validate via the system CA store with no `insecure` or pin).
  - Public DNS must already point to this server, and both host firewall and cloud security group must allow inbound TCP 80 for issuance and future renewals (when ufw is active without `--no-firewall`, ToastBox opens and tracks `80/tcp`). If TCP 80 is already held by Nginx / ToastWeb, ToastBox refuses clearly without stopping existing services.
  - ToastBox reuses an existing valid cert on re-installs, reuses an active system `certbot.timer` / `snap.certbot.renew.timer` when present, or installs a scoped `toastbox-hy2-certbot.timer` (`toastbox-hy2-certbot.service`). Disabling automation or uninstalling removes only ToastBox's hook and scoped timer, leaving shared Certbot timers, accounts, and certificates untouched.

```bash
# Automatic public CA certificate via Certbot standalone (no ToastWeb / Nginx required)
sudo toastbox install -y \
  --core sing-box --protocols hy2 \
  --server-addr proxy.example.com \
  --hy2-tls acme \
  --hy2-acme-email admin@example.com \
  --hy2-acme-agree-tos
```

### Hysteria 2 UDP port hopping

- Enable optional UDP port hopping with `--hy2-hop-ports 20000-20100,30000` and optional `--hy2-hop-interval 30` (or `15-45`, minimum `5` s); pass `--hy2-hop-ports none` to disable hopping and clean up its rules.
- Both Xray and sing-box servers stay single-port listeners on `--hy2-port` (for example `443/udp`); ToastBox installs kernel `PREROUTING` NAT redirects (`nftables` preferred, `iptables`/`ip6tables` fallback) via `/usr/local/libexec/toastbox-hy2-hop`, `toastbox-hy2-hop.service`, and a core systemd drop-in so rules persist across reboots.
- Cloud security groups / external firewalls must open both `--hy2-port` UDP and all configured `--hy2-hop-ports` UDP ranges; ufw only needs the post-NAT listening port `--hy2-port`.
- Version compatibility: server core minimums stay `Xray >= 26.7.11` / `sing-box >= 1.12.0`; when port hopping is enabled, exported client configs target `Hysteria >= app/v2.14.0`, `Xray >= 26.11.9` (`finalmask.udp` `udphop`), or `sing-box >= 1.11.0` (fixed interval; random `hop_interval_max` requires `sing-box >= 1.14.0`).

```bash
# Reuse an existing Certbot cert (e.g. alongside ToastWeb) + deploy hook + UDP port hopping
sudo toastbox install -y \
  --core sing-box --protocols hy2 \
  --server-addr proxy.example.com \
  --hy2-cert /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --hy2-key /etc/letsencrypt/live/proxy.example.com/privkey.pem \
  --hy2-cert-hook certbot \
  --hy2-hop-ports 20000-20100,30000 --hy2-hop-interval 15-45
```

### Security defaults

- The node refuses to relay to loopback, private and link-local addresses (where cloud metadata endpoints live) when they are given as IP addresses. This is not complete isolation: a domain name that resolves to a private address is not caught. Use `--allow-private` if you really need to reach the server's internal network.
- Xray's access log is off; sing-box logs at `warn`.
- `--block-bt` relies on sniffing. With it, protocols where the server speaks first (SSH, SMTP) wait a moment longer when a connection is set up.
- Configuration and state hold private keys: the Xray configuration is `root:xray 0640`, the sing-box configuration and `state.json` are `root 0600`.

### Persistent TCP socket options (Xray)

These are optional settings, not a default tuning profile. To save a profile on an existing Xray node:

```bash
sudo toastbox install -y --no-firewall \
  --tcp-keepalive-idle 120 \
  --tcp-keepalive-interval 30 \
  --tcp-user-timeout 120000
```

The options are stored in the `sockopt` object of `state.json` and replayed by later `install` runs (without these flags), `update` and `rotate`. Changing socket settings does not replace credentials; `rotate` still rotates them as before.

- New nodes and old state files without `sockopt` get no overrides, keeping core / system defaults. Hand-edited server JSON is not imported automatically; enter those values once with these flags.
- Only Xray TCP inbounds are affected: VLESS-REALITY and the TCP part of SS TCP or TCP+UDP. UDP-only SS gets no socket overrides. Outbounds, client configurations and host `sysctl` are unchanged.
- Keepalive values are in seconds; user timeout is in milliseconds. `tcpUserTimeout` only takes effect on Linux. Negative, fractional, non-numeric and out-of-range values are rejected.
- Changing one value preserves the others; `0` removes that override. `--reset-sockopt` clears everything before applying explicit values from the same command, regardless of argument order.
- sing-box does not accept these Xray-specific settings. Switching cores with custom settings is refused; use `install --core sing-box --reset-sockopt` to explicitly clear them and switch.
- These CLI options are accepted only with `install`; `update` / `rotate` reuse the saved settings. `show` reports saved values, not runtime socket measurements.

### Firewall

When ufw is active, the script allows the node's listening ports (Hysteria 2 hop traffic is redirected via `PREROUTING` NAT, so ufw only needs `--hy2-port`) and removes the rules it added itself when ports change or on uninstall (rules you created are left alone). `--no-firewall` only skips ufw changes; when `--hy2-hop-ports` is enabled, required hop NAT rules are still applied. Provider-side security groups must allow all UDP hop ports yourself.

### Public address detection

Without `--server-addr`, the script looks at the address of the default route first; if that is a private address (NAT) it asks `cloudflare.com/cdn-cgi/trace` and `api.ipify.org` for the public IP.

## Files

| Path | Content |
| --- | --- |
| `/etc/toastbox/state.json` | Every parameter of the node; links and client configurations are rendered from it |
| `/etc/toastbox/hy2-hop.json` | Hysteria 2 UDP port-hopping NAT runtime snapshot |
| `/etc/toastbox/backup/` | Server configurations as they were before each replacement, five per core |
| `/usr/local/etc/xray/config.json` | Xray server configuration |
| `/etc/sing-box/config.json` | sing-box server configuration |
| `/usr/local/bin/toastbox` | A copy of the script |
| `/usr/local/libexec/toastbox-hy2-hop` | Standalone UDP port-hopping NAT helper script |
| `/etc/systemd/system/toastbox-hy2-hop.service` | Systemd unit (plus core service drop-in) applying hop NAT across reboots |
| `/etc/systemd/system/toastbox-hy2-certbot.timer` | Scoped renewal timer (plus `.service`) created when no shared system Certbot timer is active |
| `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh` | Certbot deploy hook invoking `refresh-cert` on renewal (with `--hy2-cert-hook certbot` or `acme`) |

The sing-box service merges every JSON file in `/etc/sing-box/`. The script tells you when other files are present there.

## Development

The sources live in `src/` as modules. `toastbox.sh` in the repository root is the single-file release generated from them; do not edit it by hand.

```bash
make build   # generate toastbox.sh from src/
make lint    # shellcheck + shfmt
make test    # bats unit tests (apt, systemd and the network are replaced)
make check   # lint + test
```

`tests/unit/` holds the unit tests and full command flows against mocks (including `35-hy2-hop.sh`, `55-tls.sh`, `56-cert-hook.sh`, and `57-acme.sh`). `tests/e2e/run.sh` is the real thing: CI runs it for both cores on Ubuntu 22.04 and 24.04 (including live Certbot symlink renewal and isolated `veth` namespace UDP port-hopping E2E). It installs and purges the core, so **only run it on a disposable machine**. CI does not cover Debian or arm64 yet.

## License

[MIT](LICENSE) © ToastSail
