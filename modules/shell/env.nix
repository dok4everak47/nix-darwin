{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
  # shell / nushell 与 GUI agent 共用同一份代理变量, 两边永不漂移。
  proxyVars = shared.proxyEnv // shared.shellProxyExtra;

  # 每次登录把代理变量注入"用户 launchd domain"的脚本。
  # 为什么不是 launchd.user.envVariables: 那个只在 `darwin-rebuild switch`
  # 激活时跑一次 launchctl setenv, 值活不过重启; RunAtLoad 用户 agent 每次
  # 登录重放一遍, 才是 GUI app 能稳定继承到代理的原因。
  proxySetenvScript = lib.concatMapStrings (
    name: "launchctl setenv ${name} '${proxyVars.${name}}'\n"
  ) (lib.attrNames proxyVars);
in {
  # ── Global environment ───────────────────────────────────────────────
  # environment.variables 被 nix-darwin 渲染进 set-environment, 由 /etc/zshenv
  # source → 覆盖**所有 zsh**(含非交互) 与 nushell (shell/nushell.nix 从同一
  # config.environment.variables 生成 env.nu)。
  #
  # 注意: 它**不会**进 launchd (2026-09-23 复核: 活动系统的 activate /
  # activate-user 里没有任何 launchctl setenv, 且 `launchctl getenv EDITOR`
  # 为空) —— Dock/Finder 启动的 GUI app 看不到它, GUI 侧靠下面的 user agent 补。
  #
  # LANG 声明在 system/packages.nix (单独的事, 挨着它自己的注释)。
  environment.variables =
    {
      EDITOR = "nvim";
      VISUAL = "nvim";
      GIT_EDITOR = "nvim";

      # ── Ghidra / JDK, for REA (2026-10-26) ──────────────────────────
      # REA (rea-agents 6.8.0) 的深度原生分析 provider 只读 process.env:
      # 没有配置文件回退, 也没有 CLI flag, 只认 GHIDRA_INSTALL_DIR + JAVA_HOME。
      # 放在这里而不是 ~/.zshrc, 因为本机 ZDOTDIR=/etc/zdotdir 让 ~/.zshenv
      # 永不生效, 而 ~/.zshrc 只覆盖交互 shell —— IDE task runner、npm
      # lifecycle、agent 子进程都读不到, 会报 missing_analysis_engine。
      #
      # Ghidra: 指向 libexec, 因为 REA 校验这三个路径都在它下面:
      #   Ghidra/application.properties / support/analyzeHeadless /
      #   Ghidra/Features/Decompiler/os/mac_arm_64/decompile
      # 用 opt 软链而非 Cellar 版本号路径, brew 升级 ghidra 后无需改这里。
      # 版本要求: REA 的 GhidraReleasePolicy 只接受 12.1.x (见 homebrew.nix)。
      GHIDRA_INSTALL_DIR = "/opt/homebrew/opt/ghidra/libexec";
      # JDK: Ghidra 12.1.x 要求 21+; REA 的 JavaProbe 要求 64-bit full JDK。
      JAVA_HOME = "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home";
    }
    // proxyVars;

  # ── GUI / launchd 的代理环境 ─────────────────────────────────────────
  # 声明式替代原来手写在 ~/Library/LaunchAgents 的 com.dok4ever.proxy-env
  # (那个 plist 及其 ~/.hermes/bin/set-proxy-env.sh 现已冗余, 可删)。
  # 与 shell 同一来源 (shared.proxyEnv), 所以不会再出现 "终端一套 no_proxy /
  # GUI 另一套" 的分裂。
  launchd.user.agents.proxy-env = {
    serviceConfig.RunAtLoad = true;
    script = proxySetenvScript;
  };
}
