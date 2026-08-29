{
  # ── Rust 语言工具链 (2026-08-29 清理) ──────────────────────────────
  # 已移除全局安装：rust 工具链（rustc/cargo/rustfmt/clippy/rust-analyzer）
  # 全部走项目 flake devShell + direnv。
  #
  # 原因（2026-08-29 高温病根）：
  #   系统 profile 的 rust-analyzer 2026-06-01 在 PATH 中优先于项目
  #   devShell 的 rust-overlay 1.98.0，且 FSEvents 监听 .direnv/ 触发
  #   reindex 风暴 → 单核 95% 持续高温。
  #   移除后：任何 Rust 项目内由 devShell 提供工具链，无 PATH 冲突。
  #
  # 项目模板: templates/rust/flake.nix（rust-overlay，版本随项目锁）。
  # 新建项目: nix flake init -t /etc/nix-darwin#rust 或 new-rust-proj.sh
}
