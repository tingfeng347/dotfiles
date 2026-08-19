#!/bin/bash
# ============================================================
# install.sh — dotfiles 一键安装入口
#
# 用法:
#   ./install.sh               交互式选择模块
#   ./install.sh -y            安装全部模块 (自动确认)
#   ./install.sh fish zsh      只安装指定模块
#   ./install.sh --dry-run     仅预览, 不实际修改
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

# ----------------------------------------------------------
# 模块清单: modules/* (含 home/ 树、包清单或安装钩子)
# ----------------------------------------------------------
AVAILABLE=()
while IFS= read -r m; do [ -n "$m" ] && AVAILABLE+=("$m"); done < <(list_modules)

if [ "${#AVAILABLE[@]}" -eq 0 ]; then
    die "未发现任何模块 (modules/*)"
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   dotfiles 一键安装 (Ubuntu/Arch)    ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
detect_distro
log "检测到发行版: $DISTRO_ID"

install_x_cmd

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
    echo ""
    echo "可选模块:"
    for i in "${!AVAILABLE[@]}"; do
        m="${AVAILABLE[$i]}"
        desc=""
        if [ -f "$MODULES_DIR/$m/module.conf" ]; then
            desc="$(grep -m1 '^MODULE_DESC=' "$MODULES_DIR/$m/module.conf" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
        fi
        printf "  %2d) %-10s %s\n" "$((i+1))" "$m" "$desc"
    done
    printf "  %2d) %s\n" "$((${#AVAILABLE[@]}+1))" "全部安装"
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
log "将安装模块: ${SELECTED[*]}"
if [ "$AUTO_YES" -ne 1 ] && [ -z "$DRY_RUN" ]; then
    confirm "继续? " || die "已取消"
fi

# ----------------------------------------------------------
# 逐模块安装
# ----------------------------------------------------------
for m in "${SELECTED[@]}"; do
    install_module "$m"
done

echo ""
ok "全部完成"
[ -n "$DRY_RUN" ] && warn "本次为 dry-run，未做任何实际修改"
echo "  备份目录: $BACKUP_ROOT"
echo "  插件安装: fish 用 fisher, zsh 用 oh-my-zsh 清单, tmux 用 tpm"
echo "  LazyVim 插件在首次用 lazyvim 命令启动时自动安装"
echo "  本地改了配置后: ./capture.sh -y 复制回仓库, 再 git 提交同步"
