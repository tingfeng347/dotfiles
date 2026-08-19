test ! -e "$HOME/.x-cmd.root/local/data/fish/rc.fish" || source "$HOME/.x-cmd.root/local/data/fish/rc.fish" # boot up x-cmd.
if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""
set -gx TERMINFO_DIRS /usr/lib/kitty/terminfo:/usr/share/terminfo
set -p PATH ~/.local/bin
set -gx STARSHIP_CONFIG ~/.config/starship.toml
starship init fish | source
zoxide init fish --cmd cd | source

# fzf tab completion
bind tab _fzf_tab_completion
bind --mode insert tab _fzf_tab_completion

# Alt+C: fzf 选择目录并 cd
set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --exclude .git --exclude node_modules 2>/dev/null'
bind \ec '_fzf_cd; commandline -f repaint'
bind --mode insert \ec '_fzf_cd; commandline -f repaint'
function _fzf_cd
    set -l dir (eval $FZF_ALT_C_COMMAND | fzf --height=40% --reverse --preview 'eza --icons --tree --level=1 {}' --preview-window=right:50% --bind 'tab:down,shift-tab:up')
    test -n "$dir" && builtin cd "$dir"
end

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function cat 
	command bat $argv
end

function ls
	command eza --icons $argv
end
function lt
	command eza --icons --tree $argv
end

# grub
abbr grub 'LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
# fa运行fastfetch
abbr fa fastfetch
abbr reboot 'systemctl reboot'
function sl 
	command sl | lolcat	
end

function 安装
	command yay -S $argv
end

function 卸载
	command yay -Rns $argv
end 

set -gx PATH $PATH ./node_modules/.bin

# Tokyo Night 配色 for eza
set -gx EZA_COLORS "di=38;2;122;162;247:ex=38;2;158;206;106:fi=38;2;192;202;245:ln=38;2;125;207;255:pi=38;2;224;175;104:so=38;2;187;154;247:bd=38;2;224;175;104:cd=38;2;224;175;104:or=38;2;247;118;142"

# dk = 在当前目录打开 Thunar
function dk
    thunar -q 2>/dev/null
    nohup thunar . >/dev/null 2>&1 &
    disown
end

# cf = 复制当前目录路径到剪切板
function cf
    if command -q wl-copy
        pwd | wl-copy
    else if command -q xclip
        pwd | xclip -selection clipboard
    else
        echo "cf: 未找到 wl-copy 或 xclip" >&2
        return 1
    end
    echo "已复制: $PWD"
end

# 切换到zsh
function zsh_switch
    command zsh $argv
    echo "已返回 fish shell"
end
abbr zz zsh_switch

# conda: 按需加载，使用 conda-on 激活
function conda-on
    if not set -q CONDA_SHLVL
        eval /opt/miniconda3/bin/conda "shell.fish" "hook" $argv | source
        echo "conda 已激活"
    else
        echo "conda 已经在运行中"
    end
end

function conda-off
    if set -q CONDA_SHLVL
        while test $CONDA_SHLVL -gt 0
            eval /opt/miniconda3/bin/conda "shell.fish" "deactivate" $argv | source
        end
        # 清理 PATH 中的 conda 路径
        set -gx PATH (string match -ev /opt/miniconda3 $PATH)
        set -e CONDA_SHLVL CONDA_EXE _CONDA_EXE _CONDA_ROOT CONDA_PREFIX CONDA_PROMPT_MODIFIER
        functions -e conda
        echo "conda 已关闭"
    else
        echo "conda 未激活"
    end
end

# 终端代理：`proxy_on [端口]`，未传端口时默认使用 7897。
function proxy_on
    if test (count $argv) -gt 1
        echo "用法：proxy_on [1-65535 端口]" >&2
        return 2
    end

    set -l port 7897
    if test (count $argv) -eq 1
        set port $argv[1]
    end
    if not string match -qr '^[0-9]+$' -- $port; or test $port -lt 1; or test $port -gt 65535
        echo "用法：proxy_on [1-65535 端口]" >&2
        return 2
    end

    set -l http_proxy_url http://127.0.0.1:$port
    set -l socks_proxy_url socks5://127.0.0.1:$port

    set -gx http_proxy $http_proxy_url
    set -gx https_proxy $http_proxy_url
    set -gx all_proxy $socks_proxy_url
    set -gx HTTP_PROXY $http_proxy_url
    set -gx HTTPS_PROXY $http_proxy_url
    set -gx ALL_PROXY $socks_proxy_url
    echo "代理已开启（HTTP: $http_proxy_url；SOCKS5: $socks_proxy_url）"
end

function proxy_off
    set -e http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    echo "代理已关闭"
end

function proxy_status
    echo "--- 代理环境变量 (Proxy Env) ---"
    printf 'http_proxy: %s\\nhttps_proxy: %s\\nall_proxy: %s\\n' \
        (set -q http_proxy; and echo $http_proxy; or echo 未设置) \
        (set -q https_proxy; and echo $https_proxy; or echo 未设置) \
        (set -q all_proxy; and echo $all_proxy; or echo 未设置)
    printf 'HTTP_PROXY: %s\\nHTTPS_PROXY: %s\\nALL_PROXY: %s\\n' \
        (set -q HTTP_PROXY; and echo $HTTP_PROXY; or echo 未设置) \
        (set -q HTTPS_PROXY; and echo $HTTPS_PROXY; or echo 未设置) \
        (set -q ALL_PROXY; and echo $ALL_PROXY; or echo 未设置)

    if not set -q https_proxy
        printf '\n代理状态：未开启\n'
        return 0
    end

    printf '\n--- 连通性测试 (Connectivity) ---\n'
    set -l result (curl --proxy "$https_proxy" --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'HTTP %{http_code}, %{time_total}s' https://www.google.com 2>&1)
    if test $status -eq 0
        echo "测试 Google.com… 成功 ($result)"
    else
        echo "测试 Google.com… 失败 ($result)"
        return 1
    end

    printf '\n--- IP 地理位置 (IP Location) ---\n'
    curl --proxy "$https_proxy" --connect-timeout 5 --max-time 10 -fsS https://ipinfo.io/json; or echo "查询失败"
end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH $HOME/.lmstudio/bin
# End of LM Studio CLI section
