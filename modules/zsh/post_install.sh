#!/bin/bash
# zsh post_install: 克隆 oh-my-zsh 与自定义插件(固定版本), 第三方工作树不入仓库
set -euo pipefail

OMZ_REV="b37dd49ca5bfe0d99b35607637152cb8cc8b29d7"
ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_PLUGINS="$ZSH_DIR/custom/plugins"

# 1. oh-my-zsh
if [ ! -d "$ZSH_DIR/.git" ]; then
    log "克隆 oh-my-zsh (pin $OMZ_REV)..."
    git clone --quiet --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
    git -C "$ZSH_DIR" fetch --quiet --depth 1 origin "$OMZ_REV" \
        && git -C "$ZSH_DIR" checkout --quiet "$OMZ_REV"
    ok "oh-my-zsh 安装完成"
else
    log "oh-my-zsh 已存在，跳过"
fi

# 2. 按 plugins.txt 清单安装自定义插件
[ -f "$MODULE_DIR/plugins.txt" ] || { warn "缺少 plugins.txt"; exit 0; }
while IFS='|' read -r repo rev; do
    [ -z "$repo" ] && continue
    [[ "$repo" =~ ^#.*$ ]] && continue
    name="$(basename "$repo")"
    dest="$CUSTOM_PLUGINS/$name"
    if [ -d "$dest/.git" ]; then
        log "插件已存在，跳过: $name"
        continue
    fi
    log "克隆插件: $repo (pin $rev)"
    mkdir -p "$CUSTOM_PLUGINS"
    git clone --quiet --depth 1 "https://github.com/$repo.git" "$dest"
    git -C "$dest" fetch --quiet --depth 1 origin "$rev" \
        && git -C "$dest" checkout --quiet "$rev"
    ok "插件安装完成: $name"
done < "$MODULE_DIR/plugins.txt"
