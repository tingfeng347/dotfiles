# dotfiles — 跨发行版一键安装 (Ubuntu / Arch)

个人 shell 与终端工具配置仓库：fish / zsh / starship / tmux / yazi / fzf / LazyVim，支持动态扩充。

## 快速开始

```bash
# 一键安装（交互式选模块，或全装）
./install.sh          # 交互式菜单
./install.sh -y       # 安装全部模块
./install.sh fish zsh tmux yazi fzf lazyvim   # 只装指定模块
./install.sh --dry-run                     # 预览，不做任何修改

# 覆盖/同步本机配置为仓库内容（清理仓库里已删除的旧文件）
./update.sh -y        # 更新全部模块
./update.sh fish zsh  # 只更新指定模块
./update.sh --dry-run

# 本机配置有更新时，反向采集进仓库
./capture.sh -y       # 采集全部
./capture.sh fish     # 只采集指定模块
./capture.sh --dry-run

# 卸载（默认只删配置，保留已装的包）
./uninstall.sh                          # 交互式菜单
./uninstall.sh -y                       # 卸载全部模块
./uninstall.sh --remove-packages        # 同时卸载装过的包（fd/fastfetch 等）
./uninstall.sh --purge                  # 同时删除第三方数据（oh-my-zsh/fisher/tpm 等）
./uninstall.sh fish zsh                 # 只卸载指定模块
./uninstall.sh --dry-run
```

安装器自动检测发行版（`/etc/os-release`）：Arch 走 pacman（`aur:` 前缀走 paru/yay），Ubuntu/Debian 走 apt。冲突文件先备份到 `~/.dotfiles-backup/<时间戳>/` 再覆盖。若本次安装了 fish，会自动执行 `chsh -s` 将其设为默认登录 shell（失败仅警告）。

## 目录结构

```
dotfiles/
├── install.sh          一键安装入口
├── uninstall.sh        卸载入口（默认保留已装的包）
├── update.sh           覆盖/同步本机配置为仓库内容（清理已删除文件）
├── capture.sh          反向采集本机配置进仓库
├── lib/                引擎（扩充模块时无需改动）
│   ├── common.sh       日志/工具函数
│   ├── distro.sh       发行版检测 + 包管理抽象
│   └── deploy.sh       模块发现 + 复制部署
├── modules/            动态扩充点：加一个目录 = 加一个模块
│   ├── fish/           fish + fisher 插件清单
│   ├── zsh/            zsh + oh-my-zsh + 自定义插件清单
│   ├── starship/       starship 提示符主题 (fish/zsh 共用)
│   ├── tmux/           tmux + tpm 插件
│   ├── yazi/           yazi 文件管理器
│   ├── fzf/            fzf + 配套工具（纯包模块）
│   └── lazyvim/        LazyVim 配置 (部署为 ~/.config/lazyvim)
```

## 模块契约

每个 `modules/<name>/` 可选包含：

| 文件                                    | 作用                                                                                                           |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `home/`                               | 相对`$HOME` 的配置树，**复制部署**到 `$HOME` 对应路径                                                |
| `packages.arch` / `packages.ubuntu` | 依赖包清单，每行一个；`aur:` 前缀 = AUR 包（仅 Arch）；`ext:` 前缀 = 仓库缺失的工具（starship/eza/fastfetch），经官方脚本/GitHub releases 装到 `~/.local` |
| `post_install.sh`                     | 可选钩子（被 source 执行）：克隆第三方插件等                                                                   |
| `module.conf`                         | `MODULE_DESC`（菜单描述）、`CAPTURE_PATHS`（采集来源 `源\|仓库内路径`）、`CAPTURE_EXCLUDES`（采集排除）、`CAPTURE_STRIP`（行级隔离：sed 删除本机安装器写入的块） |
| `plugins.txt`                         | 自定义清单（zsh 用：`仓库名\|pin 的 commit`）                                                                 |

新增一个模块 = 复制目录并按需填写上述文件，**无需改引擎、无中央注册表**。

## 设计原则

1. **纯复制部署，不建符号链接**：`install.sh` 把仓库里的配置复制到 `$HOME`。家目录里的配置是独立的真实文件，改坏、误删都不影响仓库；安装前已存在且内容不同的文件先备份到 `~/.dotfiles-backup/<时间戳>/`，内容一致的跳过（重复安装幂等）。本地改完配置后用 `capture.sh` 复制回仓库再 git 同步。
2. **清单而非工作树**：oh-my-zsh、tpm、自定义插件、fisher 托管文件、yazi 插件/flavor 都不入库，只提交固定版本的清单/`package.toml`，由 post_install 钩子或各工具自身拉取：
   - fish：`fish_plugins` + fisher
   - zsh：`plugins.txt`（`仓库\|commit`）+ oh-my-zsh pinned commit
   - tmux：`.tmux.conf` 内 `@plugin` + tpm
   - yazi：`package.toml` 的 rev+hash，post_install 钩子执行 `ya pkg install` 拉取
   - LazyVim：`lazy-lock.json` 锁版本，首次启动自动安装（本机用 `NVIM_APPNAME=lazyvim nvim` 启动）

## 已知事项

- Ubuntu 上 `fd` 的包名是 `fd-find`（二进制 `fdfind`），包清单已区分处理；fish 模块的 post_install 会自动创建 `~/.local/bin/fd` 软链，yazi/lazyvim 等其它用到 `fd` 的模块若未装 fish，可手动 `ln -s $(which fdfind) ~/.local/bin/fd`。
- 旧版 Ubuntu（22.04 及更早）的 apt 仓库没有 `starship`/`eza`/`fastfetch`/`yazi`，清单里用 `ext:` 前缀标记，安装器会经官方脚本或 GitHub releases 预编译包装到 `~/.local/bin`（fastfetch 的 share 装到 `~/.local/share/fastfetch`；yazi 用 musl 静态构建以避免 glibc 版本不足），两个 shell 均已把 `~/.local/bin` 加入 PATH。`~/.local/bin` 不在 PATH 时需自行加入。
- Ubuntu 仓库的 neovim 版本较旧，LazyVim 建议从 GitHub releases 或 ppa 安装新版本，再运行本安装器。
- Ubuntu 22.04 的 apt 自带 fish 3.3.1，太旧（`fzf.fish`/`fifc` 需要 3.4+/3.6+，否则启动报 `set -f` 错误）。fish 模块的 post_install 会自动通过 `ppa:fish-shell/release-3` 升级到 3.7；`fish_plugins` 里把 `fzf.fish` 钉在 `@v9.1`（兼容 fish 3.2+），避免 `fisher update` 拉到要求 fish 4.0 的最新版。
- `./install.sh` 需要 sudo（装包）；以普通用户运行，不要用 root。
- install.sh 会确保 `en_US.UTF-8` locale 已生成（需 sudo 执行 `locale-gen`）；否则 oh-my-zsh 的 agnoster 主题用 `$'\ue0b0'` 时会报 "character not in range"。
- fzf 的 shell 集成（keybind 等）在 fish/zsh 模块内；`modules/fzf` 只负责二进制与配套工具。

## 更新流程

1. 本机改了配置 → `./capture.sh -y` 复制回仓库 → `git diff` 审查 → `git add -A && git commit` → `git push`
2. 另一台机器 → `git pull` → `./install.sh -y`（内容一致的跳过，有冲突的备份后覆盖）
