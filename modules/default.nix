# Aggregated nix-darwin modules. Ordered: overlays first (so downstream
# package references see the overridden attrs), then system config, shell,
# programs, and fixups. Order within each group is irrelevant — nix-darwin
# merges all module outputs.
{
  imports = [
    # ── Overlays (must precede package references that use overrides) ──
    ./overlays

    # ── System ─────────────────────────────────────────────────────────
    ./system/nix.nix
    ./system/homebrew.nix
    ./system/users.nix # 用户声明:uid/home/knownUsers(登录 shell 见 shell/login-shell.nix)
    ./system/packages.nix
    ./system/activation.nix
    ./system/pam.nix
    ./system/nitter.nix # self-hosted Nitter (x-tweet-fetcher timeline backend)

    # ── Shell ──────────────────────────────────────────────────────────
    ./shell/default.nix
    ./shell/aliases.nix
    ./shell/env.nix
    ./shell/nushell.nix # 生成 ~/.config/nushell/env.nu(PATH/代理,与 zsh 同源)
    ./shell/login-shell.nix # shell 切换器:登录 shell = 调度器,`sw nu|zsh` 即时切换
    ./shell/plugins.nix
    ./shell/functions.nix

    # ── Programs ───────────────────────────────────────────────────────
    ./programs/direnv.nix
    ./programs/elm.nix
    ./programs/rust.nix
    ./programs/tmux.nix
    ./programs/fetch.nix

    # ── Fixes / workarounds ────────────────────────────────────────────
    ./fixes/ssh-config.nix
    ./fixes/dasd-freeze.nix
  ];
}
