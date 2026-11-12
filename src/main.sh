#!/usr/bin/env bash
#
# ToastBox - deploy VLESS-TCP-REALITY-Vision and Shadowsocks-2022 nodes
# with Xray or sing-box on Debian / Ubuntu.
#
# https://github.com/Claudedu-dev/ToastBox
#
# This file is the development entry point. It loads the modules in
# src/lib/ at run time. The single-file release (toastbox.sh in the
# repository root) is generated from it by scripts/build.sh.

set -euo pipefail

# @build:begin-loader
TB_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _tb_lib in "$TB_SRC_DIR"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "$_tb_lib"
done
unset _tb_lib
# @build:end-loader

# Everything above only defines functions and constants, so a truncated
# download (curl | bash) cannot run half of an installation.
if [[ "${TOASTBOX_SOURCE_ONLY:-0}" != "1" ]]; then
  tb_main "$@"
fi
