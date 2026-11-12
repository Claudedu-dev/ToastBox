# shellcheck shell=bash
#
# Bilingual messages (English / 简体中文).
#
# Every message is a printf format string, so a literal percent sign must
# be written as %%. tests/unit/i18n.bats checks that both tables carry the
# same keys and that every key used in the code exists.

# -g: the tables must stay global even when this file is sourced from
# inside a function (as the test-suite does).
declare -gA TB_MSG_EN=()
declare -gA TB_MSG_ZH=()

TB_LANG_EXPLICIT=0

# msg KEY [ARGS...]
msg() {
  local key="$1" fmt=""
  shift
  if [[ "$TB_LANG" == "zh" ]]; then
    fmt="${TB_MSG_ZH[$key]:-}"
  fi
  if [[ -z "$fmt" ]]; then
    fmt="${TB_MSG_EN[$key]:-$key}"
  fi
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
}

# Language: --lang, then TOASTBOX_LANG, then the locale. Runs before the
# real argument parsing so that parse errors are already localized.
tb_init_lang() {
  local lang="" arg prev=""
  for arg in "$@"; do
    if [[ "$arg" == --lang=* ]]; then
      lang="${arg#*=}"
    elif [[ "$prev" == "--lang" ]]; then
      lang="$arg"
    fi
    prev="$arg"
  done
  [[ -n "$lang" ]] || lang="${TOASTBOX_LANG:-}"

  TB_LANG_EXPLICIT=1
  case "$lang" in
    zh | zh[_-]* | cn) TB_LANG="zh" ;;
    en | en[_-]*) TB_LANG="en" ;;
    "")
      TB_LANG_EXPLICIT=0
      case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        zh*) TB_LANG="zh" ;;
        *) TB_LANG="en" ;;
      esac
      ;;
    *)
      TB_LANG="en"
      die err_invalid_option --lang "$lang"
      ;;
  esac
}

# Asked once at the top of the interactive menu: SSH sessions rarely carry
# a locale that says anything about the person typing.
tb_choose_lang() {
  local reply default="1"
  [[ "$TB_LANG_EXPLICIT" == "1" ]] && return 0
  [[ "$TB_LANG" == "zh" ]] && default="2"
  reply="$(tb_readline "Language / 语言: 1) English  2) 中文 [$default]: ")"
  case "${reply:-$default}" in
    2 | zh | 中文) TB_LANG="zh" ;;
    *) TB_LANG="en" ;;
  esac
}

# ---------------------------------------------------------------------------
# English
# ---------------------------------------------------------------------------

TB_MSG_EN[err_root]='This command must be run as root (try: sudo bash toastbox.sh ...).'
TB_MSG_EN[err_os_version]='%s %s is not supported. %s %s or newer is required.'
TB_MSG_EN[err_os_unsupported]='Unsupported system "%s". ToastBox supports Debian 11+ and Ubuntu 20.04+.'
TB_MSG_EN[warn_os_derivative]='"%s" is a Debian/Ubuntu derivative. It is not tested, continuing anyway.'
TB_MSG_EN[err_arch_unsupported]='Unsupported CPU architecture "%s". Only amd64 and arm64 are supported.'
TB_MSG_EN[err_no_systemd]='systemd is required but is not running on this host.'
TB_MSG_EN[info_install_deps]='Installing required packages: %s'
TB_MSG_EN[err_apt_update]='apt-get update failed.'
TB_MSG_EN[err_apt_install]='Failed to install: %s'
TB_MSG_EN[err_download]='Download failed: %s'
TB_MSG_EN[err_state_corrupt]='The state file %s is unreadable or damaged.'
TB_MSG_EN[err_no_state]='No ToastBox node found on this host. Run "install" first.'
TB_MSG_EN[err_keypair]='Could not generate a REALITY key pair with %s.'
TB_MSG_EN[err_core]='Unknown core "%s". Use xray or sing-box.'
TB_MSG_EN[err_missing_value]='Option %s needs a value.'
TB_MSG_EN[err_unknown_arg]='Unknown argument: %s (see --help).'
TB_MSG_EN[err_invalid_option]='Invalid value for %s: "%s"'
TB_MSG_EN[err_invalid_value]='Invalid value: "%s"'
TB_MSG_EN[warn_invalid_input]='"%s" is not valid, please try again.'
TB_MSG_EN[err_protocols]='Invalid protocol list "%s". Use vless, ss or vless,ss.'
TB_MSG_EN[err_protocol_disabled]='Protocol "%s" is not enabled on this node.'
TB_MSG_EN[err_format]='Unknown format "%s". Use text, links, json, xray or sing-box.'
TB_MSG_EN[err_aborted]='Aborted. Nothing was changed. (Use --yes to confirm without a prompt.)'

