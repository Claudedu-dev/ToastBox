# ToastBox

简体中文 | [English](README.en.md)

在 Debian / Ubuntu 上一条命令部署 **VLESS-TCP-REALITY-Vision**、**Shadowsocks 2022** 与 **Hysteria 2** 节点，内核可选 [Xray](https://github.com/XTLS/Xray-core) 或 [sing-box](https://github.com/SagerNet/sing-box)。

- 内核通过官方渠道安装：Xray 使用 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)，sing-box 使用官方 APT 源。
- 只写当前文档里的配置格式，不使用已弃用的字段。
- 新配置先由内核自己校验，再替换旧配置；服务起不来会自动回滚。
- 重复运行是幂等的：没在命令行里给出的设置保持不变，UUID、密钥、密码不会被重新生成。
- 中英双语，可交互，也可全参数无人值守。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Debian 11+ 或 Ubuntu 20.04+，使用 systemd |
| 架构 | amd64、arm64 |
| 权限 | root |
| Xray | 26.7.11 或更高（脚本默认安装最新版） |
| sing-box | 1.12.0 或更高（脚本默认安装最新版） |

## 快速开始

```bash
curl -fsSLO https://raw.githubusercontent.com/Claudedu-dev/ToastBox/main/toastbox.sh
sudo bash toastbox.sh
```

不带参数运行会进入交互菜单。部署成功后脚本会把自己安装为 `toastbox` 命令，之后直接用它管理节点：

```bash
sudo toastbox show
```

无人值守示例：

```bash
sudo bash toastbox.sh install -y \
  --core xray \
  --reality-sni www.example.com \
  --ss-port 28443
```

## 命令

| 命令 | 作用 |
| --- | --- |
| `install` | 部署节点；节点已存在时用来修改设置 |
| `show` | 显示连接信息、分享链接或客户端配置 |
| `update` | 升级内核并重启节点 |
| `rotate` | 重新生成 UUID、REALITY 密钥对、Short ID、Shadowsocks 密码和 Hysteria 2 认证/混淆密码（保留 TLS 证书） |
| `refresh-cert` | 从 `--hy2-cert` / `--hy2-key` 重新校验并导入证书材料；证书或私钥有变化时重载当前激活内核 |
| `uninstall` | 移除内核和节点；加 `--purge` 同时删除配置、日志和备份 |

