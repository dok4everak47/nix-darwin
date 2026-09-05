{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # ── Binary cache: official cache.nixos.org only ──────────────────────
  # 2026-08-24: SJTU mirror 频繁超时/挂起, darwin-rebuild 卡死在
  # "querying ... on mirror.sjtu.edu.cn"; 换回官方单源。如需镜像,
  # 放官方之后做 fallback, 不要放第一位。
  # substituters / trusted-public-keys / trusted-users 由 nix-darwin 默认提供,
  # 这里只补充 flake 特有的项避免 mkMerge 重复。
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
  # which is GFW-blocked (EOF). cache.nixos.org stays first (official mirror).
  nix.settings.substituters = [
    "https://cache.nixos.org/"
    "https://cache.numtide.com"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  # ── Proxy for nix-daemon ────────────────────────────────────────────
  # nix-daemon 是 root 常驻进程，从 launchd 启动时不继承 shell 代理变量，
  # 直连 cache.nixos.org 被墙。nix.envVars 是官方设计给 daemon 注入环境
  # 的入口：会写入 launchd daemon plist 的 EnvironmentVariables + 系统变量。
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
