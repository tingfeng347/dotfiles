#!/bin/bash
# lazyvim post_install: 只部署配置, 不在此同步插件 (下载耗时长, 避免拖慢整体安装)
#
# 插件安装请自行选择其一:
#   - 启动 lazyvim (NVIM_APPNAME=lazyvim nvim), 首次启动自动安装, 或 :Lazy sync
#   - 运行仓库根目录的独立脚本 ./install-lazyvim.sh (无头模式, 带超时与重试)
set -uo pipefail

log "lazyvim: 配置已部署, 插件未在安装时同步"
log "  安装插件: 启动 lazyvim 自动安装, 或执行 ./install-lazyvim.sh (带重试)"
