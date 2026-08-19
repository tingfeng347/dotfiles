#!/bin/bash
# ============================================================
# update.sh — 覆盖/同步本机配置为仓库内容 (清理已删除文件)
#
# 与 install.sh 的区别:
#   - install.sh: 装包 + 复制部署 (不删除本机多余文件)
#   - update.sh:  不装包, 用 rsync --delete 同步, 会删除本机里
#                 仓库已不存在的文件 (如旧的 miyu.fish)
#
# 用法:
#   ./update.sh               交互式选择模块
#   ./update.sh -y            更新全部模块
#   ./update.sh fish zsh      只更新指定模块
#   ./update.sh --dry-run     仅预览将发生的变更
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$REPO_DIR/lib"
MODULES_DIR="$REPO_DIR/modules"

. "$LIB_DIR/common.sh"
. "$LIB_DIR/distro.sh"
. "$LIB_DIR/deploy.sh"

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
while IFS= read -r m; do [ -n "$m" ] && AVAILABLE+=("$m"); done < <(list_modules)

if [ "${#AVAILABLE[@]}" -eq 0 ]; then
    die "未发现任何模块 (modules/*)"
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   dotfiles 配置更新/覆盖 (同步模式)  ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

SELECTED=()

if [ "${#SELECTED_ARGS[@]}" -gt 0 ]; then
    for arg in "${SELECTED_ARGS[@]}"; do
        if in_array "$arg" "${AVAILABLE[@]}"; then
            SELECTED+=("$arg")
        else
            warn "未知模块，跳过: $arg (可用: ${AVAILABLE[*]})"
        fi
    done
elif [ "$AUTO_YES" -eq 1 ]; then
    SELECTED=("${AVAILABLE[@]}")
else
    echo "可选模块:"
    for i in "${!AVAILABLE[@]}"; do
        m="${AVAILABLE[$i]}"
        desc=""
        if [ -f "$MODULES_DIR/$m/module.conf" ]; then
            desc="$(grep -m1 '^MODULE_DESC=' "$MODULES_DIR/$m/module.conf" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
        fi
        printf "  %2d) %-10s %s\n" "$((i+1))" "$m" "$desc"
    done
    printf "  %2d) %s\n" "$((${#AVAILABLE[@]}+1))" "全部更新"
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
        else
            warn "无效编号: $n"
        fi
    done
fi

[ "${#SELECTED[@]}" -gt 0 ] || die "未选择任何模块"
log "将更新模块: ${SELECTED[*]}"
warn "同步会删除本机存在但仓库已删除的文件 (被删除前先备份)"
if [ "$AUTO_YES" -ne 1 ] && [ -z "$DRY_RUN" ]; then
    confirm "继续? " || die "已取消"
fi

for m in "${SELECTED[@]}"; do
    echo ""
    log "=== 更新模块: $m ==="
    sync_module "$m"
done

echo ""
ok "更新完成"
[ -n "$DRY_RUN" ] && warn "本次为 dry-run，未做任何实际修改"
echo "  备份目录: $BACKUP_ROOT"
echo "  若要装新依赖包，请改用 ./install.sh"
