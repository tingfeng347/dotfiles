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

# 确保 en_US.UTF-8 locale 已生成。
# oh-my-zsh 的 agnoster 等主题用 $'\ue0b0' 之类 powerline 分隔符, 依赖 UTF-8 locale;
# 若环境变量声明了 en_US.UTF-8 但 locale 未生成, zsh 启动会报 "character not in range"。
ensure_utf8_locale() {
    command -v locale >/dev/null 2>&1 || return 0
    if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
        log "UTF-8 locale (en_US.UTF-8) 已就绪"
        return 0
    fi
    log "生成 en_US.UTF-8 locale..."
    [ -n "$DRY_RUN" ] && return 0
    case "$DISTRO_ID" in
        arch)
            # Arch 需先在 /etc/locale.gen 取消注释 en_US.UTF-8 再 locale-gen
            sudo sed -i -E 's/^#[[:space:]]*(en_US\.UTF-8[[:space:]]+UTF-8)[[:space:]]*$/\1/' /etc/locale.gen
            sudo locale-gen en_US.UTF-8
            ;;
        *)
            sudo sed -i -E 's/^#[[:space:]]*(en_US\.UTF-8[[:space:]]+UTF-8)[[:space:]]*$/\1/' /etc/locale.gen 2>/dev/null || true
            sudo locale-gen en_US.UTF-8
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

# 卸载单个包 (已安装才卸载; 其余跳过)
pkg_remove() { # pkg_remove <包名...>
    local pkgs=("$@") installed=()
    for p in "${pkgs[@]}"; do
        if is_installed "$p"; then
            installed+=("$p")
        else
            log "未安装，跳过: $p"
        fi
    done
    [ "${#installed[@]}" -eq 0 ] && return 0
    log "卸载: ${installed[*]}"
    [ -n "$DRY_RUN" ] && return 0
    case "$DISTRO_ID" in
        arch) sudo pacman -Rns --noconfirm "${installed[@]}" ;;
        *) sudo apt-get remove -y "${installed[@]}" ;;
    esac
}

# 解析包清单文件并卸载 (与 install_package_list 对称)
remove_package_list() { # remove_package_list <文件路径>
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
    # Arch 下 AUR 包与官方包都走 pacman 卸载; 其余发行版 AUR 本就不安装
    if [ "$DISTRO_ID" = "arch" ]; then
        official+=("${aur[@]}")
        aur=()
    fi
    [ "${#official[@]}" -gt 0 ] && pkg_remove "${official[@]}"
    [ "${#aur[@]}" -gt 0 ] && warn "跳过 AUR 包卸载: ${aur[*]}"
    return 0
}

# 检测 x-cmd 是否已安装 (~/.x-cmd.root/X 存在即视为已安装)
has_x_cmd() {
    [ -f "$HOME/.x-cmd.root/X" ]
}

# 安装 x-cmd (官方安装脚本 eval "$(curl https://get.x-cmd.com)")
install_x_cmd() {
    if has_x_cmd; then
        log "x-cmd 已安装，跳过"
        return 0
    fi
    command -v curl >/dev/null || die "需要 curl 才能安装 x-cmd"
    log "未检测到 x-cmd，正在安装..."
    [ -n "$DRY_RUN" ] && return 0
    # x-cmd 安装脚本会引用 $ZSH_VERSION 等未定义变量, 需在子 shell 中关闭 nounset
    ( set +u; eval "$(curl https://get.x-cmd.com)" )
    has_x_cmd && ok "x-cmd 安装完成" || warn "x-cmd 安装脚本已执行，但未检测到 ~/.x-cmd.root/X，请检查"
    return 0
}