TB_MSG_EN[prompt_core]='Core: 1) xray  2) sing-box'
TB_MSG_EN[prompt_protocols]='Protocols: 1) both  2) VLESS-REALITY-Vision only  3) Shadowsocks 2022 only'
TB_MSG_EN[info_detect_addr]='Detecting the public address of this server...'
TB_MSG_EN[err_server_addr_required]='Could not detect the public address. Pass it with --server-addr.'
TB_MSG_EN[prompt_server_addr]='Address clients connect to (IP or domain)'
TB_MSG_EN[prompt_vless_port]='VLESS port'
TB_MSG_EN[help_reality_sni]='
REALITY borrows the TLS identity of a real website (the "target").
Choose a site that:
  - supports TLS 1.3 and HTTP/2;
  - is NOT behind a CDN such as Cloudflare: connections that fail REALITY
    authentication are forwarded to the target, so a CDN target turns this
    server into a free relay for that CDN;
  - ideally is hosted in the same network (ASN) as this server.
'
TB_MSG_EN[prompt_reality_sni]='REALITY target domain (SNI), e.g. www.example.com'
TB_MSG_EN[err_sni_required]='A REALITY target domain is required. Pass it with --reality-sni.'
TB_MSG_EN[info_probing_target]='Probing REALITY target %s (SNI %s)...'
TB_MSG_EN[ok_target]='%s speaks TLS 1.3 and presents a valid certificate.'
TB_MSG_EN[warn_target_no_h2]='%s did not negotiate HTTP/2. It works, but an HTTP/2 site blends in better.'
TB_MSG_EN[err_target_unreachable]='Could not connect to %s from this server.'
TB_MSG_EN[err_target_no_tls13]='%s does not support TLS 1.3, which REALITY requires.'
TB_MSG_EN[err_target_cert]='The certificate of %s is not valid for %s.'
TB_MSG_EN[prompt_target_anyway]='Use this target anyway?'
TB_MSG_EN[err_target_rejected]='The REALITY target was rejected. Choose another one, or pass --skip-target-check to skip the probe.'
TB_MSG_EN[prompt_ss_port]='Shadowsocks port'
TB_MSG_EN[prompt_ss_method]='Shadowsocks method: 1) 2022-blake3-aes-128-gcm  2) 2022-blake3-aes-256-gcm  3) 2022-blake3-chacha20-poly1305'
TB_MSG_EN[err_no_free_port]='Could not find a free port. Pass one with --ss-port.'
TB_MSG_EN[err_port_same]='VLESS and Shadowsocks cannot both listen on TCP port %s.'
TB_MSG_EN[err_port_in_use]='Port %s is already in use by: %s'
TB_MSG_EN[plan_title]='About to deploy:'
TB_MSG_EN[prompt_proceed]='Proceed?'

