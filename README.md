# ToastBox

简体中文 | [English](README.en.md)

在 Debian / Ubuntu 上一条命令部署 **VLESS-TCP-REALITY-Vision** 和 **Shadowsocks 2022** 节点，内核可选 [Xray](https://github.com/XTLS/Xray-core) 或 [sing-box](https://github.com/SagerNet/sing-box)。

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
| `rotate` | 重新生成 UUID、REALITY 密钥对、Short ID 和 Shadowsocks 密码 |
| `uninstall` | 移除内核和节点；加 `--purge` 同时删除配置、日志和备份 |

### `install` 的选项

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `--core xray\|sing-box` | `xray` | 使用的内核 |
| `--protocols LIST` | `vless,ss` | `vless`、`ss` 或 `vless,ss` |
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
| `--tcp-keepalive-idle SEC` | 不覆盖 | Xray TCP 保活空闲时间，1–32767 秒；`0` 清除该项 |
| `--tcp-keepalive-interval SEC` | 不覆盖 | Xray TCP 保活探测间隔，1–32767 秒；`0` 清除该项 |
| `--tcp-user-timeout MS` | 不覆盖 | Xray TCP 用户超时，1–2147483647 毫秒；`0` 清除该项 |
| `--reset-sockopt` | | 先清除已保存的 TCP 覆盖，再应用本次显式参数 |
| `--block-bt` | 关闭 | 拒绝 BitTorrent 流量 |
| `--allow-private` | 关闭 | 允许转发到私有 / 回环地址 |
| `--core-version VERSION` | 最新版 | 安装指定版本的内核 |
| `--no-firewall` | | 不修改 ufw |
| `--overwrite-config` | | 替换并非由 ToastBox 生成的现有配置；仅有 `-y` 不会替换 |

通用选项：`-y` / `--yes`（不提示）、`--lang en|zh`、`--help`。

### `show` 的输出格式

```bash
sudo toastbox show                          # 参数一览和分享链接
sudo toastbox show --qr                     # 同时显示二维码
sudo toastbox show --format links           # 只输出分享链接
sudo toastbox show --format xray            # 完整的 Xray 客户端配置
sudo toastbox show --format sing-box        # 完整的 sing-box 客户端配置
sudo toastbox show --format json            # 机器可读（不含 REALITY 私钥）
sudo toastbox show --format xray --protocols ss   # 只输出某个协议
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

检测到 ufw 处于启用状态时，脚本会放行节点用到的端口，并在端口变更或卸载时移除它自己加的规则（不会动你手工加的规则）。云厂商的安全组需要自行放行。

### 公网地址检测

未指定 `--server-addr` 时，脚本先看本机出口网卡地址；该地址是内网地址（NAT）时，会向 `cloudflare.com/cdn-cgi/trace` 和 `api.ipify.org` 查询公网 IP。

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `/etc/toastbox/state.json` | 节点的全部参数；分享链接和客户端配置都由它生成 |
| `/etc/toastbox/backup/` | 每次替换前的服务端配置备份，每个内核保留最近 5 份 |
| `/usr/local/etc/xray/config.json` | Xray 服务端配置 |
| `/etc/sing-box/config.json` | sing-box 服务端配置 |
| `/usr/local/bin/toastbox` | 脚本自身的副本 |

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
| `src/lib/20-system.sh` | 系统检测、依赖、交互提示、systemd |
| `src/lib/30-net.sh` | 校验、端口、公网地址、目标站探测、防火墙 |
| `src/lib/40-state.sh` | 节点状态的读写与配置备份 |
| `src/lib/50-gen.sh` | 凭据的生成与校验 |
| `src/lib/60-xray.sh`、`61-singbox.sh` | 各内核的安装与服务端配置 |
| `src/lib/70-output.sh` | 分享链接、客户端配置、信息展示 |
| `src/lib/80-commands.sh` | 参数解析与各命令 |
| `tests/unit/` | 单元测试与带 mock 的完整流程测试 |
| `tests/e2e/run.sh` | 真机端到端测试，由 CI 在 Ubuntu 22.04 / 24.04 上对两种内核运行 |

端到端测试会真实安装并清除内核，**只应在一次性的机器上运行**。CI 目前不覆盖 Debian 和 arm64。

## 许可证

[MIT](LICENSE) © ToastSail
