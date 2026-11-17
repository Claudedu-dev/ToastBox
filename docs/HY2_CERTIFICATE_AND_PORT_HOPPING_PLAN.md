# ToastBox：Hy2 证书复用与端口跳跃实施规划

编写日期：2026-11-17。用途：交给 Gemini 在当前 ToastBox 工作树上实施。本文件是规划，尚未实现下述新增命令和参数。

## 1. 执行目标与边界

完成两部分功能：

1. Hy2 复用 ToastWeb 的公共 CA 证书，记录证书来源，并在 Certbot 续期后同步到 Hy2。
2. Hy2 支持可选的 UDP 端口跳跃，包括服务器转发、客户端导出、重启恢复和关闭清理。

继续使用项目现有的 Xray/sing-box 两种内核，支持 VLESS、SS、Hy2 的现有协议组合。现有自签证书模式继续保留。

本次实施集中于 ToastBox。无需修改 ToastWeb、给其网站开启 HTTP/3，也不引入独立的官方 Hysteria 服务端、ACME 客户端、通用防火墙框架或长期驻留的管理进程。证书仍保存为 PEM 副本并内嵌到内核配置，沿用现有结构。

首版不新增“导入外部自签证书并选择独立信任模式”的功能：现有 self-signed 模式已经覆盖纯 IP 自签部署，ToastWeb 正式证书则适用于 files 模式。文件来源与信任方式分离，可作为后续独立扩展。

先完成代码、测试、文档和单文件构建，不对用户生产 VPS 执行部署、签证书或防火墙变更。

## 2. 已核对的项目基线

本地 HEAD 为 f929512，但工作树包含尚未提交的 Hy2 实现和此前修复。必须以执行时的当前工作树为基础；先查看 git status 和 git diff，保留已有修改，不 reset、checkout 覆盖或重新克隆后丢弃工作树。

| 文件/函数 | 当前职责及实施入口 |
|---|---|
| src/lib/00-core.sh | 路径、最低版本等常量 |
| src/lib/20-system.sh | 依赖安装、systemd 操作等系统辅助函数 |
| src/lib/30-net.sh | 端口检查与 UFW 管理，目前不配置跳跃 NAT |
| src/lib/40-state.sh | cfg_reset、state_json、state_load、state_save，当前 schema 为 1 |
| src/lib/55-tls.sh | 自签证书、PEM 导入、密钥配对、有效期、名称匹配、叶证书 SHA-256 |
| src/lib/60-xray.sh、61-singbox.sh | 服务端配置生成，Hy2 当前监听单个 UDP 端口 |
| src/lib/70-output.sh | hy2_link、三个客户端 JSON 导出、show 输出 |
| src/lib/80-commands.sh | 参数解析、resolve_hy2、apply_config、sync_firewall、安装/更新/轮换/卸载 |
| src/lib/10-i18n.sh | 中英文交互、帮助和错误信息 |
| scripts/build.sh | 从 src 生成 toastbox.sh，不应手工编辑构建产物 |
| tests/unit、tests/e2e/run.sh | Bats 单元测试与一次性 Linux 环境的真实内核测试 |

当前实现的重要行为：

- --hy2-tls self-signed 为默认模式，生成 ECDSA P-256 证书。三个客户端导出已经分别使用指纹或内嵌公开证书建立信任。
- --hy2-cert/--hy2-key 隐含 files 模式。导入的 PEM 被保存到 state 和服务端配置；之后更新原文件不会自动刷新副本。
- files 模式客户端按公共 CA 校验；保留 Xray 导出的 useSystemCA: true。
- apply_config 当前会重启相应内核，不是无中断热加载。
- --no-firewall 现有含义是“不修改 UFW”。
- 卸载非当前使用的旧内核会提前返回，保留当前节点。新增共享资源不能在这种卸载操作中被删除。

## 3. 官方依据与部署关系