TB_MSG_EN[warn_core_switch]='Switching core from %s to %s. The %s service is stopped and disabled once the new core is ready.'
TB_MSG_EN[prompt_overwrite_config]='%s already holds a configuration that ToastBox did not write. Replace it? (A backup is kept.)'
TB_MSG_EN[err_foreign_config]='Kept the existing configuration %s. Re-run with --yes to replace it.'
TB_MSG_EN[info_installing_core]='Installing %s from its official source...'
TB_MSG_EN[err_core_install]='Installing %s failed.'
TB_MSG_EN[err_core_too_old]='%s %s is too old: ToastBox needs %s or newer. Run "update" to upgrade it.'
TB_MSG_EN[ok_core_ready]='%s %s is installed.'
TB_MSG_EN[err_render]='Could not generate the configuration.'
TB_MSG_EN[err_validate]='%s rejected the generated configuration. Nothing was changed.'
TB_MSG_EN[info_restarting]='Restarting %s...'
TB_MSG_EN[ok_service_running]='%s is running.'
TB_MSG_EN[err_service_start]='%s failed to start with the new configuration. Recent log:'
TB_MSG_EN[warn_rolled_back]='Restored the previous configuration from %s.'
TB_MSG_EN[warn_service_stopped]='%s was not running before this change and has been left stopped.'
TB_MSG_EN[warn_old_core_restored]='Started the previous %s service again.'
TB_MSG_EN[err_apply]='The configuration was not applied.'
TB_MSG_EN[info_fw_opened]='Firewall (ufw): allowed %s'
TB_MSG_EN[info_fw_closed]='Firewall (ufw): removed rule %s'
TB_MSG_EN[warn_extra_configs]='sing-box merges every JSON file in its configuration directory. These files are also loaded: %s'
TB_MSG_EN[warn_clock]='The system clock is not NTP-synchronized. Shadowsocks 2022 rejects clients when the clocks differ too much; enable time sync (e.g. timedatectl set-ntp true).'
TB_MSG_EN[ok_installed]='The node is deployed.'
TB_MSG_EN[ok_self_installed]='Installed this script as %s; manage the node later with "toastbox <command>".'
TB_MSG_EN[ok_updated]='%s is now at version %s.'
TB_MSG_EN[prompt_rotate]='Generate new credentials? Every existing client will stop working until it is reconfigured.'
TB_MSG_EN[ok_rotated]='New credentials are active.'
TB_MSG_EN[prompt_uninstall]='Remove %s and this node? (Configuration files are kept.)'
TB_MSG_EN[prompt_uninstall_purge]='Remove %s, this node and ALL of its configuration, logs and backups?'
TB_MSG_EN[warn_remove_failed]='Removing %s reported an error; check the output above.'
TB_MSG_EN[ok_uninstalled]='%s and the ToastBox node were removed.'
TB_MSG_EN[ok_core_removed]='%s was removed. The node on %s is untouched.'
TB_MSG_EN[warn_no_qrencode]='qrencode is not available, skipping the QR code.'

TB_MSG_EN[word_running]='running'
TB_MSG_EN[word_stopped]='not running'
TB_MSG_EN[label_core]='Core'
TB_MSG_EN[label_server]='Server address'
TB_MSG_EN[label_config]='Server config'
TB_MSG_EN[label_port]='Port'
TB_MSG_EN[label_uuid]='UUID'
TB_MSG_EN[label_flow]='Flow'
TB_MSG_EN[label_sni]='SNI'
TB_MSG_EN[label_target]='Target'
TB_MSG_EN[label_public_key]='Public key (password)'
TB_MSG_EN[label_short_id]='Short ID'
TB_MSG_EN[label_fingerprint]='Fingerprint'
TB_MSG_EN[label_method]='Method'
TB_MSG_EN[label_password]='Password'
TB_MSG_EN[label_link]='Share link:'
TB_MSG_EN[note_ss_landing]='Note: Shadowsocks has no TLS camouflage. Use it as a landing node behind a relay, not for connections that cross a censoring firewall directly.'
TB_MSG_EN[note_client_configs]='Client configurations: "show --format xray" or "show --format sing-box". Links only: "show --format links". QR codes: "show --qr".'
TB_MSG_EN[note_firewall]='If the provider has its own firewall / security group, open the ports above there as well.'

