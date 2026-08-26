{
  config,
  pkgs,
  ...
}: {
  # ── Elm 语言工具链 (2026-08-23) ──────────────────────────────────────────
  # 通过 nix 安装，避免 vs code 保存时 "Cannot read properties of null"
  # 之类因缺少 elm-format 导致的格式化失败。
  environment.systemPackages = [
    # 注意：elm 编译器本体已从系统移除，避免与项目 flake 提供的 0.19.2 冲突。
    # 在 Elm 项目目录内由 direnv + flake 提供 elm；项目外如需编译器请进入相应项目。
    pkgs.elmPackages.elm-format # 代码格式化 (0.8.8)
    pkgs.elmPackages.elm-test-rs # 测试运行器 (3.0.1)
    pkgs.elmPackages.elm-review # Linter (2.13.5)
    pkgs.elmPackages.elm-language-server # LSP 服务端（nvim 补全/诊断/跳转依赖它）
    pkgs.elm2nix # elm.json → nix 表达式 (0.4.0)
  ];
}