核对时的稳定版本：官方 Hysteria app/v2.14.0、Xray v26.11.9、sing-box v1.14.4。开始实施时复核下列接口；如有变化，以对应版本的源码及真实配置校验为准，不能只依据文档中的旧示例。

ToastWeb 当前正式流程使用 Certbot 的 HTTP-01 申请 ECDSA 公共证书，默认文件为 /etc/letsencrypt/live/toastweb-<domain>/fullchain.pem 和 privkey.pem；其续期钩子仅 reload ToastWeb Nginx。[ToastWeb 证书申请与钩子源码](https://github.com/MerryToast/ToastWeb/blob/410aa6d4f33b83f1c12fdee5edf20ca2c715e118/toastweb.py#L1323)、[续期钩子](https://github.com/MerryToast/ToastWeb/blob/410aa6d4f33b83f1c12fdee5edf20ca2c715e118/toastweb.py#L413)

证书没有 HTTP/2 或 HTTP/3 专用版本；HTTP/3 的 QUIC/TLS/ALPN 能力由实际服务程序提供。ToastWeb 的 ECDSA 证书能供 Hy2 使用，网站无需开启 HTTP/3。[HTTP/3 标准](https://www.rfc-editor.org/rfc/rfc9114.html#section-3.2)、[Hy2 证书算法说明](https://v2.hysteria.network/docs/advanced/Full-Client-Config/#quic-parameters)

目标部署示例：

| 服务 | 地址/端口 | 说明 |
|---|---|---|
| ToastWeb | 127.0.0.1:8443/TCP | 默认网站 HTTPS/HTTP2，保留其现有配置 |
| VLESS + REALITY | 公网 443/TCP | 可继续使用上述网站作为本地 target |
| Hy2 | 公网 443/UDP | 使用同一对网站证书和私钥 |
| Hy2 跳跃入口 | 公网 20000-20100/UDP | 转发到 Hy2 的单端口监听 |

官方 Hy2 端口跳跃由客户端定期选择目标 UDP 端口；官方服务端的端口段监听实际上也通过防火墙转发实现。Xray/sing-box 不会自动继承官方程序的这段管理逻辑，需由 ToastBox 实现。[官方跳跃文档](https://v2.hysteria.network/docs/advanced/Port-Hopping/)、[官方服务端实现](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/app/cmd/server.go#L339)、[官方防火墙实现](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/app/internal/firewall/firewall_linux.go#L58)

## 4. 功能 A：公共证书复用与续期同步

### A1. 参数与状态

现有 --hy2-tls、--hy2-cert、--hy2-key、--hy2-sni 保持兼容。新增安装参数：

| 参数/命令 | 语义 |
|---|---|
| install --hy2-cert-hook certbot | 为当前 files 模式证书安装 ToastBox 自己的 Certbot deploy hook |
| install --hy2-cert-hook none | 显式取消本项目安装的证书钩子 |
| toastbox refresh-cert | 从 state 记录的来源路径刷新证书，无交互，不执行 ACME 签发 |

新节点默认不安装钩子；已有节点重装而未传该选项时保留原设置。self-signed 模式不允许启用 Certbot 钩子。--hy2-renew-cert 继续只负责重新生成 ToastBox 的自签证书，不能拿它续签公共证书。

在 hy2 下增加以下可选字段，保持 schema-1 加法兼容：

```json
{
  "cert_file": "/etc/letsencrypt/live/toastweb-docs.example.org/fullchain.pem",
  "key_file": "/etc/letsencrypt/live/toastweb-docs.example.org/privkey.pem",
  "certbot_hook": false
}
```

记录来源的稳定绝对路径。Certbot live 路径本身是符号链接，不能把它解析后保存成 archive/fullchain1.pem 等带版本号的文件路径。现有 cert、key、cert_sha256 字段继续保存当前已应用副本。

旧 files 状态没有来源路径时，原有 show/update/rotate 继续可用；refresh-cert 给出一次重新导入路径的明确提示，不猜测文件位置。切换回 self-signed 时清空外部来源和钩子设置，移除本项目钩子。

Certbot 钩子首版只支持标准 /etc/letsencrypt/live/<lineage>/fullchain.pem、privkey.pem 配对，且同一 lineage；普通 files 导入仍允许其他路径并支持手动 refresh-cert。

### A2. refresh-cert 的执行流程

1. 要求 root，加载已有状态，确认 Hy2 已开启且 tls=files，读取已登记路径；来源缺失、文件失效时明确失败。
2. 复用 55-tls.sh 的校验：有效期、证书/私钥匹配及当前 Hy2 SNI/地址名称匹配。
3. 比较完整证书链 PEM 和私钥内容。内容未变化则成功退出，不重启；不能仅凭叶证书指纹判断，因为中间证书链也可能变化。
4. 仅替换证书、私钥及对应指纹，不解析安装参数，不探测 REALITY target，不更新内核，不轮换密码，不改变协议、端口或跳跃设置。
5. 复用配置生成、内核校验、备份、应用及回滚能力。服务原本运行时才重启；服务已停止时只更新磁盘配置/state，保持停止状态。可为 apply_config 增加小型可选激活策略，避免复制一整套应用逻辑。
6. 应用成功才提交新状态。配置校验、重启或 state 写入失败时恢复旧的配置和状态；如果原来运行，尽力恢复原服务，并返回失败供 Certbot/journal 显示。

对 install/update/rotate/uninstall/refresh-cert 使用同一个简单的操作锁，避免自动续期与人工重配同时覆盖 state。可使用 flock；锁在 state 被删除后仍须有效，放在独立运行目录中。show 无需取得写锁。

由于证书内嵌，刷新将重启整个当前内核，同内核的 VLESS/SS 连接也可能短暂中断。README 必须如实说明；不承诺无中断热更新。

### A3. Certbot 钩子

建议路径：/etc/letsencrypt/renewal-hooks/deploy/toastbox-hy2.sh。

钩子具有项目所有权标记，只为 state 登记的 lineage 工作，通过 RENEWED_LINEAGE 匹配后调用已安装的 toastbox refresh-cert。不要覆盖或串改 ToastWeb 的 toastweb.sh 钩子，也不要修改共享 Certbot 定时器。

不相关 lineage 成功跳过；目标 lineage 的真实刷新失败返回非零并留下简明错误。缺少节点状态或节点已关闭 Hy2 时成功跳过，避免历史钩子影响其他证书。

钩子调用的是持久存在的管理入口，不能引用下载临时目录或开发目录。当前 self_install 在源码模式和管道模式可能跳过安装，因此启用钩子前必须确保可调用的单文件 toastbox 已正确安装；可复用构建安装入口，或明确提示先安装单文件版本。

关闭钩子、切换到 self-signed、关闭 Hy2、卸载当前节点时，清理本项目拥有的钩子。证书和私钥仍归 Certbot/ToastWeb 管理，不删除、不改权限。

### A4. 证书与客户端导出约束

files 模式继续正常验证公共 CA，不添加 insecure 或固定叶证书指纹；域名和信任链正常时，例行续期不要求更新客户端配置。

self-signed 模式保持现有三种信任导出：官方客户端 insecure+pinSHA256、Xray pinnedPeerCertSha256、sing-box 内嵌公开证书。不要把证书私钥带到客户端 JSON、分享链接或普通 show 输出中。

## 5. 功能 B：UDP 端口跳跃

### B1. 参数与持久化

| 参数 | 输入及语义 |
|---|---|
| --hy2-hop-ports '20000-20100' | 开启跳跃 |
| --hy2-hop-ports '20000-20100,30000,31000-31100' | 多区间/单端口组合 |
| --hy2-hop-ports none | 显式关闭 |
| --hy2-hop-interval 30 | 固定 30 秒；初次开启默认值 |
| --hy2-hop-interval 15-45 | 每跳使用 15-45 秒内的随机间隔 |

上述参数用于 install。新节点默认关闭，重装未传参时保留旧配置；update、rotate、证书刷新均保留跳跃状态。传入跳跃参数但本次未启用 Hy2 时，给出参数不适用的错误。Hy2 关闭时撤销生效的转发及钩子，清空两项自动化功能的启用状态，避免之后无提示重新启用。

端口集合统一规范化，处理排序、重叠及重复；每个端口必须为 1-65535，区间下限不大于上限。开启跳跃时至少有两个不同端口。检查已配置和实际占用的 UDP 服务冲突，特别是 SS UDP；同数字 TCP 端口不视为冲突。

固定/随机间隔只接受整数秒，下限至少 5 秒，随机下限不得大于上限。使用有长度和数值上限的整数解析，建议上限为 2147483647 秒以匹配 Xray Int32Range；不增加其他无依据的产品限制。[官方间隔校验](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/extras/transport/udphop/conn.go#L107)

状态示例，嵌入现有 hy2 对象：

```json
{
  "hop": {
    "ports": "20000-20100",
    "interval_min": 30,
    "interval_max": 30
  }
}
```

ports 为空表示关闭，不再增加重复的 enabled 开关。旧状态缺少 hop 时读取为空端口集合及 30/30 默认间隔；已存在但不合法的字段在写入配置/规则前报错。

--hy2-port 始终是服务端真正监听的单个 UDP 端口。跳跃集合可以包含它，也可完全使用另外的端口段；包含时无需给这个监听端口自身建立重复转发。

### B2. 服务器转发

建议新增 src/lib/35-hy2-hop.sh，封装以下有限职责：端口集合规范化、规则生成/应用/移除、自有 systemd 资源管理。服务端 60-xray.sh/61-singbox.sh 继续保持单端口 Hy2 inbound，不给服务器添加客户端的 udphop mask。

优先 nftables；缺少时使用 iptables/ip6tables。启用时检查所需命令及对应 IP 栈能力，缺依赖或安装规则失败应明确报错，不把配置成功当作跳跃已可用。关闭跳跃时不引入此依赖。

只给本机目标地址的入站 UDP 建立 PREROUTING 转发，按 listen 地址选择 REDIRECT 或明确地址的 DNAT；不重定向发往远端的流量，不增加全局 OUTPUT 规则，也不修改 ip_forward/route_localnet 等全局开关。仅回环监听不作为公网跳跃支持方式。IPv4 和已启用的 IPv6 都要覆盖。[官方对本机目标的匹配与后端实现](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/app/internal/firewall/firewall_linux.go#L86)

使用 ToastBox 专属表/链及标记，例如 nft 表 toastbox_hy2 或 iptables 链 TOASTBOX-HY2。重复应用不产生重复规则，更新时只替换自己的规则。不要 flush 系统规则集或其他项目的表/链。

保留 --no-firewall 当前“跳过 UFW 修改”的含义；显式启用 --hy2-hop-ports 仍会配置必需的 NAT，CLI 帮助、交互安装计划和 README 都要写明这一点。UFW 需要允许 NAT 后实际进入 INPUT 的 Hy2 监听端口；在真实 UFW 环境验收，不仅添加跳跃端口段的 allow 就认为完成。

安装结果明确输出云厂商安全组需放行的 UDP 端口集合；ToastBox 不调用云 API。第一版不增加手工 NAT 模式或第三方防火墙管理适配层。

### B3. 重启恢复与失败恢复

使用独立的 ToastBox systemd oneshot 单元管理规则恢复，配合当前内核的自有 drop-in 确保转发生效后启动内核。建议资源如下，名称可根据项目约定微调，但职责保持一致：

| 资源 | 职责 |
|---|---|
| /usr/local/libexec/toastbox-hy2-hop | 生成的持久辅助脚本，支持 apply/remove，复用模块逻辑，不能依赖源码目录 |
| /etc/toastbox/hy2-hop.json | 当前规则参数，只包含后端、监听地址/端口和规范化端口集合，不复制认证凭据或证书私钥 |
| toastbox-hy2-hop.service | oneshot，RemainAfterExit，ExecStart 应用规则，ExecStop 移除自有规则 |
| 当前内核的专属 drop-in | 管理顺序及依赖；切换内核时更新，移除旧内核的本项目 drop-in |

规则恢复顺序应考虑已有 ufw/nftables 服务，避免开机后被其常规加载覆盖。无需为管理员任意手工刷新防火墙实现额外守护进程。

安装中先验证新配置并准备候选规则参数，再应用内核和规则，全部成功后提交状态。围绕本项目的旧配置、规则参数和 unit/drop-in 做有限备份恢复即可，不建设通用事务系统。需明确处理：

- NAT 建立部分失败，不能遗留半套新规则并报告成功。
- 内核启动失败或状态保存失败，恢复此前可用的配置及转发参数。
- 单独停止当前内核时不把它自动重新拉起；通过合适的 systemd 生命周期关联协调规则停止与下次启动。
- 修改监听端口、跳跃集合或 listen 地址后，旧规则应被替换。
- 关闭跳跃/Hy2、卸载当前节点时清理自己的 unit、drop-in、辅助脚本、规则及参数文件。
- 仅卸载一个非当前使用的旧内核时保留当前节点的跳跃资源和证书钩子。

### B4. 客户端 JSON 与链接

全部导出从 state 中同一组规范化参数生成；关闭跳跃时保持原单端口输出。

| 导出 | 固定间隔 | 随机间隔 |
|---|---|---|
| 官方 Hysteria | server 使用域名:端口集合；transport.udp.hopInterval 为 30s | 改用 minHopInterval/maxHopInterval，不能同时带 hopInterval |
| sing-box | server_ports 使用 ["20000:20100"]；hop_interval 为 30s | hop_interval 取下限，hop_interval_max 取上限 |
| Xray | finalmask.udp 的 udphop；interval 为 "30" | interval 为 "15-45" |

sing-box 开启跳跃时输出 server_ports 并省略 server_port；保留 server 地址和 TLS SNI。注意它的区间分隔符是冒号，需要逐段转换。固定跳跃自 1.11 支持，随机 hop_interval_max 自 1.14 支持。[sing-box 官方配置](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)、[v1.14.4 选项定义](https://github.com/SagerNet/sing-box/blob/v1.14.4/option/hysteria2.go)

Xray 客户端使用已核对的 v26.11.9 格式：

```json
{
  "finalmask": {
    "udp": [
      {
        "type": "udphop",
        "settings": {
          "mode": "intervallocal,intervalremote",
          "interval": "30",
          "remotePorts": "20000-20100"
        }
      }
    ]
  }
}
```

remoteIPs 省略，继承上层服务器地址。开启 Salamander 时，UDP mask 数组应为 [salamander, udphop]，其中 udphop 为最后一项；不要生成两次 finalmask 互相覆盖。源码会逆序处理 mask，udphop 的 HandleDial 要处于处理序列首位。需要真实互通验证这个组合。[Xray 配置解析](https://github.com/XTLS/Xray-core/blob/v26.11.9/infra/conf/transport_finalmask.go)、[包装顺序](https://github.com/XTLS/Xray-core/blob/v26.11.9/transport/internet/finalmask/finalmask.go#L44)、[udphop 仅支持客户端](https://github.com/XTLS/Xray-core/blob/v26.11.9/transport/internet/finalmask/udphop/config.go)

文档中残留的 hysteriaSettings.udphop、finalmask.quicParams.udpHop 示例不能直接用于新版；以对应版本源码为准。本次新跳跃 Xray 客户端导出以 v26.11.9 为支持/验收基线，不增加旧字段兼容分支。[Xray 官方文档](https://xtls.github.io/config/transports/finalmask.html#udphop)

版本要求针对接收导出配置的客户端。服务端仍是单端口监听，维持原 Xray 26.7.11、sing-box 1.12.0 最低要求；不能仅因客户端导出有跳跃字段而强制升级服务端。随机跳跃的 sing-box 客户端需要 1.14+。官方客户端按 app/v2.14.0 验收；不要猜测该随机参数更早版本的最低支持版本。

在 README 和文本 show 中提示客户端要求。JSON/links 标准输出保持机器可解析，任何额外提示放 stderr 或独立文本说明；不向内核 JSON 塞自定义注释字段。

分享链接使用官方多端口语法，保留原有 auth、SNI、证书信任、obfs 及名称编码：

```text
hysteria2://PASSWORD@docs.example.org:20000-20100/?sni=docs.example.org#ToastBox
```

IPv6 地址继续使用方括号。端口集合不能按单整数解析，也不要被百分号编码成客户端无法识别的端口部分。官方 URI 未统一规定跳跃间隔参数，首版不添加私有扩展；完整 JSON 包含间隔，链接导入后的间隔遵循客户端设置。对实际常用 GUI 做导入验证，不承诺所有客户端解析器都支持该语法。[官方 URI 规范](https://v2.hysteria.network/docs/developers/URI-Scheme/)

## 6. 实施顺序与文件分工

| 顺序 | 工作 | 主要文件 |
|---|---|---|
| 1 | 复核工作树、官方字段、现有测试；确认已有 Hy2 修复仍在 | git diff、相关源码、tests |
| 2 | 新状态字段、参数规范化和兼容加载 | 40-state.sh、80-commands.sh、10-i18n.sh |
| 3 | 公共证书来源记录、refresh-cert、Certbot 钩子、必要操作锁 | 55-tls.sh、80-commands.sh；可新增 56-cert-hook.sh；20-system.sh |
| 4 | 跳跃规则生成及 systemd 管理，接入安装/卸载/回滚 | 新增 35-hy2-hop.sh、30-net.sh、80-commands.sh、00-core.sh |
| 5 | 三种客户端 JSON、链接、文本展示及版本说明 | 70-output.sh、10-i18n.sh |
| 6 | 有针对性的单元和 Linux 互通测试，更新中英文文档 | tests/unit、tests/e2e、README.md、README.en.md |
| 7 | 格式化、重新生成单文件、运行检查、复核最终 diff | scripts/build.sh、toastbox.sh、Makefile |

文件名属于建议；以小模块和现有函数复用为主。仅在功能实际需要时修改服务端生成器，避免连带重构 VLESS、SS、REALITY 或整套错误处理。

## 7. 验收标准

### 7.1 单元测试

覆盖与本次功能直接相关的行为，复用现有 Bats/mock 结构：

- 旧 state 加载后功能默认关闭；显式参数、未传参数、none 的持久化行为正确；无关配置和认证信息不被清空。
- 普通 files 导入记录稳定来源；Certbot live 路径不会被保存为 archive 版本路径。
- refresh-cert 内容相同不重启，变化后更新完整链与私钥；参数、证书无效或应用失败时旧状态保留；停止的服务保持停止。
- 钩子仅处理匹配 lineage；启用/禁用/重装/卸载幂等，ToastWeb 钩子和共享证书文件不受影响。
- 跳跃端口集合的正常输入、边界、重复合并、无效区间；固定及随机间隔映射；UDP 冲突与 TCP 同号共存。
- 三种客户端导出开/关跳跃、固定/随机、有/无 Salamander；Xray 的 finalmask 合并顺序；URI IPv4/IPv6 和特殊字符。
- 转发后端选择、双栈生成、重复应用、切换配置、部分失败恢复；关闭及卸载仅清理自己的资源。
- --no-firewall 跳过 UFW，但明确开启的 NAT 仍执行；卸载非当前内核保留共享资源。

### 7.2 真实 Linux 验收

真实 NAT/systemd 测试只在一次性 Debian/Ubuntu 环境或 CI 执行。现有 tests/e2e/run.sh 会安装和卸载真实内核，不在用户日常主机上运行。

1. 使用临时测试 CA 签发服务器证书，客户端正常校验，验证 files 模式；测试 CA 不冒充公共 CA 实测，不申请真实生产证书。
2. 模拟 Certbot live 链接由第一版切换到第二版，再调用部署钩子；核对 Hy2 实际在服证书已更换，认证、协议及跳跃设置保持。不会仅凭 state 指纹认定刷新成功。
3. 使用独立网络命名空间/veth 或隔离 VM 发起流量，确保走入站 PREROUTING。只有本机回环连接无法证明本规划的 NAT 路径有效。
4. 两个服务端内核分别与官方 Hysteria、Xray、sing-box 客户端互通；有/无 Salamander 共 12 个基础组合，持续 TCP 传输和 UDP 请求跨越多次跳跃。
5. 使用较小端口集合与 5 秒间隔缩短测试，至少运行跨越 3 次跳跃周期，抓包或规则计数结合客户端流量确认多个入口端口确实被使用。随机抽样可能重复，测试应留出合理重试余量。
6. 两种 NAT 后端至少各有实际覆盖，验证 IPv4、可用的 IPv6，以及启用 UFW 时的真实转发路径；环境不具备的项目明确记录未验证，不用 mock 结果替代。
7. 验证规则重新应用、systemd 停启、切换内核、修改端口段、关闭跳跃、关闭 Hy2和卸载；确认其他项目规则仍存在。实际 OS 重启可在隔离 VM 补测，未执行时如实说明。
8. 原 VLESS/SS 回归及现有自签 Hy2 用例继续通过；不能通过关闭身份验证使证书测试通过。

### 7.3 构建与交付

在具备工具的 Linux/Git Bash 环境按项目习惯运行：

```bash
make fmt
make build
make check
```

根据环境单独执行 Linux E2E。构建后的 toastbox.sh 必须与 src 一致。最终说明已运行的检查、真实互通结果和未验证项；不把规划或生成配置等同于已完成真实网络验证。

## 8. 实现后的目标用法

下列新增命令/参数需要完成实现后才能使用。示例中的域名需替换，协议列表按节点实际需求选择。

```bash
# 复用 ToastWeb 证书，开启续期同步和固定间隔跳跃。
sudo toastbox install -y \
  --protocols vless,hy2 \
  --hy2-port 443 \
  --hy2-tls files \
  --hy2-sni docs.example.org \
  --hy2-cert /etc/letsencrypt/live/toastweb-docs.example.org/fullchain.pem \
  --hy2-key /etc/letsencrypt/live/toastweb-docs.example.org/privkey.pem \
  --hy2-cert-hook certbot \
  --hy2-hop-ports '20000-20100' \
  --hy2-hop-interval 30

# 从已登记的来源手动刷新；没有变化就不重启。
sudo toastbox refresh-cert

# 改为随机间隔，保留其他已有设置。
sudo toastbox install -y --hy2-hop-interval 15-45

# 分别关闭跳跃或证书钩子。
sudo toastbox install -y --hy2-hop-ports none
sudo toastbox install -y --hy2-cert-hook none
```

## 9. 可直接交给 Gemini 的执行指令

请阅读本文件并在当前 ToastBox 工作树实施两项功能：ToastWeb 公共证书复用及 Certbot 续期同步、Hy2 UDP 端口跳跃。先核对当前源码和官方版本接口，再按第 6 节顺序完成代码、测试、中英文文档和单文件构建。当前工作树已有尚未提交的 Hy2 实现及修复，必须保留；不要重置或覆盖。沿用 Xray/sing-box，不切换官方独立服务端，不修改 ToastWeb 或为网站开启 HTTP/3。优先复用现有模块，只处理与这两项功能直接相关的实际问题，不扩大为通用证书平台或防火墙重构。正常技术细节自行确定并落实；若官方接口有实质变化，先核实并在交付说明中记录调整理由。完成后报告修改、检查结果和仍需真实 Linux/客户端验证的项目。不要提交、推送或部署到用户生产环境，除非用户另行要求。