TB_MSG_EN[menu_items]='  1) Install or reconfigure a node
  2) Show connection details
  3) Update the core
  4) Rotate credentials
  5) Uninstall
  0) Exit'
TB_MSG_EN[prompt_menu]='Choose'

TB_MSG_EN[usage]='ToastBox %s - VLESS-TCP-REALITY-Vision and Shadowsocks 2022 nodes on Xray or sing-box

Usage: toastbox.sh [command] [options]

Run without a command for the interactive menu.

Commands:
  install      Deploy a node, or change the settings of an existing one
  show         Print connection details, share links or client configs
  update       Upgrade the core and restart the node
  rotate       Generate new UUID / keys / passwords
  uninstall    Remove the core and the node
  help, version

Options for install:
  --core xray|sing-box        Core to use (default: xray)
  --protocols LIST            vless, ss or vless,ss (default: vless,ss)
  --server-addr ADDR          Address clients connect to (default: detected)
  --name NAME                 Node name used in share links (default: ToastBox)
  --listen ADDR               Bind to this local address (default: all)
  --vless-port PORT           VLESS port (default: 443)
  --reality-sni DOMAIN        REALITY target domain / SNI (required for vless)
  --reality-target HOST:PORT  REALITY target (default: <sni>:443)
  --skip-target-check         Do not probe the REALITY target
  --ss-port PORT              Shadowsocks port (default: random)
  --ss-method METHOD          2022-blake3-aes-128-gcm (default),
                              2022-blake3-aes-256-gcm or
                              2022-blake3-chacha20-poly1305
  --ss-network both|tcp|udp   Shadowsocks listen network (default: both)
  --block-bt                  Reject BitTorrent traffic (--no-block-bt to undo)
  --allow-private             Allow relaying to private / loopback addresses
                              (--no-allow-private to undo)
  --core-version VERSION      Install this core version instead of the latest
  --no-firewall               Do not touch ufw

Options for show:
  --format FORMAT             text (default), links, json, xray, sing-box
  --protocols LIST            Limit the output to these protocols
  --qr                        Also print QR codes (text format)

Options for uninstall:
  --purge                     Also delete configuration, logs and backups
  --core xray|sing-box        Core to remove when no node state exists

General:
  -y, --yes                   Never prompt; answer yes to confirmations
  --lang en|zh                Language (default: from the locale)
  -h, --help                  Show this help
  -V, --version               Show the version

Settings that are not given on the command line keep their current value
when a node already exists.
'

# ---------------------------------------------------------------------------
# 简体中文
# ---------------------------------------------------------------------------

