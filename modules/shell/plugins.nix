{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Interactive zsh init ─────────────────────────────────────────────
  # nix-darwin sources this in /etc/zshrc AFTER compinit setup; it runs
  # before the user's ~/.zshrc.
  programs.zsh.interactiveShellInit = ''
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

    # Load and run compinit first → compdef is now available for everyone
    autoload -U compinit
    compinit

    # Load antidote plugins (fzf-tab, autosuggestions, ...). They need compdef.
    # fzf-tab wraps Tab here (fzf keybindings are already loaded above).
    [ -s ~/.zsh_plugins.zsh ] && source ~/.zsh_plugins.zsh

    # ── Prompt: pure (sindresorhus/pure, via antidote bundle above) ──
    # pure.plugin.zsh (sourced by the bundle) ends with `prompt_pure_setup`
    # so it self-activates - NO promptinit/`prompt pure` (that would
    # double-register precmd/preexec hooks). Replaces starship (see
    # modules/shell/default.nix).

    # ── zsh-vi-mode: re-apply fzf bindings clobbered by zvm init ─────
    # zsh-vi-mode defers init to the first prompt (precmd_functions+=zvm_init,
    # verified in source) and then OVERWRITES all prior keybindings — which
    # kills the fzf ^T/^R/Alt-C bindings sourced before the bundle above.
    # README's official fix: re-source them from the after-init hook.
    # Safe for fzf-tab: key-bindings.zsh only binds ^T/\ec/^R, never Tab.
    # (zvm declares these arrays without resetting them at source time, so
    # appending here — after the bundle — is the documented pattern.)
    zvm_after_init_commands+=('source ${pkgs.fzf}/share/fzf/key-bindings.zsh')

    # insert 模式下连按 jk 代替 ESC 进 normal(仅 insert 生效,normal 里
    # j/k 的移动/历史功能不受影响)。必须在第一个 prompt(zvm init)之前
    # 设置,这里满足。若觉得 lone-j 提交有延迟,可再调 ZVM_KEYTIMEOUT(默认 0.4s)。
    ZVM_VI_INSERT_ESCAPE_BINDKEY=jk

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
