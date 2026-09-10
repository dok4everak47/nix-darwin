{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Zsh (nix-darwin writes /etc/{zshenv,zprofile,zshrc}) ────────────
  # Autosuggestions + syntax-highlighting + fzf-tab come from antidote
  # (~/.zsh_plugins.txt), so we don't enable nix-darwin's built-in copies
  # (they'd double-source and conflict).
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # ── 根治: macOS 更新覆盖 /etc/zshrc ──────────────────────────────
  # /etc/zshrc 在 nix-darwin 的 overridable 列表里, 系统写入 Apple 原版
  # 真实文件后 nix 不强制链接 → zsh 静默丢失 antidote/补全/alias
  # (2026-09-10 实测: store 里 generation 189 的 /etc/zshrc 是完整的,
  # 磁盘上的却被 09-03 的 Apple 原版占据, zsh 裸奔)。每次 rebuild 在
  # etc 阶段之后强制 ln 回 nix 生成的版本, 被覆盖也自动恢复。
  system.activationScripts.forceNixZshrc = {
    deps = [ "etc" ];
    text = "ln -sfn /etc/static/zshrc /etc/zshrc";
  };

  # ── PATH additions ───────────────────────────────────────────────────
  # NOTE: cannot use `environment.variables.PATH = [ ... ]` because nix-darwin
  # writes that to /etc/launchd-environment (space-separated, no shell
  # expansion); $HOME/$path must be evaluated at shell startup, so we use
  # programs.zsh.shellInit (runs for every zsh, including non-interactive).
  # Re-asserted in plugins.nix interactiveShellInit after `brew shellenv`.
  programs.zsh.shellInit = shared.pathInit;

  # ── Prompt: pure (sindresorhus/pure) ─────────────────────────────────
  # pure self-activates via antidote in plugins.nix (interactiveShellInit):
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
