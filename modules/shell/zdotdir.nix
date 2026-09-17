{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── ZDOTDIR 迁移: 交互/登录配置搬出 /etc/zshrc|zprofile (2026-09-17) ──
  #
  # 故障类别: macOS 更新会把 Apple 原版 /etc/zshrc、/etc/zprofile 盖回来
  # (两者都在 nix-darwin 的 overridable 列表里), 2026-09-10 / 2026-09-17
  # 两次实测。此前靠 activation 钩子在 rebuild 时 relink, 但"更新后 → 下次
  # rebuild 之间"仍是裸奔窗口。
  #
  # 根治: /etc/zshenv 是全 zsh 唯一必读且 Apple 从不自带/覆盖的文件 (本机
  # 2026-07-26 创建至今历次更新免疫), 在其中设 ZDOTDIR=/etc/zdotdir →
  # zsh 的交互 (.zshrc) 和登录 (.zprofile) 配置全部从 nix store 只读目录
  # 读取。/etc/zshrc、/etc/zprofile 从此变成空壳, 被盖成 Apple 原版也
  # 无碍 (Apple 版至多自带一个无害的 compinit)。relink 钩子保留兜底。
  #
  # ⚠️ ZDOTDIR 必须是稳定路径 (/etc/zdotdir), 不能直接写 store 路径:
  # rebuild 后已存在 shell 的环境里还挂着旧 ZDOTDIR 值, herdr-reload-shells
  # exec zsh 时会继承旧值; 稳定路径 + activation 刷新 symlink 才能读到新配置。
  #
  # 执行顺序 (zsh 官方 rc 加载序):
  #   /etc/zshenv (设 ZDOTDIR) → /etc/zshrc (nix 基座, 空壳化) →
  #   /etc/zdotdir/.zshrc (完整交互配置, 末尾 source ~/.zshrc)
  #   登录态另加: /etc/zprofile (空壳) → /etc/zdotdir/.zprofile (别名,
  #   末尾 source ~/.zprofile 的 brew shellenv)
  # 与迁移前 /etc/zshrc → ~/.zshrc 的相对顺序完全一致。

  options.dok4ever.shell = {
    # 交互 zsh 配置内容 (原 programs.zsh.interactiveShellInit 的来源)
    zshRc = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Interactive zsh config, assembled into /etc/zdotdir/.zshrc
        (loaded via ZDOTDIR set in /etc/zshenv).
      '';
    };
    # 登录 zsh 配置内容 (原 environment.shellAliases 的来源)
    zprofileRc = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Login zsh config, assembled into /etc/zdotdir/.zprofile.
      '';
    };
  };

  config = let
    # 交互配置总入口。内容三段: 基座兜底 → zshRc (functions+plugins) → 兜底/收尾。
    zshrcText = ''
      # GENERATED FILE — edit modules/shell/*.nix, not this file.
      # 交互配置总入口: /etc/zshenv 设 ZDOTDIR 指向本目录 (nix store 只读)。
      # macOS 更新盖 /etc/zshrc 也无碍 —— 配置从这里读。

      # ── history / keymap 基座 ──
      # (programs.zsh 基座写在 /etc/zshrc; 该文件被盖成 Apple 原版时缺这些
      #  setopt, 这里兜底。正常状态重复赋同一值, 无副作用。)
      SAVEHIST=2000
      HISTSIZE=2000
      HISTFILE=$HOME/.zsh_history
      setopt HIST_IGNORE_DUPS SHARE_HISTORY HIST_FCNTL_LOCK
      bindkey -e

      # ══ 项目函数 (functions.nix) + 插件链 (plugins.nix) ══
      ${config.dok4ever.shell.zshRc}

      # ══ 兜底: direnv hook ══
      # nix-darwin 的 programs.direnv 把 hook 注入 /etc/zshrc; 该文件被盖后
      # 由此补。正常状态 _direnv_hook 已定义, guard 跳过, 不重复注册。
      (( ''${+functions[_direnv_hook]} )) || eval "$(${pkgs.direnv}/bin/direnv hook zsh)"

      # ══ 兜底: bashcompinit ══
      # (enableCompletion 尾块在 /etc/zshrc; 被盖后由此补)
      (( ''${+functions[bashcompinit]} )) || { autoload -U bashcompinit; bashcompinit; }

      # ══ 用户 rc ══
      # ZDOTDIR 生效后 zsh 不再自动读 ~/.zshrc (kaku.zsh 集成在其末尾),
      # 保持原顺序在这里接上 —— 必须是本文件最后一步。
      [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
    '';

    # 登录 shell 配置。顺序: 别名 → source ~/.zprofile (brew shellenv),
    # 与迁移前 /etc/zprofile → ~/.zprofile 一致。
    zprofileText = ''
      # GENERATED FILE — edit modules/shell/aliases.nix, not this file.
      # 登录 shell 配置: /etc/zshenv 设 ZDOTDIR 指向本目录 (nix store 只读)。
      # macOS 更新盖 /etc/zprofile 也无碍。

      ${config.dok4ever.shell.zprofileRc}

      # ZDOTDIR 生效后 zsh 不再自动读 ~/.zprofile (brew shellenv 在里面),
      # 保持原顺序接上。
      [ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile"
    '';

    zdotdir = pkgs.symlinkJoin {
      name = "zdotdir-zsh";
      paths = [
        (pkgs.writeTextDir ".zshrc" zshrcText)
        (pkgs.writeTextDir ".zprofile" zprofileText)
      ];
    };
  in {
    # ── PATH additions + ZDOTDIR (落入 /etc/zshenv, 所有 zsh 必读) ──
    # NOTE: 不能用 environment.variables.PATH —— nix-darwin 把它写进
    # /etc/launchd-environment (空格分隔, 无 shell 展开); $HOME/$path 必须
    # 在 shell 启动时求值, 所以走 programs.zsh.shellInit (每个 zsh 都跑,
    # 含非交互)。
    programs.zsh.shellInit = shared.pathInit + ''

      # ZDOTDIR 入口 (本模块核心, 见文件头注释)
      export ZDOTDIR="/etc/zdotdir"
    '';

    environment.etc."zdotdir".source = zdotdir;
  };
}