TB_MSG_ZH[err_root]='此命令需要 root 权限（可使用：sudo bash toastbox.sh ...）。'
TB_MSG_ZH[err_os_version]='不支持 %s %s，需要 %s %s 或更高版本。'
TB_MSG_ZH[err_os_unsupported]='不支持的系统“%s”。ToastBox 支持 Debian 11+ 和 Ubuntu 20.04+。'
TB_MSG_ZH[warn_os_derivative]='“%s”是 Debian/Ubuntu 的衍生发行版，未经测试，将继续执行。'
TB_MSG_ZH[err_arch_unsupported]='不支持的 CPU 架构“%s”，仅支持 amd64 和 arm64。'
TB_MSG_ZH[err_no_systemd]='需要 systemd，但本机未运行 systemd。'
TB_MSG_ZH[info_install_deps]='正在安装依赖：%s'
TB_MSG_ZH[err_apt_update]='apt-get update 执行失败。'
TB_MSG_ZH[err_apt_install]='安装失败：%s'
TB_MSG_ZH[err_download]='下载失败：%s'
TB_MSG_ZH[err_state_corrupt]='状态文件 %s 无法读取或已损坏。'
TB_MSG_ZH[err_no_state]='本机没有 ToastBox 节点，请先执行 install。'
TB_MSG_ZH[err_keypair]='无法使用 %s 生成 REALITY 密钥对。'
TB_MSG_ZH[err_core]='未知内核“%s”，可选 xray 或 sing-box。'
TB_MSG_ZH[err_missing_value]='选项 %s 需要一个值。'
TB_MSG_ZH[err_unknown_arg]='未知参数：%s（参见 --help）。'
TB_MSG_ZH[err_invalid_option]='%s 的值无效：“%s”'
TB_MSG_ZH[err_invalid_value]='无效的值：“%s”'
TB_MSG_ZH[warn_invalid_input]='“%s”无效，请重新输入。'
TB_MSG_ZH[err_protocols]='协议列表“%s”无效，可选 vless、ss 或 vless,ss。'
TB_MSG_ZH[err_protocol_disabled]='此节点未启用协议“%s”。'
TB_MSG_ZH[err_format]='未知格式“%s”，可选 text、links、json、xray 或 sing-box。'
TB_MSG_ZH[err_aborted]='已取消，未做任何更改。（使用 --yes 可跳过确认。）'

TB_MSG_ZH[prompt_core]='内核：1) xray  2) sing-box'
TB_MSG_ZH[prompt_protocols]='协议：1) 两者都部署  2) 仅 VLESS-REALITY-Vision  3) 仅 Shadowsocks 2022'
TB_MSG_ZH[info_detect_addr]='正在检测本机公网地址……'
TB_MSG_ZH[err_server_addr_required]='无法检测公网地址，请用 --server-addr 指定。'
TB_MSG_ZH[prompt_server_addr]='客户端连接所用的地址（IP 或域名）'
TB_MSG_ZH[prompt_vless_port]='VLESS 端口'
TB_MSG_ZH[help_reality_sni]='
REALITY 会借用一个真实网站（“目标站”）的 TLS 身份。
请选择满足以下条件的网站：
  - 支持 TLS 1.3 和 HTTP/2；
  - 不在 Cloudflare 等 CDN 之后：未通过 REALITY 认证的连接会被原样
    转发到目标站，选用 CDN 站点会让本机变成该 CDN 的免费转发节点；
  - 最好与本机位于同一网络（ASN）。
'
TB_MSG_ZH[prompt_reality_sni]='REALITY 目标域名（SNI），例如 www.example.com'
TB_MSG_ZH[err_sni_required]='必须提供 REALITY 目标域名，请用 --reality-sni 指定。'
TB_MSG_ZH[info_probing_target]='正在探测 REALITY 目标站 %s（SNI %s）……'
TB_MSG_ZH[ok_target]='%s 支持 TLS 1.3，证书有效。'
TB_MSG_ZH[warn_target_no_h2]='%s 未协商 HTTP/2。可以使用，但支持 HTTP/2 的站点伪装效果更好。'
TB_MSG_ZH[err_target_unreachable]='本机无法连接到 %s。'
TB_MSG_ZH[err_target_no_tls13]='%s 不支持 TLS 1.3，而 REALITY 需要 TLS 1.3。'
TB_MSG_ZH[err_target_cert]='%s 的证书对 %s 无效。'
TB_MSG_ZH[prompt_target_anyway]='仍然使用这个目标站？'
TB_MSG_ZH[err_target_rejected]='REALITY 目标站未通过检查。请换一个，或使用 --skip-target-check 跳过探测。'
TB_MSG_ZH[prompt_ss_port]='Shadowsocks 端口'
TB_MSG_ZH[prompt_ss_method]='Shadowsocks 加密方式：1) 2022-blake3-aes-128-gcm  2) 2022-blake3-aes-256-gcm  3) 2022-blake3-chacha20-poly1305'
TB_MSG_ZH[err_no_free_port]='找不到空闲端口，请用 --ss-port 指定。'
TB_MSG_ZH[err_port_same]='VLESS 和 Shadowsocks 不能同时监听 TCP 端口 %s。'
TB_MSG_ZH[err_port_in_use]='端口 %s 已被占用：%s'
TB_MSG_ZH[plan_title]='即将部署：'
TB_MSG_ZH[prompt_proceed]='继续？'

