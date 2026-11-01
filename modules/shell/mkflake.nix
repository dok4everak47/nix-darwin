{ config, lib, pkgs, ... }: {
  # ── mkflake: 交互式项目脚手架 ─────────────────────────────────────────
  # 完整 zsh 实现见 modules/shell/mkflake.zsh (随本模块一并写进 nix store)。
  # 这里只在生成的 /etc/zdotdir/.zshrc 里追加一行 source, 把它挂进交互 shell。
  #
  # 走 dok4ever.shell.zshRc (types.lines, 与 functions.nix / plugins.nix 拼接),
  # 位于 base 主体末尾、source ~/.zshrc 之前; 用 mkAfter 保证拼在最后。
  # 这样 mkflake 由 nix-darwin 托管: darwin-rebuild 后稳定存在, 不再依赖
  # 手改 ~/.zshrc (那只是 base 末尾 source 的可写 overlay, 易丢)。
  dok4ever.shell.zshRc = lib.mkAfter ''
    # ── mkflake：从 /etc/nix-darwin/templates 快速生成项目骨架 ──
    # (完整实现: modules/shell/mkflake.zsh, 由下面这行 source)
    source ${pkgs.writeText "mkflake.zsh" (builtins.readFile ./mkflake.zsh)}
  '';
}
