{
  config,
  pkgs,
  llm-agents,
  ...
}: {
  # Packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  #
  # 2026-08: prompt 改用 sindresorhus/pure (经 antidote 加载,见 modules/shell/)；
  # fzf/atuin 安装在 modules/shell/；direnv 由 programs.direnv.enable 自动提供;
  # taskwarrior3/taskwarrior-tui/vit 已迁移 htask, 遗留已删。
  #
  # tmux (2026-08): moved to modules/programs/tmux.nix — programs.tmux.enable
  # ships a wrapped tmux (-f /etc/tmux.conf); a bare pkgs.tmux here would collide.
  # Homebrew takeover (2026-08): CLI tools migrated here from brew.
  # ffmpeg-full / imagemagick-full stay on Homebrew (full feature set),
  # managed in modules/system/homebrew.nix and prioritized in shell PATH.
  #
  # Overlays (openmp empty-patch filter, opencode codesign fix, atuin from
  # unstable with search patch) live in modules/overlays/.
  environment.systemPackages = with pkgs; [
    vim
    neovim
    fastfetch
    wget
    curl
    bat
    eza
    himalaya
    neomutt
    isync
    yazi
    (emacs.override {
      withXwidgets = true;
      withXinput2 = true;
    }) # Emacs 30 + xwidget-webkit (内嵌浏览器, 跑 CSS/JS); GUI at /Applications/Nix Apps/Emacs.app
    fd
    nmap
    nil
    alejandra
    ghostty-bin
    zed-editor
    mdcat
    opencode
    nix-search-cli
    cliamp
    pi-coding-agent
    herdr
    cinny-desktop
    codex

    # ── Migrated from Homebrew ────────────────────────────────────────
    antidote # zsh plugin manager (replaces /opt/homebrew/opt/antidote)
    cmake
    delta # git-delta
    jq
    lazygit
    nb
    ntfy
    poppler-utils # pdftotext, pdfinfo, ... (poppler is the GLib lib)
    resvg
    ripgrep
    _7zz # 7-Zip CLI (binary is `7zz`; replaces brew sevenzip)
    socat
    zellij

    # ── AI coding agents (numtide/llm-agents.nix) ──────────────────────
    # Pulled from llm-agents' own pinned nixpkgs-unstable (not our stable
    # 26.05). claude-code is meta.license.unfree, but cross-flake package
    # refs are pre-evaluated by llm-agents' nixpkgs so our (absent)
    # allowUnfree does not gate them -- verified via
    #   nix build --dry-run github:numtide/llm-agents.nix#claude-code
    # Browse the full list: nix run github:numtide/llm-agents.nix
  ] ++ (with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    gemini-cli
    # qwen-code 的 npmDeps FOD (prefetch-npm-deps, isahc) 直连 registry.npmjs.org
    # 拉 ~2400 个 tarball, 但该 fetcher 的一次性 isahc send() **不读任何代理环境变量**
    # (已三重验证: 源码无 proxy 调用 / 进程环境里有 https_proxy 但仍直连 / netstat 不见 7890 连接),
    # 而 registry.npmjs.org 在国内被 GFW 干扰, 直连丢包率约 40%。
    #
    # 解法: 用 NIX_NPM_REGISTRY_OVERRIDES 把 registry.npmjs.org 重写到一个**本地 HTTPS
    # 反向代理** (127.0.0.1:443, 自签证书; FOD 里 SSL_CERT_FILE=/no-cert-file.crt ->
    # isahc 走 DANGER_ACCEPT_INVALID_CERTS, 直接接受自签证书)。本地代理再走 clash
    # (127.0.0.1:7890) 拉 npmjs 全量 (含 npmmirror CDN 未同步的 mobilecli 等 gap 包)。
    #
    # override 值用**非特殊 scheme** "myproto://127.0.0.1": url crate 对非特殊 scheme 的
    # mirror_url.path() 返回空串 "", 拼接 "" + "/pkg/-.tgz" = 单斜杠; set_host("127.0.0.1")
    # 设 host, scheme/端口保留原值 (https/443)。故 fetcher 实际请求 https://127.0.0.1/...
    # (实测: Replaced URL ... with https://127.0.0.1/@adobe/...)
    #
    # **hash 稳定**: cache.put 存的 url/key 用的是 lockfile 原 package.url
    # (registry.npmjs.org, 见 prefetch-npm-deps main.rs L458), override 只改 fetch 用的临时
    # url, 不改缓存内容 -> 输出 nar hash == 声明的 npmDepsHash, 无需重算。
    #
    # 注入方式: fetchNpmDeps 把 npmRegistryOverridesString 已 eager 进 env.NIX_NPM_REGISTRY_OVERRIDES
    # (prefetch-npm-deps/default.nix), 设函数参数不生效, 必须用 overrideAttrs 改 env attr。
    # 构建期间需先启动本地代理: 见 scripts/npm-proxy-build.sh
    (qwen-code.overrideAttrs (old: {
      npmDeps = old.npmDeps.overrideAttrs (final: {
        env = (final.env or {}) // {
          NIX_NPM_REGISTRY_OVERRIDES = builtins.toJSON {
            "registry.npmjs.org" = "myproto://127.0.0.1";
          };
        };
      });
    }))
  ]);

  # ── LANG (2026-08-14) ────────────────────────────────────────────────
  # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
  # 从系统读 locale → 启动警告 "LANG=en_CN.UTF-8 cannot be used"。
  # environment.variables 写入 launchd 环境, GUI 应用 (Dock 启动的 Emacs)
  # 都需要这里显式设置; 终端 shell 的 LANG 在 shell/env.nix 里。
  environment.variables.LANG = "en_US.UTF-8";
}
