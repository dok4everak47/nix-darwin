# AGENTS.md — AI Agent 协作指南

本文件为 AI 编码 agent（Claude Code / Codex / OpenCode / pi / Hermes 等）提供本仓库的工作上下文。修改本配置前请先通读。

## 仓库是什么

个人 macOS (Apple Silicon, `aarch64-darwin`) 的 [nix-darwin](https://github.com/nix-darwin/nix-darwin) 配置，hostname 为 `dok4ever-mac`。

**核心原则：Nix 是控制平面，Homebrew 只承载 nixpkgs 无法（或无法以所需特性集）提供的东西。**

## 铁律（违反会出事故）

1. **语言工具链禁止全局安装**（2026-08-29 高温事故确立）：
   - Rust / Elm / 其他语言的 compiler、LSP、formatter **一律走项目级 flake devShell + direnv**。
   - 系统 profile 只保留系统工具 / 编辑器 / multiplexer / direnv / 字体。
   - 全局装语言工具链的历史事故：系统 rust-analyzer (2026-06-01) PATH 优先于 devShell 的 rust-overlay 1.98.0，叠加 FSEvents 监听 `.direnv/` 触发 reindex 风暴 → 单核 95% 持续高温。
   - 新增语言工具链 → 创建 `templates/<lang>/flake.nix` 模板，不要加进 `systemPackages`。
2. **`modules/lib.nix` 的 `pathInit` 是 PATH 单一事实来源**，`modules/shell/default.nix` 和 `modules/shell/plugins.nix` 都引用它。改 PATH 顺序前想清楚：
   - user nix profile (devShell 装的工具) → nix default profile → system profile → TeX → user bins → /opt/homebrew。
   - imagemagick 2026-09-03 从 brew imagemagick-full 迁到 nixpkgs（packages.nix，ghostscriptSupport=true）——PATH 里不再有 /opt/homebrew/opt/imagemagick-full/bin。
   - 不要重新引入 `/opt/homebrew/opt/ffmpeg-full/bin`（ffmpeg-full 已删，2026-08）。
3. **Homebrew 用 `onActivation.cleanup = "uninstall"`**：任何未在 `homebrew.brews` 声明的顶层公式会在 rebuild 时被卸载。新增 brew 包必须同步声明。
4. **不要引入 Homebrew 能替代 nixpkgs 的 CLI 工具**。CLI 工具走 nixpkgs（`modules/system/packages.nix`），Homebrew 只留 keg-only full builds + casks。
5. **Home-manager 刻意不用**（用户决定，永久）。GUI 应用装 cask 或 nixpkgs，不用 home-manager 包管理。
6. **`nix flake check --no-build` 是改完配置后的最低验证门槛**。改完必须跑，全绿才能交差。

## 结构

```
flake.nix            # 入口：inputs (nixpkgs 26.05 / nix-darwin / unstable pin / nixos-unstable / areofyl-fetch / llm-agents) + specialArgs + templates
flake.lock           # 锁文件
modules/
  lib.nix            # 共享常量：username / home / proxyEnv / pathInit（PATH 单一来源）
  default.nix        # import 汇总（overlays → system → shell → programs → fixes）
  overlays/          # 包级 override（openmp 空 patch 过滤 / opencode codesign 修复 / atuin pin）
  system/            # nix.nix (daemon/GC/proxy) / homebrew.nix / packages.nix / activation.nix
  shell/             # zsh: default (pathInit) / aliases / env / plugins (antidote) / functions
  programs/          # direnv / elm / rust (纯文档) / tmux / fetch
  fixes/             # 已知上游 bug 的 workaround（ssh_config.d 错位）
templates/           # python / node / go / rust / elm 项目模板
scripts/             # npm-proxy-build.sh 等（llm-agents 构建期依赖）
```

## 工作流（改配置的正确姿势）

1. **改**：编辑对应模块，保持现有注释风格（中文注释、区块标题 `# ── xxx ──`）。
2. **验证（build 测试）**：`cd /etc/nix-darwin && nix flake check --no-build` 必须全绿；**每次改完代码后必须先 build 测试过一遍**（`nix build --no-link --print-out-paths '.#darwinConfigurations.dok4ever-mac.system'` 或 `nix flake check`），**如果有报错让 AI 自己改**，改到全绿才能交差，不许把报错留给用户。
3. **rebuild**：用户自己跑 `sudo darwin-rebuild switch --flake .#dok4ever-mac`（agent 无 sudo，不要尝试）。
4. **提交**：`git add -A && git commit`，推送到 `gitea`（SSH, `ssh://git@gitea.luongchin.com:2222/dok4ever/nix-darwin.git`）和 `origin`（GitHub HTTPS, `github.com/dok4everak47/nix-darwin`）。
   - push 需要代理 `127.0.0.1:7890` 在跑（ClashBar）。失败先 `lsof -iTCP:7890` 确认代理，再让用户重启 ClashBar。
   - **本机是 SSH 到 gitea，如果 gitea 连接被劫持/超时，检查 `~/.ssh/config` 的 ProxyCommand。**

## 已知坑

### 代理 (proxy)
- 所有构建/更新走 `http://127.0.0.1:7890`（ClashBar）。`modules/lib.nix` 的 `proxyEnv` 是单一来源，daemon (`nix.envVars`) 和 shell/GUI (`environment.variables`) 都引用它。
- `no_proxy` 含 `feishu.cn / larksuite.com`（飞书 CLI 不走代理）。
- ClashBar 会随机退出 → nix 构建/git push 报网络错时先查代理是否活着。
- npm registry override（llm-agents 的 qwen-code 等）依赖 `scripts/npm-proxy-build.sh` 启动的本地 HTTPS 反向代理 (127.0.0.1:443)。**构建期必须代理在跑**。

### nix-darwin 26.05 上游 bug
- `ssh_config.d/100-nix-darwin.conf` 被错误写到 PAM sudo_local 内容位置（`modules/fixes/ssh-config.nix` 有 mkForce 占位修复）。不要删这个修复。
- openmp 空 patch (`run-lit-directly.patch` 是空文件) 导致 patch(1) 报 "Only garbage was found" → 连锁炸掉 openmp→fftw→vid.stab→ffmpeg→imagemagick 依赖链。`modules/overlays/default.nix` 过滤空 patch。不要删。

### GC / 存储
- 自动 GC：周日 03:00 `--delete-older-than 30d`（`modules/system/nix.nix`）。
- `nix-collect-garbage -d` 可手动清（删除全局工具链后 ~1.5GB 垃圾）。

### 版本 pin 理由（改 inputs 前先读注释）
- `unstable` 固定 rev `6f6fca05`：atuin 18.17.1（含 search-hyphen patch）。
- `nixos-unstable` 滚动：herdr / codex 等新工具。
- `areofyl-fetch` 固定 rev `5297ad4`，follows nixpkgs。
- `llm-agents` 刻意不 follows nixpkgs（README 警告）。
- 任何 pin 都有注释理由，**改前先看注释，别盲改**。

## 验证清单（改完自查）

- [ ] `nix flake check --no-build` 全绿
- [ ] 每次改完代码已先 build 测试过（`nix build --no-link --print-out-paths '.#darwinConfigurations.dok4ever-mac.system'`），报错已自己修掉
- [ ] 没往 `systemPackages` 加语言工具链
- [ ] PATH 顺序没破坏 devShell 优先（`$HOME/.nix-profile/bin` 在 system profile 前）
- [ ] brew 包改动同步了 `homebrew.brews`（cleanup=uninstall 会删未声明的）
- [ ] 注释风格一致（`# ── 区块 ──`）
- [ ] 提交信息遵循 conventional commits（`feat:` / `fix:` / `chore:` / `style:`）

## 不要做的事

- ❌ 不要 sudo / darwin-rebuild（agent 无权限，用户自己跑）
- ❌ 不要加语言工具链到全局
- ❌ 不要重新引入 ffmpeg-full
- ❌ 不要删 fixes/ 里的 workaround（每个都有注释原因）
- ❌ 不要引入 home-manager
- ❌ 不要把 brew 能搞定的 CLI 工具从 nixpkgs 挪到 brew
