#!/bin/bash
# ============================================================
# capture.sh — 把本机当前配置吸入仓库 (备份/更新用)
#
# 用法:
#   ./capture.sh             交互式选择模块
#   ./capture.sh -y          采集全部模块
#   ./capture.sh fish zsh    只采集指定模块
#   ./capture.sh --dry-run   仅预览将采集的文件
#
# 每个模块在 module.conf 中声明:
#   CAPTURE_PATHS=( "$HOME/.config/fish|.config/fish" ... )  源|仓库内相对路径
#   CAPTURE_EXCLUDES=( fish_variables ... )                  排除项
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$REPO_DIR/lib"
MODULES_DIR="$REPO_DIR/modules"

. "$LIB_DIR/common.sh"

if [ "$EUID" -eq 0 ]; then
    die "请以普通用户运行，不要用 root"
fi
command -v rsync >/dev/null || die "需要 rsync"

AUTO_YES=0
DRY_RUN=""
SELECTED_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) printf '用法: %s [-y|--yes] [--dry-run] [模块名...]\n' "$0"; exit 0 ;;
        *) SELECTED_ARGS+=("$1") ;;
    esac
    shift
done

AVAILABLE=()
while IFS= read -r m; do [ -n "$m" ] && AVAILABLE+=("$m"); done < <(ls "$MODULES_DIR" 2>/dev/null | sort || true)

SELECTED=()
if [ "${#SELECTED_ARGS[@]}" -gt 0 ]; then
    for arg in "${SELECTED_ARGS[@]}"; do
        if in_array "$arg" "${AVAILABLE[@]}"; then
            SELECTED+=("$arg")
        else
            warn "未知模块: $arg"
        fi
    done
elif [ "$AUTO_YES" -eq 1 ]; then
    SELECTED=("${AVAILABLE[@]}")
else
    echo ""
    echo "可选模块:"
    for i in "${!AVAILABLE[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "${AVAILABLE[$i]}"
    done
    printf "  %2d) %s\n" "$((${#AVAILABLE[@]}+1))" "全部"
    echo ""
    read -rp "选择模块编号 (可逗号分隔, 回车=全部): " -r CHOICE || CHOICE=""
    [ -z "$CHOICE" ] && CHOICE="$(( ${#AVAILABLE[@]} + 1 ))"
    IFS=',' read -ra IDX <<< "$CHOICE"
    for n in "${IDX[@]}"; do
        n="${n// /}"
        if ! [[ "$n" =~ ^[0-9]+$ ]]; then
            warn "无效编号: $n"
            continue
        fi
        if [ "$n" -eq "$(( ${#AVAILABLE[@]} + 1 ))" ]; then
            SELECTED=("${AVAILABLE[@]}")
            break
        elif [ "$n" -ge 1 ] && [ "$n" -le "${#AVAILABLE[@]}" ]; then
            SELECTED+=("${AVAILABLE[$((n-1))]}")
        fi
    done
fi
[ "${#SELECTED[@]}" -gt 0 ] || die "未选择任何模块"

# 通用排除
EXCLUDES=(--exclude='.git/' --exclude='*.bak' --exclude='*.bak-*' --exclude='node_modules/')

capture_module() {
    local module="$1"
    local conf="$MODULES_DIR/$module/module.conf"
    [ -f "$conf" ] || { warn "模块 $module 无 module.conf (无 CAPTURE_PATHS)，跳过"; return 0; }
    # 在子 shell 中 source 以读取数组
    local entries excludes
    entries="$(bash -c ". '$conf'; printf '%s\n' \"\${CAPTURE_PATHS[@]}\"")"
    excludes="$(bash -c ". '$conf'; printf '%s\n' \"\${CAPTURE_EXCLUDES[@]:-}\"")"
    [ -z "$entries" ] && { warn "模块 $module 未声明 CAPTURE_PATHS，跳过"; return 0; }

    local extra_excludes=()
    while IFS= read -r e; do
        [ -n "$e" ] && extra_excludes+=(--exclude="$e")
    done <<< "$excludes"

    local entry src rel dest
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        src="${entry%%|*}"
        rel="${entry#*|}"
        dest="$MODULES_DIR/$module/home/$rel"
        if [ ! -e "$src" ]; then
            warn "源不存在，跳过: $src"
            continue
        fi
        log "采集: $src -> $rel"
        if [ -n "$DRY_RUN" ]; then
            if [ -d "$src" ]; then
                rsync -ani "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src"/ "$dest"/ 2>/dev/null || true
            else
                rsync -ani "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src" "$dest" 2>/dev/null || true
            fi
            continue
        fi
        if [ -d "$src" ]; then
            mkdir -p "$dest"
            rsync -a --delete "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src"/ "$dest"/
        else
            mkdir -p "$(dirname "$dest")"
            rsync -a "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src" "$dest"
        fi
        ok "已更新: $rel"
    done <<< "$entries"
}

echo ""
log "采集模块: ${SELECTED[*]}"
if [ "$AUTO_YES" -ne 1 ] && [ -z "$DRY_RUN" ]; then
    confirm "继续? (将覆盖仓库内旧配置) " || die "已取消"
fi

for m in "${SELECTED[@]}"; do
    echo ""
    capture_module "$m"
done

echo ""
ok "采集完成"
[ -n "$DRY_RUN" ] && warn "本次为 dry-run，未修改仓库"
echo "  审查后请 git add/commit; 注意勿提交密钥 (lazy-lock.json 中的 token 等)"
