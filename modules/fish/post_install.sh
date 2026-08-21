#!/bin/bash
# fish post_install: 升级 fish (如需), 安装 fisher, 按 fish_plugins 清单拉取插件
set -euo pipefail

# ---- 升级 fish: Ubuntu 22.04 apt 自带 3.3.1, 而 fzf.fish/fifc 需要 3.4+/3.6+ ----
upgrade_fish_if_old() {
    command -v fish >/dev/null 2>&1 || return 0
    local ver major minor
    ver="$(fish --version 2>/dev/null | awk '{print $3}' || true)"
    [ -n "$ver" ] || return 0
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 6 ]; }; then
        log "fish $ver 已满足要求 (>= 3.6)"
        return 0
    fi
    log "fish $ver 过旧 (fzf.fish/fifc 需 3.4+/3.6+), 通过 PPA 升级到 3.7"
    if [ -n "$DRY_RUN" ]; then
        warn "(dry-run) 将添加 ppa:fish-shell/release-3 并升级 fish"
        return 0
    fi
    if ! command -v add-apt-repository >/dev/null 2>&1; then
        sudo apt-get install -y software-properties-common || warn "安装 software-properties-common 失败"
    fi
    sudo add-apt-repository -y ppa:fish-shell/release-3 || warn "添加 fish PPA 失败"
    sudo apt-get update -qq
    sudo apt-get install -y fish || warn "升级 fish 失败"
    if fish --version 2>/dev/null | grep -qE '3\.[6-9]\.'; then
        ok "fish 已升级: $(fish --version 2>/dev/null)"
    else
        warn "fish 升级未生效 (当前 $(fish --version 2>/dev/null)), 请手动执行: sudo add-apt-repository -y ppa:fish-shell/release-3 && sudo apt-get update && sudo apt-get install -y fish"
    fi
}

upgrade_fish_if_old

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

# Ubuntu 的 fd 包名为 fd-find, 二进制是 fdfind; 补一个 fd 软链到 ~/.local/bin
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "已创建 fd 软链: $HOME/.local/bin/fd -> $(command -v fdfind)"
fi
