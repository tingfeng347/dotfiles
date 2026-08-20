# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnoster"

plugins=(git z fzf fzf-tab history zsh-syntax-highlighting)

export FZF_DEFAULT_OPTS="--cycle --layout=reverse --border --height=90% --marker=*"
export FZF_CTRL_R_OPTS='--prompt="> " --preview-window=bottom,3,wrap'

source $ZSH/oh-my-zsh.sh

# 静默 Alt+C: fzf 选择目录后直接 cd，不打印命令
fzf-cd-widget() {
  setopt localoptions pipefail no_aliases 2> /dev/null
  local dir="$(
    FZF_DEFAULT_COMMAND=${FZF_ALT_C_COMMAND:-} \
    FZF_DEFAULT_OPTS=$(__fzf_defaults "--reverse --walker=dir,follow,hidden --scheme=path" "${FZF_ALT_C_OPTS-} +m") \
    FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd) < /dev/tty)"
  if [[ -z "$dir" ]]; then
    zle redisplay
    return 0
  fi
  builtin cd -- "$dir"
  local ret=$?
  unset dir
  zle reset-prompt
  return $ret
}
zle -N fzf-cd-widget

# 从 fish 同步的环境变量
export TERMINFO_DIRS=/usr/lib/kitty/terminfo:/usr/share/terminfo
export PATH="$PATH:./node_modules/.bin"

# zoxide 智能跳转（替代 cd）
eval "$(zoxide init zsh --cmd cd)"

# 命令替换（先清除 oh-my-zsh 预设的别名，否则函数定义报错）
unalias ls 2>/dev/null
cat()  { command bat "$@"; }
ls()   { command eza --icons "$@"; }
lt()   { command eza --icons --tree "$@"; }
shorin()  { tput sgr0 2>/dev/null; tput cnorm 2>/dev/null; stty sane 2>/dev/null; command shorin "$@"; }

# yazi 文件管理器
y() {
    local tmp=$(mktemp -t "yazi-cwd.XXXXXX")
    yazi "$@" --cwd-file="$tmp"
    local cwd=$(cat "$tmp")
    if [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# conda 按需加载
conda-on() {
    if [ -z "$CONDA_SHLVL" ]; then
        eval "$(/opt/miniconda3/bin/conda shell.zsh hook)"
        echo "conda 已激活"
    else
        echo "conda 已经在运行中"
    fi
}

conda-off() {
    if [ -n "$CONDA_SHLVL" ]; then
        while [ -n "$CONDA_SHLVL" ] && [ "$CONDA_SHLVL" -gt 0 ]; do
            conda deactivate 2>/dev/null || break
        done
        # 清理 PATH 中的 conda 路径
        export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/opt/miniconda3' | tr '\n' ':' | sed 's/:$//')
        unset CONDA_SHLVL CONDA_EXE _CONDA_EXE _CONDA_ROOT CONDA_PREFIX CONDA_PROMPT_MODIFIER
        unset -f conda 2>/dev/null
        echo "conda 已关闭"
    else
        echo "conda 未激活"
    fi
}

# 终端代理：`proxy_on [端口]`，未传端口时默认使用 7897。
proxy_on() {
    local port="${1:-7897}"
    if ! [[ "$port" =~ '^[0-9]+$' ]] || (( port < 1 || port > 65535 )); then
        echo "用法：proxy_on [1-65535 端口]" >&2
        return 2
    fi

    local http_proxy_url="http://127.0.0.1:$port"
    local socks_proxy_url="socks5://127.0.0.1:$port"

    export http_proxy="$http_proxy_url" https_proxy="$http_proxy_url" all_proxy="$socks_proxy_url"
    export HTTP_PROXY="$http_proxy_url" HTTPS_PROXY="$http_proxy_url" ALL_PROXY="$socks_proxy_url"
    echo "代理已开启（HTTP: $http_proxy_url；SOCKS5: $socks_proxy_url）"
}

proxy_off() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    echo "代理已关闭"
}

proxy_status() {
    echo "--- 代理环境变量 (Proxy Env) ---"
    printf 'http_proxy: %s\nhttps_proxy: %s\nall_proxy: %s\n' \
        "${http_proxy:-未设置}" "${https_proxy:-未设置}" "${all_proxy:-未设置}"
    printf 'HTTP_PROXY: %s\nHTTPS_PROXY: %s\nALL_PROXY: %s\n' \
        "${HTTP_PROXY:-未设置}" "${HTTPS_PROXY:-未设置}" "${ALL_PROXY:-未设置}"

    if [[ -z "${https_proxy:-}" ]]; then
        printf '\n代理状态：未开启\n'
        return 0
    fi

    printf '\n--- 连通性测试 (Connectivity) ---\n'
    local result
    result=$(curl --proxy "$https_proxy" --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'HTTP %{http_code}, %{time_total}s' https://www.google.com 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "测试 Google.com… 成功 ($result)"
    else
        echo "测试 Google.com… 失败 ($result)"
        return 1
    fi

    printf '\n--- IP 地理位置 (IP Location) ---\n'
    curl --proxy "$https_proxy" --connect-timeout 5 --max-time 10 -fsS https://ipinfo.io/json || echo "查询失败"
}

# 中文快捷
安装() { command yay -S "$@"; }
滚()   { sysup; }
卸载() { command yay -Rns "$@"; }

# 缩写 → zsh alias
alias grub='LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
alias lsfg='export LSFG_PROCESS=miyu'
alias fa='fastfetch'
alias reboot='systemctl reboot'

# 阻止鼠标滚轮切换到历史记录（有输入时才搜索历史）
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward

# 禁用 zsh 的 %（不完整行标记），tmux 恢复时不再显示
unsetopt PROMPT_SP

# 关掉 starship，用 oh-my-zsh 的 agnoster 主题
# export STARSHIP_CONFIG=~/.config/starship-zsh.toml
# eval "$(starship init zsh)"

# dk = 在当前目录打开 Thunar
alias dk='thunar -q; thunar . &>/dev/null &!'

# cf = 复制当前目录路径到剪切板
cf() {
    if command -v wl-copy &>/dev/null; then
        pwd | wl-copy
    elif command -v xclip &>/dev/null; then
        pwd | xclip -selection clipboard
    else
        echo "cf: 未找到 wl-copy 或 xclip" >&2
        return 1
    fi
    echo "已复制: $PWD"
}



# x-cmd 初始化（zsh 包装）
export PATH="$HOME/.x-cmd.root/local/data/pkg/sphere/X/l/j/h/bin:$HOME/.x-cmd.root/bin:$PATH"
x() {
    ___X_CMD_REAL_CALLER_SHELL=zsh \
    ___X_CMD_RUNMODE=9 \
    bash "$HOME/.x-cmd.root/bin/___x_cmdexe_exp" "$@"
}

[ ! -f "$HOME/.x-cmd.root/X" ] || . "$HOME/.x-cmd.root/X" # boot up x-cmd.

# 手动加载 x-cmd 的 zsh-autosuggestions（已通过 x theme feature use zshplugin never 禁用自动加载中的 syntax-highlighting）
___x_cmd zshplugin load zsh-autosuggestions zsh-config

alias lazyvim="NVIM_APPNAME=lazyvim nvim"

export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:./node_modules/.bin"
