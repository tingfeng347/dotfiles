#!/bin/bash
# ============================================================
# distro.sh — 发行版检测与包管理抽象 (Ubuntu / Arch)
# ============================================================

DISTRO_ID=""
AUR_HELPER=""
APT_UPDATED=0

# 单包是否已安装 (逐包查询, 避免管道 SIGPIPE + pipefail 误判)
is_installed() { # is_installed <包名>
    case "$DISTRO_ID" in
        arch)
            pacman -Q "$1" >/dev/null 2>&1
            ;;
        *)
            dpkg-query -s "$1" >/dev/null 2>&1
            ;;
    esac
}

detect_distro() {
    if [ -r /etc/os-release ]; then
        DISTRO_ID="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
    fi
    case "$DISTRO_ID" in
        arch) ;;
        ubuntu|debian|linuxmint|pop|elementary) ;;
        *)
            warn "未识别的发行版: ${DISTRO_ID:-unknown}，将按 Ubuntu/Debian (apt) 处理"
            DISTRO_ID="ubuntu"
            ;;
    esac
}

pkg_install() { # pkg_install <包名...>
    local pkgs=("$@") missing=()
    for p in "${pkgs[@]}"; do
        if is_installed "$p"; then
            log "已安装，跳过: $p"
        else
            missing+=("$p")
        fi
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    log "安装: ${missing[*]}"
    [ -n "$DRY_RUN" ] && return 0
    case "$DISTRO_ID" in
        arch)
            sudo pacman -S --noconfirm --needed "${missing[@]}"
            ;;
        *)
            if [ "$APT_UPDATED" -eq 0 ]; then
                sudo apt-get update -qq
                APT_UPDATED=1
            fi
            sudo apt-get install -y "${missing[@]}"
            ;;
    esac
}

# AUR 安装 (仅 Arch; 需要 paru 或 yay)
pkg_install_aur() { # pkg_install_aur <包名...>
    local pkgs=("$@")
    if [ "$DISTRO_ID" != "arch" ]; then
        warn "AUR 包仅适用于 Arch Linux，跳过: ${pkgs[*]}"
        return 0
    fi
    [ -z "$AUR_HELPER" ] && AUR_HELPER="$(command -v paru || command -v yay || true)"
    [ -z "$AUR_HELPER" ] && die "未找到 paru/yay，无法安装 AUR 包: ${pkgs[*]}"
    for p in "${pkgs[@]}"; do
        if is_installed "$p"; then
            log "已安装，跳过: $p"
        else
            log "安装 AUR 包: $p"
            [ -n "$DRY_RUN" ] && continue
            "$AUR_HELPER" -S --noconfirm --needed "$p"
        fi
    done
}

# 解析包清单文件: 普通行 -> 官方仓库, "aur:" 前缀 -> AUR
install_package_list() { # install_package_list <文件路径>
    local list_file="$1" line
    [ -f "$list_file" ] || return 0
    local official=() aur=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue
        if [[ "$line" == aur:* ]]; then
            aur+=("${line#aur:}")
        else
            official+=("$line")
        fi
    done < "$list_file"
    [ "${#official[@]}" -gt 0 ] && pkg_install "${official[@]}"
    [ "${#aur[@]}" -gt 0 ] && pkg_install_aur "${aur[@]}"
    return 0
}
