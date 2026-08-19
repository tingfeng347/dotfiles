#!/bin/bash
# ============================================================
# deploy.sh — 模块发现 + 复制部署引擎
#
# 部署策略: 纯复制 (cp/rsync), 不建符号链接。
#   modules/<name>/home/ 下的每个文件 -> 复制到 $HOME 对应路径。
#   已存在且内容不同的目标文件先备份到 ~/.dotfiles-backup/ 再覆盖;
#   内容相同的跳过, 保证重复安装幂等。
#   本地修改配置后用 capture.sh 复制回仓库, 再 git 同步。
# ============================================================

BACKUP_ROOT="$HOME/.dotfiles-backup"

list_modules() {
    local m
    for d in "$MODULES_DIR"/*/; do
        m="$(basename "$d")"
        # 有 home/ 树、包清单或安装钩子即可作为模块
        if [ -d "$d/home" ] || ls "$d"/packages.* >/dev/null 2>&1 || [ -f "$d/post_install.sh" ]; then
            echo "$m"
        fi
    done
}

# 部署单个模块的 home/ 树
deploy_module() { # deploy_module <模块名>
    local module="$1"
    local src="$MODULES_DIR/$module/home"
    [ -d "$src" ] || { warn "模块 $module 无 home/ 目录，跳过部署"; return 0; }
    # shellcheck disable=SC1090
    [ -f "$MODULES_DIR/$module/module.conf" ] && . "$MODULES_DIR/$module/module.conf"

    local copied=0 skipped=0
    while IFS= read -r -d '' rel; do
        local dest="$HOME/$rel"
        local s="$src/$rel"
        mkdir -p "$(dirname "$dest")"
        # 内容一致则跳过 (幂等)
        if [ -f "$dest" ] && cmp -s "$s" "$dest"; then
            skipped=$((skipped+1))
            continue
        fi
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            backup_target "$dest" "$s" "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
        fi
        if [ -n "$DRY_RUN" ]; then
            warn "(dry-run) 将复制: $s -> $dest"
        else
            cp -a "$s" "$dest"
            log "已复制: $dest"
        fi
        copied=$((copied+1))
    done < <(cd "$src" && find . -type f -print0 | sed -z 's|^\./||')

    ok "模块 $module: 复制 $copied, 内容一致跳过 $skipped"
}

# 同步模块配置到本机 (rsync --delete: 覆盖 + 清理仓库里已删除的文件)
# 相比 deploy_module, 会删除本机存在但仓库已删除的文件 (如旧 miyu.fish);
# 被覆盖/删除的文件仍按相对路径备份到 ~/.dotfiles-backup/<时间戳>/
# 按 module.conf 的 CAPTURE_PATHS 逐项同步, 使 CAPTURE_EXCLUDES (相对各源根) 正确生效
sync_module() { # sync_module <模块名>
    local module="$1"
    local home_root="$MODULES_DIR/$module/home"
    [ -d "$home_root" ] || { warn "模块 $module 无 home/ 目录，跳过"; return 0; }
    # shellcheck disable=SC1090
    [ -f "$MODULES_DIR/$module/module.conf" ] && . "$MODULES_DIR/$module/module.conf"

    # 通用排除 + 模块声明的排除 (运行时状态/fisher/yazi 插件等, 不覆盖也不删除)
    local excludes=(--exclude='.git/' --exclude='*.bak')
    local e
    for e in "${CAPTURE_EXCLUDES[@]:-}"; do
        [ -n "$e" ] && excludes+=(--exclude="$e")
    done

    # 无 CAPTURE_PATHS 时回退为整棵 home/ 树
    local entries=()
    if declare -p CAPTURE_PATHS >/dev/null 2>&1; then
        entries=("${CAPTURE_PATHS[@]}")
    fi
    [ "${#entries[@]}" -eq 0 ] && entries=("$HOME|")

    local stamp="" backup_dir=""
    if [ -z "$DRY_RUN" ]; then
        stamp="$(date +%Y%m%d-%H%M%S)"
        backup_dir="$BACKUP_ROOT/$stamp"
        mkdir -p "$backup_dir"
    fi

    local entry src rel dest repo
    for entry in "${entries[@]}"; do
        [ -z "$entry" ] && continue
        src="${entry%%|*}"     # 本机目标 (含 $HOME)
        rel="${entry#*|}"      # 相对 home/ 的仓库内路径
        dest="$src"
        repo="$home_root/${rel#/}"
        repo="${repo%/}"
        [ -e "$repo" ] || { warn "仓库内不存在，跳过: $repo"; continue; }

        if [ -d "$repo" ]; then
            # 目录: 同步 + --delete 清理本机多余文件
            if [ -n "$DRY_RUN" ]; then
                log "(dry-run) 模块 $module 同步变更 (${rel:-home/}):"
                rsync -ani --delete "${excludes[@]}" "$repo"/ "$dest"/ || true
                continue
            fi
            mkdir -p "$dest"
            rsync -a --delete --backup --backup-dir="$backup_dir" "${excludes[@]}" "$repo"/ "$dest"/
            ok "模块 $module: 已同步 ${rel:-home/}"
        else
            # 单文件: 仅覆盖 (无 --delete, 不存在就新建)
            if [ -n "$DRY_RUN" ]; then
                log "(dry-run) 模块 $module 同步变更 (${rel:-home/}):"
                rsync -ani "${excludes[@]}" "$repo" "$dest" || true
                continue
            fi
            mkdir -p "$(dirname "$dest")"
            rsync -a --backup --backup-dir="$backup_dir" "${excludes[@]}" "$repo" "$dest"
            ok "模块 $module: 已同步 ${rel:-home/}"
        fi
    done
    [ -z "$DRY_RUN" ] && rmdir "$backup_dir" 2>/dev/null || true
}

# 运行模块安装钩子 (钩子失败不中断整体安装, 仅警告)
run_post_install() { # run_post_install <模块名>
    local module="$1"
    local hook="$MODULES_DIR/$module/post_install.sh"
    [ -f "$hook" ] || return 0
    log "运行模块 $module 的 post_install 钩子"
    [ -n "$DRY_RUN" ] && return 0
    # source 而非执行子进程, 以继承 common.sh 的 log/ok/warn 函数
    ( cd "$MODULES_DIR/$module" && MODULE_DIR="$MODULES_DIR/$module" . ./post_install.sh ) \
        || warn "模块 $module 的 post_install 失败 (已复制的配置不受影响)"
}

# 安装模块 (包清单 + 部署 + 钩子)
install_module() { # install_module <模块名>
    local module="$1"
    # shellcheck disable=SC1090
    [ -f "$MODULES_DIR/$module/module.conf" ] && . "$MODULES_DIR/$module/module.conf"
    local desc="${MODULE_DESC:-$module}"
    echo ""
    log "=== 模块: $module — $desc ==="

    local pkg_file=""
    case "$DISTRO_ID" in
        arch)    pkg_file="$MODULES_DIR/$module/packages.arch" ;;
        *)       pkg_file="$MODULES_DIR/$module/packages.ubuntu" ;;
    esac
    install_package_list "$pkg_file"
    deploy_module "$module"
    run_post_install "$module"
}
