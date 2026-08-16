#!/bin/bash
# fish post_install: 安装 fisher 并按 fish_plugins 清单拉取插件
set -euo pipefail

FISHER_URL="https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"

if [ ! -f "$HOME/.config/fish/functions/fisher.fish" ]; then
    log "安装 fisher..."
    fish -c "curl -sL '$FISHER_URL' | source && fisher install jorgebucaran/fisher" \
        || warn "fisher 安装失败，可稍后手动执行: fisher install jorgebucaran/fisher"
else
    log "fisher 已存在，跳过安装"
fi

if [ -f "$HOME/.config/fish/functions/fisher.fish" ]; then
    log "按 fish_plugins 清单更新插件..."
    fish -c 'fisher update' || warn "fisher update 失败"
fi
