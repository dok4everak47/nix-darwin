{
  config,
  pkgs,
  ...
}: {
  # ── Shell aliases ────────────────────────────────────────────────────
  # 原 environment.shellAliases (→ /etc/zprofile, macOS 更新会盖)。
  # ZDOTDIR 迁移后改写进 /etc/zdotdir/.zprofile (nix store, 免疫更新),
  # 由 shell/zdotdir.nix 组装。
  #
  # NOTE: environment.shellAliases 置空避免双处维护漂移。副作用: bash 的
  # /etc/bashrc 不再有这些别名 —— 本机登录 shell 是 swsh (nu/zsh), bash 无
  # 交互依赖, 可接受 (2026-09-17)。
  #
  # "--" 别名 ("-" / "--" → cd) 不能放这里: 登录 rc 阶段 zsh 对
  # `alias -=` 报 "bad option: -=" (迁移前同理, 它们在 plugins.nix 的
  # 交互段里用 `alias --` 定义)。
  environment.shellAliases = {};

  dok4ever.shell.zprofileRc = ''
    alias ls=eza
    alias ll='eza -lah --classify --sort=type'
    alias la='eza -a'
    alias tree='eza --tree'
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
    alias c=clear
    alias cls=clear
    alias v=nvim
    alias vi=nvim
    alias cat=bat
    alias em='emacs -nw'

    # grep 彩色
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'

    # git 常用
    alias g='git'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git pull'
    alias gd='git diff'
    alias gco='git checkout'
    alias gb='git branch'

    # 其它常用
    alias h='history'
    alias j='jobs'

    # nix-darwin rebuild
    alias drs='darwin-rebuild switch'
    alias drb='darwin-rebuild build'
  '';
}