### `install` 的选项

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `--core xray\|sing-box` | `xray` | 使用的内核 |
| `--protocols LIST` | `vless,ss` | `vless`、`ss`、`hy2`、`both`（`vless,ss`）、`all`（三者全部）或逗号组合 |
| `--server-addr ADDR` | 自动检测 | 客户端连接所用的 IP 或域名 |
| `--name NAME` | `ToastBox` | 分享链接里的节点名称 |
| `--listen ADDR` | 全部地址 | 绑定到指定的本机地址 |
| `--vless-port PORT` | `443` | VLESS 端口 |
| `--reality-sni DOMAIN` | 无，必填 | REALITY 目标域名 |
| `--reality-target HOST:PORT` | `<sni>:443` | REALITY 目标站 |
| `--skip-target-check` | | 不探测目标站 |
| `--ss-port PORT` | 随机 | Shadowsocks 端口 |
| `--ss-method METHOD` | `2022-blake3-aes-128-gcm` | 另可选 `2022-blake3-aes-256-gcm`、`2022-blake3-chacha20-poly1305` |
| `--ss-network both\|tcp\|udp` | `both` | Shadowsocks 监听的网络 |
| `--hy2-port PORT` | `443` | Hysteria 2 UDP 端口（可与 VLESS 或仅 TCP 的 SS 共用端口） |
| `--hy2-sni NAME` | 域名地址时自动取之 | Hysteria 2 TLS 证书验证名称（SNI） |
| `--hy2-tls self-signed\|files\|acme` | `self-signed` | 自签 ECDSA 证书、导入已有 PEM，或由 Certbot standalone 自动申请公共 CA 证书 |
| `--hy2-cert FILE` | | 导入证书链 PEM 文件（隐含 `--hy2-tls files`） |
| `--hy2-key FILE` | | 导入私钥 PEM 文件（需与 `--hy2-cert` 成对提供） |
| `--hy2-cert-hook certbot\|none` | `none` | 为已导入的 Certbot 证书安装/移除 `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh` 自动同步钩子 |
| `--hy2-acme-domain DOMAIN` | 域名地址或 `--hy2-sni` | Certbot `--standalone` 自动申请公共证书的域名（隐含 `--hy2-tls acme`） |
| `--hy2-acme-email EMAIL` | | Let's Encrypt / Certbot 账户邮箱（自动申请模式必填） |
| `--hy2-acme-agree-tos` | | 非交互自动申请时明确同意 CA 服务条款（仅 `-y` 不会跳过） |
| `--hy2-hop-ports LIST\|none` | `none` | 可选 Hysteria 2 UDP 端口跳跃范围（如 `20000-20100,30000`），或 `none` 清除 |
| `--hy2-hop-interval SEC\|MIN-MAX` | `30` | UDP 端口跳跃间隔秒数或范围（至少 `5` 秒） |
| `--hy2-obfs none\|salamander` | `none` | 可选 Salamander 混淆；开启时自动生成独立混淆密码 |
| `--hy2-masquerade none\|URL` | 无 | HTTP/3 反向代理伪装目标 URL，或 `none` 清除 |
| `--hy2-renew-cert` | | 显式重新签发自签 Hysteria 2 证书 |
| `--tcp-keepalive-idle SEC` | 不覆盖 | Xray TCP 保活空闲时间，1–32767 秒；`0` 清除该项 |
| `--tcp-keepalive-interval SEC` | 不覆盖 | Xray TCP 保活探测间隔，1–32767 秒；`0` 清除该项 |
| `--tcp-user-timeout MS` | 不覆盖 | Xray TCP 用户超时，1–2147483647 毫秒；`0` 清除该项 |
| `--reset-sockopt` | | 先清除已保存的 TCP 覆盖，再应用本次显式参数 |
| `--block-bt` | 关闭 | 拒绝 BitTorrent 流量 |
| `--allow-private` | 关闭 | 允许转发到私有 / 回环地址 |
| `--core-version VERSION` | 最新版 | 安装指定版本的内核 |
| `--no-firewall` | | 不修改 ufw（开启 `--hy2-hop-ports` 时仍会应用必需的端口跳跃 NAT 规则） |
| `--overwrite-config` | | 替换并非由 ToastBox 生成的现有配置；仅有 `-y` 不会替换 |

通用选项：`-y` / `--yes`（不提示）、`--lang en|zh`、`--help`。

### `show` 的输出格式

```bash
sudo toastbox show                          # 参数一览和分享链接
sudo toastbox show --qr                     # 同时显示二维码
sudo toastbox show --format links           # 只输出分享链接
sudo toastbox show --format xray            # 完整的 Xray 客户端配置
sudo toastbox show --format sing-box        # 完整的 sing-box 客户端配置
sudo toastbox show --format hysteria2       # 官方 Hysteria 2 客户端配置
sudo toastbox show --format json            # 机器可读（不含私钥）
sudo toastbox show --format xray --protocols hy2   # 只输出某个协议
```

客户端配置在本机 `127.0.0.1:1080` 开一个代理入口，可以直接保存后运行。

## 需要了解的几件事

### REALITY 目标站怎么选

REALITY 借用一个真实网站的 TLS 身份。未通过认证的连接会被原样转发到目标站，所以：

- 目标站要支持 TLS 1.3，最好也支持 HTTP/2。
- **不要选 Cloudflare 等 CDN 之后的站点**，否则你的服务器会变成该 CDN 的免费转发节点。
- 最好选与服务器位于同一网络（ASN）的站点。

脚本没有内置默认域名，需要你自己提供。部署前它会从服务器上实际握手一次，确认目标站支持 TLS 1.3 且证书对该域名有效；不通过时拒绝继续（`--skip-target-check` 可跳过）。

### Shadowsocks 2022 的定位是落地节点

Shadowsocks 没有 TLS 伪装，流量外观可以被识别。请把它放在中转或隧道之后作为落地使用，不要让它直接穿越审查防火墙。

Shadowsocks 2022 还要求两端时钟基本一致，系统未开启时间同步时脚本会给出警告。