TB_MSG_ZH[warn_core_switch]='内核将由 %s 切换为 %s，新内核就绪后 %s 服务会被停止并禁用。'
TB_MSG_ZH[prompt_overwrite_config]='%s 中已有一份并非由 ToastBox 生成的配置。是否替换？（会保留备份。）'
TB_MSG_ZH[err_foreign_config]='已保留现有配置 %s。如需替换，请加上 --yes 重新运行。'
TB_MSG_ZH[info_installing_core]='正在从官方渠道安装 %s……'
TB_MSG_ZH[err_core_install]='安装 %s 失败。'
TB_MSG_ZH[err_core_too_old]='%s %s 版本过旧：ToastBox 需要 %s 或更高版本。请执行 update 升级。'
TB_MSG_ZH[ok_core_ready]='%s %s 已安装。'
TB_MSG_ZH[err_render]='无法生成配置。'
TB_MSG_ZH[err_validate]='%s 未通过对生成配置的校验，未做任何更改。'
TB_MSG_ZH[info_restarting]='正在重启 %s……'
TB_MSG_ZH[ok_service_running]='%s 正在运行。'
TB_MSG_ZH[err_service_start]='%s 使用新配置启动失败。最近的日志：'
TB_MSG_ZH[warn_rolled_back]='已从 %s 恢复之前的配置。'
TB_MSG_ZH[warn_service_stopped]='%s 在本次更改之前并未运行，现已保持停止状态。'
TB_MSG_ZH[warn_old_core_restored]='已重新启动之前的 %s 服务。'
TB_MSG_ZH[err_apply]='配置未生效。'
TB_MSG_ZH[info_fw_opened]='防火墙（ufw）：已放行 %s'
TB_MSG_ZH[info_fw_closed]='防火墙（ufw）：已移除规则 %s'
TB_MSG_ZH[warn_extra_configs]='sing-box 会合并配置目录下的所有 JSON 文件，以下文件也会被加载：%s'
TB_MSG_ZH[warn_clock]='系统时钟未与 NTP 同步。两端时间相差过大时 Shadowsocks 2022 会拒绝连接，请开启时间同步（例如 timedatectl set-ntp true）。'
TB_MSG_ZH[ok_installed]='节点部署完成。'
TB_MSG_ZH[ok_self_installed]='已将本脚本安装为 %s，之后可用 toastbox <命令> 管理节点。'
TB_MSG_ZH[ok_updated]='%s 已更新到 %s。'
TB_MSG_ZH[prompt_rotate]='重新生成凭据？所有现有客户端在重新配置前都将无法连接。'
TB_MSG_ZH[ok_rotated]='新凭据已生效。'
TB_MSG_ZH[prompt_uninstall]='移除 %s 和此节点？（配置文件会保留。）'
TB_MSG_ZH[prompt_uninstall_purge]='移除 %s、此节点及其全部配置、日志和备份？'
TB_MSG_ZH[warn_remove_failed]='移除 %s 时出现错误，请查看上方输出。'
TB_MSG_ZH[ok_uninstalled]='%s 和 ToastBox 节点已移除。'
TB_MSG_ZH[ok_core_removed]='%s 已移除，运行在 %s 上的节点不受影响。'
TB_MSG_ZH[warn_no_qrencode]='qrencode 不可用，跳过二维码。'

