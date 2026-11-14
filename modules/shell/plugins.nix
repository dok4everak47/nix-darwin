{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Interactive zsh init ─────────────────────────────────────────────
  # Assembled into /etc/zdotdir/.zshrc by shell/zdotdir.nix (ZDOTDIR 迁移:
  # macOS 更新盖 /etc/zshrc 不再影响 zsh)。执行位置 = /etc/zshrc 基座之后、
  # 用户 ~/.zshrc 之前 (zdotdir 尾部 source) —— 与迁移前顺序一致。
  dok4ever.shell.zshRc = ''
    # Aliases starting with `-` can't live in environment.shellAliases
    # (nix-darwin writes those to /etc/zprofile, where zsh errors with
    # "bad option: -="). Define them here with `alias --` in interactive
    # shells only.
    alias -- -= 'cd -'
    alias -- --='cd ..'

    # Kaku 终端:它的 zsh 集成(kaku.zsh,由 ~/.zshrc 末尾 source,晚于本文件)
    # 在 TERM_PROGRAM=Kaku 时会把 Tab 重新绑成自带的 _kaku_tab_widget(走内置
    # expand-or-complete),抢走下面 fzf-tab 的 Tab,导致 fzf 补全不弹出。
    # kaku.zsh 读这个官方开关,置非空即不接管 Tab。必须在 source kaku.zsh 之前
    # 导出(本 interactiveShellInit 早于 ~/.zshrc),新开终端 tab 即生效,无需
    # 重启 Kaku。接受自动建议改用 End / 右箭头。
    export KAKU_SMART_TAB_DISABLE=1

    # Re-assert PATH after ~/.zprofile runs `brew shellenv` (see lib.pathInit).
    ${shared.pathInit}

    # ── antidote (zsh plugin manager) ──────────────────────────────────
    # antidote is a zsh *script*, not a binary: it must be sourced before the
    # `antidote` function exists. Sourcing the nix store copy explicitly means
    # it works in EVERY interactive shell — including non-login shells (tmux
    # panes, IDE terminals) where ~/.zprofile (brew shellenv) never runs.
    # Previously this relied on `antidote` being on PATH, which only held in
    # login shells; in tmux it was `command not found`.
    #
    # ANTIDOTE_HOME: 默认 $HOME/Library/Caches/antidote —— macOS 会定期清理
    # ~/Library/Caches, 缓存被清后 .zsh_plugins.zsh 还在引用旧路径, 报
    # "no such file or directory: .../zsh-autosuggestions.plugin.zsh"。
    # 改到 ~/.local/share/antidote (XDG 数据目录, 系统不清理)。
    export ANTIDOTE_HOME="$HOME/.local/share/antidote"
    source ${pkgs.antidote}/share/antidote/antidote.zsh

    # ── fzf key bindings (MUST precede the antidote bundle) ───────────
    # fzf-tab, when loaded by the bundle below, grabs Tab (`bindkey '^I'
    # fzf-tab-complete`) and wraps whatever widget held Tab before it. fzf's
    # key-bindings.zsh also rebinds Tab -> fzf-completion, so if it is sourced
    # *after* the bundle it clobbers fzf-tab and Tab never opens fzf-tab.
    # Load keybindings first; fzf-tab (in the bundle below) then wraps the
    # current Tab widget and wins. fzf's completion.zsh is deliberately NOT
    # sourced (see the note after the bundle).
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh

    # ── Alt-C: 浏览式 cd (fzf --walker=dir) ───────────────────────────
    # fzf 0.72 自带的 fzf-cd-widget 本身就用 `--walker=dir,follow,hidden` 直接
    # 扫盘, 不走 zsh 的 _path_files —— 大目录(几万条)不会先卡在候选生成上。
    # 补它默认没有的三件事:
    #   --walker-skip  跳过噪音目录(默认只跳 .git,node_modules, 不够);
    #   --preview      选中目录就列出内容;
    #   --height=60%   内联在命令流里, 不开全屏 alt-screen。
    # 注意: 值里不能放带空格的路径(Application Support 之类), fzf 按逗号切分。
    # TermiNai 的 Option 是组合键(option_as_alt 不生效), Alt-C 送不到这里;
    # 实际入口是 zvm after-init 里的 Ctrl+G / ç, 这项留给真实 Meta 终端。
    export FZF_ALT_C_OPTS="--height=60% --walker-skip=.git,node_modules,.direnv,target,dist,Library/Caches,Pods,.venv --preview 'eza -1 --group-directories-first --color=always {}' --bind=ctrl-/:toggle-preview"

    # Rebuild the plugin bundle if it is stale/missing. Generate into a temp
    # file and atomically move it into place: a bare `> ~/.zsh_plugins.zsh`
    # truncates the target BEFORE the command runs, so if `antidote bundle`
    # failed (e.g. command not found) every later shell sourced an EMPTY
    # bundle and silently lost all plugins (fzf-tab, autosuggestions, ...).
    if [[ ! -s ~/.zsh_plugins.zsh || ! ~/.zsh_plugins.zsh -nt ~/.zsh_plugins.txt ]]; then
        if antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh.$$ 2>/dev/null; then
            mv -f ~/.zsh_plugins.zsh.$$ ~/.zsh_plugins.zsh
        else
            rm -f ~/.zsh_plugins.zsh.$$
        fi
    fi

    # ── Completion: case-insensitive (fzf-tab) ───────────────────
    # zsh 默认补全大小写敏感；这里让小写也能匹配大写(cd doc → Documents)
    zstyle ':completion:*' matcher-list 'm:{a-zA-z}={A-Za-z}'

    # ── cd 补全体验 (fzf-tab) ─────────────────────────────────────────
    # accept-exact-dirs: `cd ~/Proj` 命中同名目录即接受, 不再展开它的内容;
    # list-dirs-first:   候选列表里目录排在文件前面, 找 cd 目标不用翻页。
    zstyle ':completion:*' accept-exact-dirs true
    zstyle ':completion:*' list-dirs-first true
    # --height=60%: 内联显示, 不开全屏 alt-screen;
    # --select-1:   只剩一个候选时跳过界面直接采用;
    # Ctrl-/ 手动开关预览。
    zstyle ':fzf-tab:*' fzf-flags --height=60% --select-1 --bind=ctrl-/:toggle-preview
    # cd 候选右侧预览目录内容(eza 由 nix 安装), 选错目录的概率直接归零。
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --group-directories-first --color=always $realpath'

    # Load and run compinit first → compdef is now available for everyone
    #
    # ⚡ 2026-11-13 提速: /etc/zshrc (programs.zsh.enableCompletion) 在
    # ZDOTDIR 生效之前已经跑过一次 compinit, 这里再无条件跑一次 = 白花
    # ~0.12s (交互启动实测 0.34s, 这笔占三分之一)。改成「本 shell 还没
    # compinit 过才跑」:
    #   - 正常终端: /etc/zshrc 已跑过 → 跳过, compdef 照样可用;
    #   - /etc/zshrc 被 Apple 原版覆盖 / 不读全局 rc 时: _comps 为空
    #     → 这里补跑, 与原行为一致。
    if (( ! ''${+_comps} )); then
      autoload -U compinit
      compinit
    fi

    # Load antidote plugins (fzf-tab, autosuggestions, ...). They need compdef.
    # fzf-tab wraps Tab here (fzf keybindings are already loaded above).
    [ -s ~/.zsh_plugins.zsh ] && source ~/.zsh_plugins.zsh

    # ── Prompt: pure (sindresorhus/pure, via antidote bundle above) ──
    # pure.plugin.zsh (sourced by the bundle) ends with `prompt_pure_setup`
    # so it self-activates - NO promptinit/`prompt pure` (that would
    # double-register precmd/preexec hooks). Replaces starship (see
    # modules/shell/default.nix).

    # ── zsh-vi-mode: after-init 是唯一能改键位的地方 ────────────────
    # zvm 把 init 推迟到首个 prompt (precmd_functions+=zvm_init), 执行
    # `bindkey -v` 重建 viins/vicmd —— rc 阶段绑的键全被清掉 (fzf 的
    # ^T/^R/\ec 就是这样丢的), 所以自定义键位必须挂在这个钩子里。
    #
    # KEYTIMEOUT: zvm 在 init 时按 ZVM_KEYTIMEOUT 重算 KEYTIMEOUT, 写在
    # rc 里的值会被它覆盖; 0.4s → 0.1s 让 ESC 进普通模式不再迟滞。
    ZVM_KEYTIMEOUT=0.1

    # fzf 键位先恢复 (^T 文件、^R 历史), 后面 atuin 再把 ^R 抢回来。
    zvm_after_init_commands+=('source ${pkgs.fzf}/share/fzf/key-bindings.zsh')

    # atuin 的 ^R 死因: rc 阶段绑在 viins 的 ^r (在 zvm 之前), 先被
    # `bindkey -v` 清掉, 又被上面 fzf 的 ^R 抢走 → Ctrl+R 实际是
    # fzf-history-widget。atuin 是选定的历史后端, 这里最后绑一次, Ctrl+R
    # 才真正进 atuin 搜索。↑ 保留 zsh 原生历史(更轻); 想要 atuin 版就
    # 再补一行 ^[[A / ^[OA → atuin-up-search-viins。
    zvm_after_init_commands+=('bindkey -M viins "^R" atuin-search-viins')

    # Ctrl+G / Option+C(ç): 浏览式 cd (fzf --walker=dir + eza 预览)。
    # fzf 自带入口是 \ec, 但 TermiNai 不送 Meta, Option+C 实际发出 ç;
    # 直接绑这个字符就绕过了终端的 option_as_alt 限制。^G 原本是
    # send-break, 被占用后中断仍可用 Ctrl+C。
    zvm_after_init_commands+=('bindkey -M viins "^G" fzf-cd-widget; bindkey -M viins "ç" fzf-cd-widget')

    # 编辑器键位补洞: zsh 默认和 zvm 的 viins 都没绑这些, 实测 undefined-key。
    # Ctrl/Alt + ←/→ 跳词, Ctrl+Delete 删词, Shift+Tab 反向菜单。
    zvm_after_init_commands+=('bindkey -M viins "^[[1;5C" forward-word; bindkey -M viins "^[[1;3C" forward-word; bindkey -M viins "^[[1;5D" backward-word; bindkey -M viins "^[[1;3D" backward-word; bindkey -M viins "^[[3;5~" kill-word; bindkey -M viins "^[[Z" reverse-menu-complete')

    # insert 模式连按 jk 代替 ESC —— 2026-09-20 移除 (每个 lone-j 都要等
    # ZVM_KEYTIMEOUT 判断是否按 k)。退出插入模式用 ESC。

    # bun completions
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

    # NOTE: fzf's completion.zsh is intentionally NOT sourced. It ends with an
    # unconditional `bindkey '^I' fzf-completion`, which runs AFTER the bundle
    # above and steals Tab from fzf-tab (its recorded fallback to fzf-tab is
    # unreliable). fzf-tab already provides the fzf-powered Tab completion UI,
    # so fzf's own completion widget is redundant. fzf key bindings (Ctrl-T /
    # Ctrl-R / Alt-C) come from key-bindings.zsh loaded before the bundle.

    # ── zoxide (replaces HM programs.zoxide.enableZshIntegration) ──
    # Loaded after fzf-tab so its `z`/`zi` completions flow through fzf-tab.
    # No `sed`/`if true` hack is needed: zoxide's `if [[ -o zle ]]` block is
    # skipped during rc-file sourcing only (zle activates before the first
    # prompt), yet zoxide compdef still registers `z`'s completion — verified
    # via `_comps[z]=__zoxide_z_complete` — and fzf-tab owns Tab. The hack also
    # printed `can't change option: zle` whenever zsh started without a tty.
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"

    # ── atuin (replaces HM programs.atuin.enableZshIntegration) ────
    eval "$(${pkgs.atuin}/bin/atuin init zsh)"
  '';
}