### Hysteria 2 的 TLS 证书与更新

- **自签证书（`--hy2-tls self-signed`，默认）**：适合直接用 IP 部署。首次生成有效期 10 年的 ECDSA P-256 自签证书并包含对应 SAN；重复安装、`update` 和 `rotate` 均会保留证书（`rotate` 仅轮换认证与混淆密码）。官方 Hysteria 客户端采用 `insecure: true` + `pinSHA256` 固定证书指纹，Xray 客户端使用 `pinnedPeerCertSha256`，sing-box 客户端内嵌公开证书 PEM 验证。只有在显式传入 `--hy2-renew-cert`（或更改 `--server-addr` / `--hy2-sni` 使旧证书不再匹配）时才会重新签发自签证书。
- **导入已有证书（`--hy2-tls files`）**：通过 `--hy2-cert` 和 `--hy2-key` 导入由 ACME / certbot（例如已有 ToastWeb 部署签发的 `/etc/letsencrypt/live/<domain>/fullchain.pem` 与 `privkey.pem`）签发的证书链和私钥，客户端按系统 CA 验证。ToastBox 会保留传入的 `live` 符号链接路径而不展开到底层 `archive/...1.pem`，校验配对与有效期并在 `state.json` 与服务端配置中保存快照（ToastBox 本身不会修改 Certbot 或 ToastWeb 配置）。
  - 可同时启用 `--hy2-cert-hook certbot`（安装 `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh`），在对应证书谱系续期时自动执行 `toastbox refresh-cert`；外部工具续期后也可随时手动执行 `sudo toastbox refresh-cert`（或用 `--hy2-cert ... --hy2-key ...` 指定新路径）。若证书链或私钥未变化会跳过重载；发生变化时会重生成配置并重启当前激活的内核（因证书内嵌在服务端配置中，重载期间该内核上的活跃连接会短暂断开，不是无中断热加载）。
- **自动申请公共证书（`--hy2-tls acme`，无需 ToastWeb / Nginx）**：显式传入 `--hy2-tls acme`、`--hy2-acme-domain`（或域名 `--server-addr`）、`--hy2-acme-email` 与 `--hy2-acme-agree-tos` 后，ToastBox 会使用 `certbot certonly --standalone`（HTTP-01，仅申请/续期瞬间临时监听 TCP 80）为独立的 `toastbox-hy2-<domain>` 谱系申请 ECDSA 证书，并将产物接入 `files` 流程与部署钩子。
  - 需确保域名公网解析已指向当前服务器，且本机防火墙与云安全组均允许公网访问 TCP 80（ufw 启用且未传 `--no-firewall` 时会自动放行 `80/tcp`）。若 TCP 80 已被 Nginx / ToastWeb 等现有服务占用，脚本会直接报错而不会停止现有服务。
  - 若系统已有运行中的 `certbot.timer` / `snap.certbot.renew.timer` 会直接复用；否则创建限定该谱系的 `toastbox-hy2-certbot.timer`（`toastbox-hy2-certbot.service`）定时续期并经钩子触发 `refresh-cert`。重复安装会复用尚未临期的有效证书；关闭自动化或卸载时仅清理 ToastBox 自己的钩子和定时器，不删除共享 Certbot 定时器、账户及证书文件。

```bash
# 不依赖 ToastWeb，由 ToastBox 自动通过 Certbot standalone 申请与维护公共证书
sudo toastbox install -y \
  --core sing-box --protocols hy2 \
  --server-addr proxy.example.com \
  --hy2-tls acme \
  --hy2-acme-email admin@example.com \
  --hy2-acme-agree-tos
```

### Hysteria 2 UDP 端口跳跃