TB_MSG_ZH[word_running]='运行中'
TB_MSG_ZH[word_stopped]='未运行'
TB_MSG_ZH[label_core]='内核'
TB_MSG_ZH[label_server]='服务器地址'
TB_MSG_ZH[label_config]='服务端配置'
TB_MSG_ZH[label_port]='端口'
TB_MSG_ZH[label_uuid]='UUID'
TB_MSG_ZH[label_flow]='流控（flow）'
TB_MSG_ZH[label_sni]='SNI'
TB_MSG_ZH[label_target]='目标站'
TB_MSG_ZH[label_public_key]='公钥（password）'
TB_MSG_ZH[label_short_id]='Short ID'
TB_MSG_ZH[label_fingerprint]='指纹'
TB_MSG_ZH[label_method]='加密方式'
TB_MSG_ZH[label_password]='密码'
TB_MSG_ZH[label_link]='分享链接：'
TB_MSG_ZH[note_ss_landing]='注意：Shadowsocks 没有 TLS 伪装，适合作为中转之后的落地节点，不适合直接穿越审查防火墙。'
TB_MSG_ZH[note_client_configs]='客户端配置：show --format xray 或 show --format sing-box；仅链接：show --format links；二维码：show --qr。'
TB_MSG_ZH[note_firewall]='如果服务商另有防火墙 / 安全组，请在那里同样放行上述端口。'

TB_MSG_ZH[menu_items]='  1) 安装或重新配置节点
  2) 查看连接信息
  3) 更新内核
  4) 重新生成凭据
  5) 卸载
  0) 退出'
TB_MSG_ZH[prompt_menu]='请选择'

TB_MSG_ZH[usage]='ToastBox %s - 基于 Xray 或 sing-box 部署 VLESS-TCP-REALITY-Vision 与 Shadowsocks 2022 节点

用法：toastbox.sh [命令] [选项]

不带命令运行将进入交互菜单。

命令：
  install      部署节点，或修改现有节点的设置
  show         显示连接信息、分享链接或客户端配置
  update       升级内核并重启节点
  rotate       重新生成 UUID / 密钥 / 密码
  uninstall    移除内核和节点
  help, version

install 的选项：
  --core xray|sing-box        使用的内核（默认：xray）
  --protocols LIST            vless、ss 或 vless,ss（默认：vless,ss）
  --server-addr ADDR          客户端连接所用的地址（默认：自动检测）
  --name NAME                 分享链接中的节点名称（默认：ToastBox）
  --listen ADDR               绑定到指定的本机地址（默认：全部）
  --vless-port PORT           VLESS 端口（默认：443）
  --reality-sni DOMAIN        REALITY 目标域名 / SNI（启用 vless 时必填）
  --reality-target HOST:PORT  REALITY 目标站（默认：<sni>:443）
  --skip-target-check         不探测 REALITY 目标站
  --ss-port PORT              Shadowsocks 端口（默认：随机）
  --ss-method METHOD          2022-blake3-aes-128-gcm（默认）、
                              2022-blake3-aes-256-gcm 或
                              2022-blake3-chacha20-poly1305
  --ss-network both|tcp|udp   Shadowsocks 监听的网络（默认：both）
  --block-bt                  拒绝 BitTorrent 流量（--no-block-bt 取消）
  --allow-private             允许转发到私有 / 回环地址
                              （--no-allow-private 取消）
  --core-version VERSION      安装指定版本的内核，而不是最新版
  --no-firewall               不修改 ufw

show 的选项：
  --format FORMAT             text（默认）、links、json、xray、sing-box
  --protocols LIST            只输出指定的协议
  --qr                        同时输出二维码（text 格式）

uninstall 的选项：
  --purge                     同时删除配置、日志和备份
  --core xray|sing-box        没有节点状态时指定要移除的内核

通用选项：
  -y, --yes                   不提示，对所有确认回答“是”
  --lang en|zh                语言（默认：取自系统 locale）
  -h, --help                  显示本帮助
  -V, --version               显示版本

节点已存在时，命令行未给出的设置保持当前值。
'
