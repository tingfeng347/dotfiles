#!/bin/bash
# yazi post_install: 按 package.toml 安装锁定版本 (rev+hash) 的插件与 flavor
set -euo pipefail

if command -v ya >/dev/null 2>&1; then
    log "安装 yazi 插件与 flavor (package.toml 锁定版本)..."
    ya pkg install || warn "ya pkg install 失败，可稍后手动执行: ya pkg install"
else
    warn "未找到 ya 命令，跳过插件安装 (yazi 未正确安装?)"
fi
