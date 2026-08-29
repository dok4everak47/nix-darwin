{
  # ── Elm 语言工具链 (2026-08-29 清理) ──────────────────────────────
  # 已移除全局安装：elm 工具链（elm / elm-format / elm-test-rs /
  # elm-review / elm-language-server / elm2nix）全部走项目 flake
  # devShell + direnv。
  #
  # 原因（2026-08-29 清理）：
  #   与 rust 套件同理，系统 profile 全局装的语言工具链会与项目
  #   devShell 版本冲突、PATH 优先级混乱。项目内由 direnv 提供。
  #
  # 项目模板: templates/elm/flake.nix（elm 0.19 编译器 + 工具链）。
  # 新建项目: nix flake init -t /etc/nix-darwin#elm
}