- 通过 `--hy2-hop-ports 20000-20100,30000` 和可选 `--hy2-hop-interval 30`（或 `15-45`，最少 `5` 秒）为 Hysteria 2 启用可选 UDP 端口跳跃；使用 `--hy2-hop-ports none` 可关闭并清理相关规则。
- Xray 和 sing-box 服务端继续只监听单个 `--hy2-port`（如 `443/udp`）；ToastBox 会在内核态通过 `PREROUTING` NAT（优先 `nftables`，回退 `iptables`/`ip6tables`）把跳跃范围的 UDP 流量重定向到该监听端口，并通过 `/usr/local/libexec/toastbox-hy2-hop`、`toastbox-hy2-hop.service` 以及对应内核服务 drop-in 在重启后自动生效。
- 云厂商安全组或外部防火墙必须同时放行 `--hy2-port` 和全部 `--hy2-hop-ports` UDP 端口；启用 ufw 时只需放行 NAT 后的实际监听端口 `--hy2-port`。
- 版本要求：服务端最低要求仍为 `Xray >= 26.7.11` / `sing-box >= 1.12.0`；启用端口跳跃后，导出配置对应的客户端需要 `Hysteria >= app/v2.14.0`、`Xray >= 26.11.9`（支持 `finalmask.udp` 的 `udphop`）或 `sing-box >= 1.11.0`（固定间隔，随机区间 `hop_interval_max` 需要 `sing-box >= 1.14.0`）。

```bash
# 复用已有 Certbot 证书（例如 ToastWeb 同机证书）+ 自动续期同步 + UDP 端口跳跃
sudo toastbox install -y \
  --core sing-box --protocols hy2 \
  --server-addr proxy.example.com \
  --hy2-cert /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --hy2-key /etc/letsencrypt/live/proxy.example.com/privkey.pem \
  --hy2-cert-hook certbot \
  --hy2-hop-ports 20000-20100,30000 --hy2-hop-interval 15-45
```

### 默认的安全设置

- 节点拒绝转发到以 IP 形式给出的回环、内网、链路本地（云厂商的元数据接口在这里）地址。这不是完整的隔离：一个解析到内网地址的域名不会被拦截。确实需要访问服务器内网时用 `--allow-private`。
- Xray 的访问日志默认关闭；sing-box 的日志级别为 `warn`。
- `--block-bt` 依赖流量嗅探。开启后，由服务端先发数据的协议（如 SSH、SMTP）在建立连接时会多等待一小段时间。
- 配置文件和状态文件含有私钥：Xray 配置为 `root:xray 0640`，sing-box 配置和 `state.json` 为 `root 0600`。

### TCP socket 参数持久化（Xray）

以下是可选设置，不是默认调优方案。要为已有 Xray 节点保存一组参数，可执行：

```bash
sudo toastbox install -y --no-firewall \
  --tcp-keepalive-idle 120 \
  --tcp-keepalive-interval 30 \
  --tcp-user-timeout 120000
```

参数保存到 `state.json` 的 `sockopt` 对象，之后 `install`（不再指定这些参数）、`update`、`rotate` 都会重放。修改设置本身不会更换凭据；`rotate` 仍会按原设计轮换凭据。

- 新节点及不含 `sockopt` 的旧状态均不添加覆盖，沿用内核 / 系统默认值；不会自动导入手改服务端 JSON 中的值，需用上述选项录入一次。
- 仅作用于 Xray 的 TCP 入站：VLESS-REALITY、SS TCP 或 TCP+UDP 中的 TCP 部分；SS 仅 UDP 时不生成该配置。不会修改出站、客户端配置或宿主机 `sysctl`。
- KeepAlive 的单位为秒，UserTimeout 为毫秒；`tcpUserTimeout` 仅 Linux 生效。脚本会拒绝负数、小数、非数字及超出范围的值。
- 只修改单项时，其他已保存项保持不变；将单项设为 `0` 可清除该覆盖。`--reset-sockopt` 清除全部，再应用同一命令中的显式参数，与参数顺序无关。
- sing-box 不接受这组 Xray 专用设置。已有自定义项时切换内核会被拒绝；确认不再需要后，可使用 `install --core sing-box --reset-sockopt` 显式清除并切换。
- 这组命令行选项仅用于 `install`；`update` / `rotate` 直接复用状态。`show` 会显示已保存的设置，不代表内核运行时探测。

### 防火墙

