{
  config,
  pkgs,
  ...
}: {
  # ── Zsh (nix-darwin writes /etc/{zshenv,zprofile,zshrc}) ────────────
  # Autosuggestions + syntax-highlighting + fzf-tab come from antidote
  # (~/.zsh_plugins.txt), so we don't enable nix-darwin's built-in copies
  # (they'd double-source and conflict).
  #
  # ZDOTDIR 迁移 (2026-09-17, 见 shell/zdotdir.nix): 交互/登录配置已搬进
  # /etc/zdotdir (nix store), programs.zsh 只负责生成 /etc/{zshenv,zprofile,
  # zshrc} 基座 (history/bindkey/enableCompletion 尾块/set-environment)。
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # ── 根治: macOS 更新覆盖 /etc/zshrc + /etc/zprofile ────────────────
  # 两个文件都在 nix-darwin 的 overridable 列表里, 系统写入 Apple 原版
  # 真实文件后 nix 不强制链接 (2026-09-10 / 2026-09-17 两次实测)。
  # ZDOTDIR 迁移后被盖已无功能影响 (配置在 /etc/zdotdir, 见 shell/zdotdir.nix),
  # 钩子保留: 拉回 nix 版维持托管确定性。/etc/zshenv 是 ZDOTDIR 入口
  # (Apple 从不写它, 纯保险) → 一起 relink。
  system.activationScripts.forceNixShellEtc = {
    deps = [ "etc" ];
    text = ''
      ln -sfn /etc/static/zshrc /etc/zshrc
      ln -sfn /etc/static/zprofile /etc/zprofile
      ln -sfn /etc/static/zshenv /etc/zshenv
    '';
  };

  # ── PATH additions + ZDOTDIR ────────────────────────────────────────
  # Moved to shell/zdotdir.nix (programs.zsh.shellInit → /etc/zshenv)。
  # 原 NOTE: 不能用 environment.variables.PATH —— nix-darwin 写进
  # /etc/launchd-environment (空格分隔, 无 shell 展开), $HOME/$path 必须
  # 在 shell 启动时求值。

  # ── Prompt: pure (sindresorhus/pure) ─────────────────────────────────
  # pure self-activates via antidote in plugins.nix (zshRc, assembled into
  # /etc/zdotdir/.zshrc):
  # the bundle sources pure.plugin.zsh, which ends with prompt_pure_setup.
  # IMPORTANT: nix-darwin's zsh module ships a DEFAULT promptInit that runs
  # `prompt suse`, and it runs AFTER interactiveShellInit in /etc/zshrc -
  # so if left enabled it would clobber pure's PROMPT. Override to empty
  # here. starship removed 2026-08.
  programs.zsh.promptInit = "";

  # ── User packages that lived in home.packages under HM ─────────────
  # atuin is provided by the overlay in modules/overlays/ (patched unstable);
  # it must be on PATH because `atuin init` emits a bare `atuin` call.
  # fzf MUST be on PATH too: plugins.nix sources fzf's key-bindings by absolute
  # path, but fzf-tab and zoxide's interactive `zi`/space-Tab invoke the bare
  # `fzf` binary at runtime. Without this it silently does nothing on Tab.
  environment.systemPackages = [
    pkgs.zoxide
    pkgs.atuin
    pkgs.fzf

    # Batch `exec zsh` for herdr shell panes after a rebuild (skips nvim /
    # agent panes via foreground-process check). Source: herdr-reload-shells.sh
    # next to this file; writeShellScriptBin gives it nixpkgs bash (mapfile OK).
    (pkgs.writeShellScriptBin "herdr-reload-shells" (builtins.readFile ./herdr-reload-shells.sh))
  ];
}
