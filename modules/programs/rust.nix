{
  config,
  pkgs,
  ...
}: {
  # ── Rust 语言工具链 (2026-08-29) ──────────────────────────────────────────
  # 系统级安装 Rust 工具链，rustaceanvim (nvim) 从 PATH 调用 rust-analyzer
  # 提供补全/诊断/跳转，rustfmt 提供保存时格式化，clippy 作为
  # rust-analyzer 的 check.command。项目级多版本/nightly 切换由各项目
  # flake devShell + direnv 负责，此处只装一份稳定基线工具链。
  environment.systemPackages = [
    pkgs.rustc # 编译器
    pkgs.cargo # 包管理器 / 构建工具
    pkgs.rustfmt # 代码格式化 (rustaceanvim format_on_save 依赖)
    pkgs.clippy # Linter (rust-analyzer check.command=clippy 依赖)
    pkgs.rust-analyzer # LSP 服务端（nvim 补全/诊断/跳转依赖）
  ];
}
