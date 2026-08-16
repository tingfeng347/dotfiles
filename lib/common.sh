#!/bin/bash
# ============================================================
# common.sh — 日志、颜色与公共工具函数
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[+]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[X]${NC} $1"; }
die()  { err "$1"; exit 1; }

# 用户确认: confirm "提示" [默认y]
confirm() {
    local prompt="$1" default="${2:-y}"
    local hint='[y/N]'
    [ "$default" = "y" ] && hint='[Y/n]'
    read -rp "$(echo -e "${YELLOW}[?]${NC} $prompt $hint ")" -r answer
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# 值是否在数组中 (不用管道 grep -q, 避免 pipefail+SIGPIPE 误判)
in_array() { # in_array <值> <候选...>
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# 备份目标文件到备份目录(保留相对路径结构), 仅当目标是真实文件/链接且不是指向 src 的链接
backup_target() {
    local dest="$1" src="$2" backup_root="$3"
    [ -e "$dest" ] || [ -L "$dest" ] || return 0
    # 已是指向 src 的符号链接则无需备份
    [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] && return 0
    local rel="${dest#$HOME/}"
    local backup_path="$backup_root/$rel"
    if [ -n "$DRY_RUN" ]; then
        warn "(dry-run) 将备份: $dest -> $backup_path"
        return 0
    fi
    mkdir -p "$(dirname "$backup_path")"
    mv -f "$dest" "$backup_path"
    ok "已备份: $dest -> $backup_path"
}
