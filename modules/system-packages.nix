{ config, pkgs, ... }:

{
  # Packages installed in system profile. To search by name, run:
    # opencode (bun 编译产物) 修复: macOS 27 上签名校验失败被 SIGKILL。
  # bun 1.3.13 编译出的二进制 adhoc 签名无效 (codesign --verify 报
  # "code or signature have been modified"), 一运行就被杀 ("Killed: 9")。
  # 处理: 跳过构建期所有执行该二进制的环节 (冒烟测试/版本检查/completion),
  # fixup 阶段用 adhoc 重新签名。已验证产物:
  # /nix/store/g5rkdxik56x2p8fg3g5flw31dmi72z0k-opencode-1.15.10
  nixpkgs.overlays = [
    (final: prev: {
      opencode = prev.opencode.overrideAttrs (old: {
        dontStrip = true;
        postPatch = (old.postPatch or "") + ''
          substituteInPlace packages/opencode/script/build.ts \
            --replace-fail "if (item.os === process.platform" \
                          "if (false && item.os === process.platform"
        '';
        doInstallCheck = false;
        postInstall = "";
        postFixup = (old.postFixup or "") + ''
          /usr/bin/codesign --force --sign - "$out/bin/.opencode-wrapped"
        '';
      });
    })
  ];
  # $ nix-env -qaP | grep wget
  #
  # 2026-08: starship init 通过 programs.zsh.promptInit 接入；fzf/atuin
  # 安装在 modules/shell.nix；direnv 由 programs.direnv.enable 自动提供;
  # taskwarrior3/taskwarrior-tui/vit 已迁移 htask, 遗留已删。
  environment.systemPackages = [
    pkgs.vim
    pkgs.neovim
    pkgs.fastfetch
    pkgs.wget
    pkgs.curl
    pkgs.bat
    pkgs.eza
    pkgs.himalaya
    pkgs.neomutt
    pkgs.isync
    pkgs.yazi
    (pkgs.emacs.override {
      withXwidgets = true;
      withXinput2 = true;
    }) # Emacs 30 + xwidget-webkit (内嵌浏览器, 跑 CSS/JS)
    pkgs.fd
    pkgs.zoxide
    pkgs.imagemagick
    pkgs.nmap
    pkgs.tmux
    pkgs.nil
    pkgs.alejandra
    pkgs.ghostty-bin
    pkgs.zed-editor
    pkgs.mdcat
    pkgs.opencode
    # NOTE: ghostty 在 nixpkgs (26.05 / unstable 6f6fca0) 的 meta.platforms 仅
    # 列 Linux,aarch64-darwin 上求值会直接报 "not available on the requested
    # hostPlatform"。macOS 走 Homebrew Cask 安装官方 .app:
    #   brew install --cask ghostty
  ];

  # ── LANG (2026-08-14) ────────────────────────────────────────────────
  # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
  # 从系统读 locale → 启动警告 "LANG=en_CN.UTF-8 cannot be used"。
  # environment.variables 写入 launchd 环境, GUI 应用 (Dock 启动的 Emacs)
  # 都需要这里显式设置; 终端 shell 的 LANG 在 home.nix envExtra 里。
  environment.variables.LANG = "en_US.UTF-8";
}
