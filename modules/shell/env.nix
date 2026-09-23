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
