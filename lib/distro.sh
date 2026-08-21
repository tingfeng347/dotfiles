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

# 安装官方仓库缺失的工具到用户目录 ~/.local (starship/eza/fastfetch 等)。
# 这类工具在旧版 Ubuntu (如 22.04) 的 apt 仓库中不存在, 通过官方脚本或
# GitHub releases 预编译包安装, 无需 sudo、不污染系统目录。
install_external() { # install_external <工具名>
    local tool="$1"
    # 优先探测 ~/.local/bin 里已装的二进制; 再探测 PATH 中能真正运行(--version)的。
    # 用 --version 实测, 避免 x-cmd 等在 Windows 侧生成的 shim 造成误判
    # (那些 shim 指向 Windows 二进制, 在 WSL 里跑不起来)。
    if [ -x "$HOME/.local/bin/$tool" ]; then
        log "已安装，跳过: $tool"
        return 0
    fi
    if command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
        log "已安装，跳过: $tool ($(command -v "$tool"))"
        return 0
    fi
    log "安装外部工具: $tool (官方仓库缺失, 安装到 ~/.local)"
    [ -n "$DRY_RUN" ] && return 0
    command -v curl >/dev/null 2>&1 || die "安装 $tool 需要 curl"
    command -v tar >/dev/null 2>&1 || die "安装 $tool 需要 tar"
    local bindir="$HOME/.local/bin" tmpdir arch
    mkdir -p "$bindir"
    case "$tool" in
        starship)
            log "通过官方脚本安装 starship..."
            curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$bindir" || die "starship 安装失败"
            ;;
        eza)
            arch="$(uname -m)"
            case "$arch" in
                x86_64) arch="x86_64-unknown-linux-gnu" ;;
                aarch64|arm64) arch="aarch64-unknown-linux-gnu" ;;
                *) die "eza 不支持的架构: $arch" ;;
            esac
            tmpdir="$(mktemp -d)"
            log "下载 eza ($arch)..."
            curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_${arch}.tar.gz" -o "$tmpdir/eza.tar.gz" || die "eza 下载失败"
            tar -xzf "$tmpdir/eza.tar.gz" -C "$tmpdir" || die "eza 解压失败"
            install -m 0755 "$tmpdir/eza" "$bindir/eza" || die "eza 安装失败"
            rm -rf "$tmpdir"
            ;;
        fastfetch)
            arch="$(uname -m)"
            case "$arch" in
                x86_64) arch="amd64" ;;
                aarch64|arm64) arch="aarch64" ;;
                *) die "fastfetch 不支持的架构: $arch" ;;
            esac
            tmpdir="$(mktemp -d)"
            log "下载 fastfetch ($arch)..."
            curl -fsSL "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.tar.gz" -o "$tmpdir/fastfetch.tar.gz" || die "fastfetch 下载失败"
            tar -xzf "$tmpdir/fastfetch.tar.gz" -C "$tmpdir" || die "fastfetch 解压失败"
            local root="$tmpdir/fastfetch-linux-$arch/usr"
            install -m 0755 "$root/bin/fastfetch" "$bindir/fastfetch" || die "fastfetch 安装失败"
            install -m 0755 "$root/bin/flashfetch" "$bindir/flashfetch" 2>/dev/null || true
            mkdir -p "$HOME/.local/share/fastfetch"
            cp -a "$root/share/fastfetch/." "$HOME/.local/share/fastfetch/" 2>/dev/null || true
            rm -rf "$tmpdir"
            ;;
        yazi)
            # Ubuntu 22.04 的 glibc 过旧, gnu 构建会报 GLIBC_2.39 not found, 故用 musl 静态构建
            arch="$(uname -m)"
            case "$arch" in
                x86_64) arch="x86_64-unknown-linux-musl" ;;
                aarch64|arm64) arch="aarch64-unknown-linux-musl" ;;
                *) die "yazi 不支持的架构: $arch" ;;
            esac
            command -v unzip >/dev/null 2>&1 || die "安装 yazi 需要 unzip"
            tmpdir="$(mktemp -d)"
            log "下载 yazi ($arch)..."
            curl -fsSL "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${arch}.zip" -o "$tmpdir/yazi.zip" || die "yazi 下载失败"
            unzip -q "$tmpdir/yazi.zip" -d "$tmpdir" || die "yazi 解压失败"
            install -m 0755 "$tmpdir/yazi-$arch/yazi" "$bindir/yazi" || die "yazi 安装失败"
            install -m 0755 "$tmpdir/yazi-$arch/ya" "$bindir/ya" || die "ya 安装失败"
            rm -rf "$tmpdir"
            ;;
        *)
            warn "未知外部工具，跳过: $tool"
            return 0
            ;;
    esac
    if [ -x "$bindir/$tool" ]; then
        ok "$tool 安装完成: $bindir/$tool"
    else
        warn "$tool 安装结果未确认, 请检查 $bindir/$tool"
    fi
}

# 解析包清单文件: 普通行 -> 官方仓库, "aur:" 前缀 -> AUR, "ext:" 前缀 -> 外部工具
install_package_list() { # install_package_list <文件路径>
    local list_file="$1" line
    [ -f "$list_file" ] || return 0
    local official=() aur=() ext=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue
        case "$line" in
            aur:*) aur+=("${line#aur:}") ;;
            ext:*) ext+=("${line#ext:}") ;;
            *) official+=("$line") ;;
        esac
    done < "$list_file"
    [ "${#official[@]}" -gt 0 ] && pkg_install "${official[@]}"
    [ "${#aur[@]}" -gt 0 ] && pkg_install_aur "${aur[@]}"
    local t
    for t in "${ext[@]}"; do
        install_external "$t"
    done
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

# 卸载 install_external 安装到 ~/.local 的工具
remove_external() { # remove_external <工具名>
    local tool="$1" target
    target="$HOME/.local/bin/$tool"
    if [ ! -e "$target" ] && ! command -v "$tool" >/dev/null 2>&1; then
        log "未安装，跳过: $tool"
        return 0
    fi
    log "卸载外部工具: $tool"
    [ -n "$DRY_RUN" ] && return 0
    rm -f "$target" && ok "已删除: $target" || warn "删除失败: $target"
    case "$tool" in
        yazi) rm -f "$HOME/.local/bin/ya" ;;
        fastfetch)
            rm -f "$HOME/.local/bin/flashfetch"
            rm -rf "$HOME/.local/share/fastfetch"
            ;;
    esac
}

# 解析包清单文件并卸载 (与 install_package_list 对称)
remove_package_list() { # remove_package_list <文件路径>
    local list_file="$1" line
    [ -f "$list_file" ] || return 0
    local official=() aur=() ext=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue
        case "$line" in
            aur:*) aur+=("${line#aur:}") ;;
            ext:*) ext+=("${line#ext:}") ;;
            *) official+=("$line") ;;
        esac
    done < "$list_file"
    # Arch 下 AUR 包与官方包都走 pacman 卸载; 其余发行版 AUR 本就不安装
    if [ "$DISTRO_ID" = "arch" ]; then
        official+=("${aur[@]}")
        aur=()
    fi
    [ "${#official[@]}" -gt 0 ] && pkg_remove "${official[@]}"
    [ "${#aur[@]}" -gt 0 ] && warn "跳过 AUR 包卸载: ${aur[*]}"
    local t
    for t in "${ext[@]}"; do
        remove_external "$t"
    done
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
