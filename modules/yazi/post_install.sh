#!/bin/bash
# yazi post_install: 按 package.toml 安装锁定版本 (rev+hash) 的插件与 flavor
set -euo pipefail

# ya 可能被 ext 安装到 ~/.local/bin (不一定在安装脚本的 PATH 中)
YA_BIN=""
if [ -x "$HOME/.local/bin/ya" ]; then
    YA_BIN="$HOME/.local/bin/ya"
elif command -v ya >/dev/null 2>&1; then
    YA_BIN="$(command -v ya)"
fi

if [ -n "$YA_BIN" ]; then
    log "安装 yazi 插件与 flavor (package.toml 锁定版本)..."
    "$YA_BIN" pkg install || warn "ya pkg install 失败，可稍后手动执行: ya pkg install"
else
    warn "未找到 ya 命令，跳过插件安装 (yazi 未正确安装?)"
fi
