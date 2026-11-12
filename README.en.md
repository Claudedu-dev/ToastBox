# ToastBox

[简体中文](README.md) | English

Deploy **VLESS-TCP-REALITY-Vision** and **Shadowsocks 2022** nodes on Debian / Ubuntu with one command, on either [Xray](https://github.com/XTLS/Xray-core) or [sing-box](https://github.com/SagerNet/sing-box).

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
| `rotate` | Generate a new UUID, REALITY key pair, short ID and Shadowsocks password |
| `uninstall` | Remove the core and the node; `--purge` also deletes configuration, logs and backups |

### Options for `install`

| Option | Default | Meaning |
| --- | --- | --- |
| `--core xray\|sing-box` | `xray` | Core to use |
| `--protocols LIST` | `vless,ss` | `vless`, `ss` or `vless,ss` |
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
| `--block-bt` | off | Reject BitTorrent traffic |
| `--allow-private` | off | Allow relaying to private / loopback addresses |
| `--core-version VERSION` | latest | Install this core version |
| `--no-firewall` | | Do not touch ufw |

General: `-y` / `--yes` (never prompt), `--lang en|zh`, `--help`.

### Output formats of `show`

```bash
sudo toastbox show                          # parameters and share links
sudo toastbox show --qr                     # with QR codes
sudo toastbox show --format links           # share links only
sudo toastbox show --format xray            # complete Xray client configuration
sudo toastbox show --format sing-box        # complete sing-box client configuration
sudo toastbox show --format json            # machine-readable
sudo toastbox show --format xray --protocols ss   # one protocol only
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

### Security defaults

- The node refuses to relay to loopback, private and link-local addresses (where cloud metadata endpoints live). Use `--allow-private` if you really need to reach the server's internal network.
- Xray's access log is off; sing-box logs at `warn`.
- `--block-bt` relies on sniffing. With it, protocols where the server speaks first (SSH, SMTP) wait a moment longer when a connection is set up.
- Configuration and state hold private keys: the Xray configuration is `root:xray 0640`, the sing-box configuration and `state.json` are `root 0600`.

### Firewall

When ufw is active, the script allows the ports the node uses and removes the rules it added itself when ports change or on uninstall (rules you created are left alone). Provider-side security groups are up to you.

### Public address detection

Without `--server-addr`, the script looks at the address of the default route first; if that is a private address (NAT) it asks `cloudflare.com/cdn-cgi/trace` and `api.ipify.org` for the public IP.

## Files

| Path | Content |
| --- | --- |
| `/etc/toastbox/state.json` | Every parameter of the node; links and client configurations are rendered from it |
| `/etc/toastbox/backup/` | Server configurations as they were before each replacement, five per core |
| `/usr/local/etc/xray/config.json` | Xray server configuration |
| `/etc/sing-box/config.json` | sing-box server configuration |
| `/usr/local/bin/toastbox` | A copy of the script |

The sing-box service merges every JSON file in `/etc/sing-box/`. The script tells you when other files are present there.

## Development

The sources live in `src/` as modules. `toastbox.sh` in the repository root is the single-file release generated from them; do not edit it by hand.

```bash
make build   # generate toastbox.sh from src/
make lint    # shellcheck + shfmt
make test    # bats unit tests (apt, systemd and the network are replaced)
make check   # lint + test
```

`tests/unit/` holds the unit tests and full command flows against mocks. `tests/e2e/run.sh` is the real thing: CI runs it for both cores on Ubuntu 22.04 and 24.04. It installs and purges the core, so **only run it on a disposable machine**. CI does not cover Debian or arm64 yet.

## License

[MIT](LICENSE) © ToastSail
