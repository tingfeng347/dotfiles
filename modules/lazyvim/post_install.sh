#!/bin/bash
# lazyvim post_install: 无头模式安装/同步插件 (带超时与重试)
#
# 可用环境变量覆盖:
#   NVIM_BIN                nvim 路径 (默认 nvim)
#   LAZYVIM_SYNC_TIMEOUT    单次同步超时秒数 (默认 600)
#   LAZYVIM_SYNC_TRIES      最多重试次数 (默认 3)
set -uo pipefail

APPNAME="lazyvim"
NVIM_BIN="${NVIM_BIN:-nvim}"
PLUGIN_ROOT="$HOME/.local/share/$APPNAME"
MAX_TRIES="${LAZYVIM_SYNC_TRIES:-3}"
SYNC_TIMEOUT="${LAZYVIM_SYNC_TIMEOUT:-600}"

if ! command -v "$NVIM_BIN" >/dev/null 2>&1; then
    warn "lazyvim: 未找到 $NVIM_BIN, 跳过插件安装 (可稍后执行: NVIM_APPNAME=$APPNAME nvim)"
    exit 0
fi

log "lazyvim: 无头模式同步插件 (超时 ${SYNC_TIMEOUT}s, 最多 ${MAX_TRIES} 次)"

# 修复偶发 "Clone succeeded, but checkout failed": 对未完成检出的插件目录
# 重新 checkout HEAD, 使工作区恢复到 lockfile 对应提交
repair_checkouts() {
    local d
    for d in "$PLUGIN_ROOT/lazy"/*/; do
        [ -d "$d/.git" ] || continue
        ( cd "$d" 2>/dev/null && git -c advice.detachedHead=false \
            restore --source=HEAD --recurse-submodules -- . 2>/dev/null ) || true
    done
}

sync_once() {
    local out rc
    out="$(timeout "$SYNC_TIMEOUT" env NVIM_APPNAME="$APPNAME" \
        "$NVIM_BIN" --headless "+Lazy! sync" +qa 2>&1)" && rc=0 || rc=$?
    printf '%s\n' "$out" | tail -n 20
    if [ "$rc" -ne 0 ]; then
        warn "lazyvim: 同步被中断 (退出码 $rc)"
        return 1
    fi
    if printf '%s' "$out" | grep -qiE 'failed'; then
        warn "lazyvim: 检测到插件安装失败"
        return 1
    fi
    return 0
}

attempt=1
while [ "$attempt" -le "$MAX_TRIES" ]; do
    log "lazyvim: 插件同步 (第 $attempt/$MAX_TRIES 次)..."
    if sync_once; then
        ok "lazyvim: 插件同步完成"
        exit 0
    fi
    warn "lazyvim: 修复部分检出后重试"
    repair_checkouts
    attempt=$((attempt+1))
done

warn "lazyvim: 插件同步多次失败; 可稍后手动执行: NVIM_APPNAME=$APPNAME nvim +Lazy"
exit 0
