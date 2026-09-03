{
  config,
  pkgs,
  lib,
  ...
}: let
  shared = import ../lib.nix {};
  home = shared.home;
  # ── Self-hosted Nitter (x-tweet-fetcher timeline backend) ─────────────
  # 2026-09-01: public Nitter instances are unreliable (nitter.net offline,
  # tiekoetter 429, etc). x-tweet-fetcher (xtf) needs a Nitter instance for
  # user timelines — self-host locally so `xtf --user` is dependable.
  #
  # Architecture (matches upstream docker-compose, minus PostgreSQL which
  # only backs guest-account login — timelines work without it):
  #   Redis   → nix-darwin services.redis (launchd user agent, :6379)
  #   Nitter  → launchd user agent, HTTP on 127.0.0.1:8788
  #
  # xtf talks to it via XTF_NITTER=http://127.0.0.1:8788 (its default).
  #
  # Nitter reads ./nitter.conf from its CWD (no env-var override), so the
  # agent runs with CWD=${home}/.nitter where the config + hmac live. The
  # static dir is an absolute store path, so no public/ copy is needed.
  #
  # launchd gives the agent a clean PATH — every command below uses
  # absolute store paths.

  nitterConfTemplate = pkgs.writeText "nitter.conf.tpl" ''
    [Server]
    hostname = "localhost"
    title = "nitter"
    address = "127.0.0.1"
    port = 8788
    https = false
    httpMaxConnections = 100
    staticDir = "${pkgs.nitter}/share/nitter/public"

    [Cache]
    listMinutes = 240
    rssMinutes = 10
    redisHost = "127.0.0.1"
    redisPort = 6379
    redisPassword = ""
    redisConnections = 20
    redisMaxConnections = 30

    [Config]
    hmacKey = "__HMAC__"
    base64Media = false
    enableRSS = true
    enableDebug = false
    proxy = "http://127.0.0.1:7890"
    proxyAuth = ""
    maxConcurrentReqs = 2
    maxRetries = 3
    retryDelayMs = 250

    [Preferences]
    theme = "Nitter"
    replaceTwitter = ""
    replaceYouTube = ""
    replaceReddit = ""
    proxyVideos = false
    hlsPlayback = false
    infiniteScroll = false
  '';
in {
  services.redis = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    # /var/lib/redis needs root and nix-darwin doesn't create it; use a
    # user-writable dir instead (redis runs as a LaunchAgent).
    dataDir = "${home}/.redis";
  };

  launchd.user.agents.nitter = {
    path = [
      pkgs.nitter
      pkgs.redis
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
    ];
    script = ''
      # Ensure the Redis data dir exists (LaunchAgent runs as user).
      ${pkgs.coreutils}/bin/mkdir -p "${home}/.redis"

      # Wait for Redis (launchd user agents have no ordering guarantee).
      for i in $(${pkgs.coreutils}/bin/seq 1 30); do
        if ${pkgs.redis}/bin/redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q PONG; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      # Working dir: ~/.nitter (writable) — nitter reads ./nitter.conf here.
      ${pkgs.coreutils}/bin/mkdir -p "${home}/.nitter"

      # Persist a stable hmac across launches (signs media URLs).
      if [ ! -f "${home}/.nitter/hmac" ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > "${home}/.nitter/hmac"
      fi
      HMAC=$(${pkgs.coreutils}/bin/cat "${home}/.nitter/hmac")

      # Materialize nitter.conf from the store template.
      ${pkgs.gnused}/bin/sed "s/__HMAC__/$HMAC/" "${nitterConfTemplate}" > "${home}/.nitter/nitter.conf"

      cd "${home}/.nitter"
      exec ${pkgs.nitter}/bin/nitter
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "${home}/.nitter";
      # macOS 27 fix: nixos-unstable nitter links its own OpenSSL 3.6.3
      # (gjv48s39) which SIGSEGVs in Nim async SSL (SSL_CTX_new). The 26.05
      # openssl build (0ml04i57) is stable — force-load it via DYLD.
      EnvironmentVariables = {
        DYLD_LIBRARY_PATH = "/nix/store/0ml04i576l0s285pngbhznr02hn917rs-openssl-3.6.3/lib";
      };
      StandardOutPath = "/tmp/nitter.stdout.log";
      StandardErrorPath = "/tmp/nitter.stderr.log";
    };
    managedBy = "services.nitter.enable";
  };
}