检测到 ufw 处于启用状态时，脚本会放行节点实际监听的端口（Hysteria 2 端口跳跃流量经 `PREROUTING` NAT 重定向，ufw 只需放行 `--hy2-port`），并在端口变更或卸载时移除它自己加的规则（不会动你手工加的规则）。`--no-firewall` 仅跳过 ufw 修改；启用 `--hy2-hop-ports` 时仍会应用必需的跳跃 NAT 规则。云厂商的安全组需要自行放行（含全部 `--hy2-hop-ports` UDP 端口）。

### 公网地址检测

未指定 `--server-addr` 时，脚本先看本机出口网卡地址；该地址是内网地址（NAT）时，会向 `cloudflare.com/cdn-cgi/trace` 和 `api.ipify.org` 查询公网 IP。

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `/etc/toastbox/state.json` | 节点的全部参数；分享链接和客户端配置都由它生成 |
| `/etc/toastbox/hy2-hop.json` | Hysteria 2 UDP 端口跳跃 NAT 运行时配置快照 |
| `/etc/toastbox/backup/` | 每次替换前的服务端配置备份，每个内核保留最近 5 份 |
| `/usr/local/etc/xray/config.json` | Xray 服务端配置 |
| `/etc/sing-box/config.json` | sing-box 服务端配置 |
| `/usr/local/bin/toastbox` | 脚本自身的副本 |
| `/usr/local/libexec/toastbox-hy2-hop` | 独立 UDP 端口跳跃 NAT helper 脚本 |
| `/etc/systemd/system/toastbox-hy2-hop.service` | 开机与随内核恢复端口跳跃 NAT 的 systemd 服务（及内核 service drop-in） |
| `/etc/systemd/system/toastbox-hy2-certbot.timer` | 无系统共享 Certbot 定时器时为独立 ACME 谱系创建的定时续期任务（含对应 `.service`） |
| `/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh` | Certbot 证书续期后自动调用 `refresh-cert` 的部署钩子（需 `--hy2-cert-hook certbot` 或 `acme`） |

sing-box 的服务会合并 `/etc/sing-box/` 下的所有 JSON 文件。该目录里若有其他配置文件，脚本会提示。

## 开发

源码在 `src/` 下分模块编写，仓库根目录的 `toastbox.sh` 是由它们合并生成的单文件发布版，不要直接编辑。

```bash
make build   # 由 src/ 生成 toastbox.sh
make lint    # shellcheck + shfmt
make test    # bats 单元测试（不触碰本机：apt、systemd、网络均被替换）
make check   # lint + test
```

| 路径 | 内容 |
| --- | --- |
| `src/main.sh` | 开发入口，运行时加载各模块 |
| `src/lib/00-core.sh` | 常量、日志、通用函数 |
| `src/lib/10-i18n.sh` | 中英文消息 |
| `src/lib/20-system.sh` | 系统检测、依赖、锁、交互提示、systemd |
| `src/lib/30-net.sh` | 校验、端口、公网地址、目标站探测、防火墙 |
| `src/lib/35-hy2-hop.sh` | Hysteria 2 UDP 端口跳跃规范化、NAT 与 systemd 管理 |
| `src/lib/40-state.sh` | 节点状态的读写与配置备份 |
| `src/lib/50-gen.sh` | 凭据的生成与校验 |
| `src/lib/55-tls.sh` | Hysteria 2 TLS 证书生成、导入、校验与指纹 |
| `src/lib/56-cert-hook.sh` | Certbot 路径解析、谱系匹配与部署钩子管理 |
| `src/lib/57-acme.sh` | Certbot standalone ACME 签发、前置校验与专属续期定时器管理 |
| `src/lib/60-xray.sh`、`61-singbox.sh` | 各内核的安装与服务端配置 |
| `src/lib/70-output.sh` | 分享链接、客户端配置、信息展示 |
| `src/lib/80-commands.sh` | 参数解析与各命令 |
| `tests/unit/` | 单元测试与带 mock 的完整流程测试 |
| `tests/e2e/run.sh` | 真机端到端测试，由 CI 在 Ubuntu 22.04 / 24.04 上对两种内核运行（含 Certbot 符号链接续期与隔离 `veth` 命名空间 UDP 端口跳跃实测） |

端到端测试会真实安装并清除内核，**只应在一次性的机器上运行**。CI 目前不覆盖 Debian 和 arm64。

## 许可证

[MIT](LICENSE) © ToastSail
