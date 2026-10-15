{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # ── Binary cache: SJTUG 思源镜像优先, 官方 cache.nixos.org 兜底 ────
  # 2026-10-15: 用户要求 SJTUG (mirror.sjtu.edu.cn) 优先, 无响应时自动切官方。
  # 列表顺序即优先级: nix 逐个 substituter 查询, 前者没有/失败就用下一个。
  # 镜像站 nix-cache-info 与官方同为 Priority: 40 → 同优先级,
  # 所以真正决定顺序的就是下面的列表顺序; cache.numtide.com 声明 30,
  # 它自己那几个专有路径仍先被它命中 (既有行为, 不受本次改动影响)。
  # ⚠️ 镜像思源在 2026-08-24 曾挂起而被撤下: 挂起时 nix 会按
  # filetransfer-retry-attempts(5) × stalled-download-timeout 重试, 默认 300s → 最长卡 25 分钟才
  # fallback。故下面把 stalled-download-timeout 压到 30s (实测: 卡住 5×30s=150s 后该镜像
  # 被丢弃, 同一条命令后续全部走官方, 一次性代价)。不想要这个
  # 超时覆盖就删掉那行 (回到 300s 默认)。
  # substituters / trusted-public-keys / trusted-users 由 nix-darwin 默认提供;
  # ⚠️ 普通赋值会与默认值 mkMerge 叠加 → 重复项, 所以下面两个列表用 mkForce
  # 整体覆盖 (原因见 numtide 那段)。
  # 默认: substituters = mkAfter [ "https://cache.nixos.org/" ]
  #       trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ]
  #       trusted-users = [ "root" ]
  nix.settings.trusted-users = [shared.username];

  # ── numtide cache for llm-agents (2026-09-06) ────────────────────────
  # llm-agents.nix declares cache.numtide.com in its own flake's nixConfig,
  # but that is IGNORED when the flake is consumed as an input (per numtide
  # flake docs / flake-parts pattern) -- substituters must be declared here.
  # cache.numtide.com hosts the go-modules FOD + prebuilt crush/claude-code
  # binaries; without it, Go source packages (crush) rebuild from proxy.golang.org
  # which is GFW-blocked (EOF). 位置保持在官方之后 (它自己声明 Priority: 30,
  # 自有路径仍会先命中它)。
  #
  # 2026-09-26: 这里必须 mkForce。nix-darwin 26.05 的默认值会把本文件的列表
  # 追加在它自己的默认项之后, 生成两份 cache.nixos.org (实测 /etc/nix/nix.conf
  # 的 substituters 与 trusted-public-keys 各重复一次); mkAfter 还会把 numtide
  # 挤到第一位, 与上面「SJTUG 首选, 官方兜底」的意图相反。mkForce 丢弃默认值,
  # 顺序完全由本文件决定。
  nix.settings.substituters = lib.mkForce [
    "https://mirror.sjtu.edu.cn/nix-channels/store" # SJTUG 思源 (镜像站, 首选)
    "https://cache.nixos.org/"                      # 官方 (兜底, 镜像无响应时自动切到)
    "https://cache.numtide.com"                     # llm-agents 专用缓存
  ];
  # 镜像站只是 cache.nixos.org 的镜像 → 签名仍是 cache.nixos.org-1, 无需额外 key。
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  # 思源挂起保护: 连续 30s 收到 0 字节就 abort 该次下载 (默认 300s),
  # 然后交给下一个 substituter —— 这才让"无响应就切官方"在分钟级而不是半小时级发生。
  nix.settings.stalled-download-timeout = 30;

  # ── Proxy for nix-daemon ────────────────────────────────────────────
  # nix-daemon 是 root 常驻进程，从 launchd 启动时不继承 shell 代理变量，
  # 直连 cache.nixos.org 被墙。nix.envVars 是官方设计给 daemon 注入环境
  # 的入口：会写入 launchd daemon plist 的 EnvironmentVariables + 系统变量。
  # 注意: daemon 是 KeepAlive 常驻进程, 改这里(或代理挂掉)后它**不会**自动
  # 重读环境 —— 需要 sudo launchctl kickstart -k system/org.nixos.nix-daemon。
  nix.envVars = shared.proxyEnv;

  # ── Auto GC: keep /nix/store bounded (encrypted APFS volume is small) ──
  # Per nixos-and-flakes.thiscute.world "Other useful Tips".
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 3;
      Minute = 0;
    }; # Sun 03:00
    options = "--delete-older-than 30d";
  };

  # Auto optimise (dedup hardlinks) after each activation.
  nix.optimise.automatic = true;

  # Dedup on every store import (not just the periodic `nix-store --optimise`).
  # Encrypted APFS volume is small — hardlink duplicate nars as they land.
  nix.settings.auto-optimise-store = true;

  # Enable alternative shell support in nix-darwin.
  # programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before reading.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
