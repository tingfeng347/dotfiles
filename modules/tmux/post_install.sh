#!/bin/bash
# tmux post_install: 克隆 tpm(固定版本) 并按 tmux.conf 中的 @plugin 安装插件
set -euo pipefail

TPM_REV="e261deb1b47614eed3400089ce7197dc68acc4eb"
TPM_DIR="$HOME/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR/.git" ]; then
    log "克隆 tpm (pin $TPM_REV)..."
    mkdir -p "$(dirname "$TPM_DIR")"
    git clone --quiet --depth 1 https://github.com/tmux-plugins/tpm.git "$TPM_DIR"
    git -C "$TPM_DIR" fetch --quiet --depth 1 origin "$TPM_REV" \
        && git -C "$TPM_DIR" checkout --quiet "$TPM_REV"
    ok "tpm 安装完成"
else
    log "tpm 已存在，跳过"
fi

if [ -x "$TPM_DIR/bin/install_plugins" ]; then
    log "安装 tmux 插件 (tmux-fzf / tmux-resurrect / tmux-continuum)..."
    "$TPM_DIR/bin/install_plugins"
    ok "tmux 插件安装完成"
    command -v fzf >/dev/null 2>&1 || warn "tmux-fzf 需要 fzf 命令，记得安装 fzf 模块"
else
    warn "无法自动安装插件，请在 tmux 中按 prefix+I"
fi
