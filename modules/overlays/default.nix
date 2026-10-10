# nixpkgs overlays. Each overlay is a separate concern; grouping them here
# keeps system/packages.nix as a pure package list.
#
# NOTE: atuin comes from `unstable` because stable 26.05 (18.15.2) predates
# the 2026-07-09 "shell" migration in the existing history.db. It is patched
# for the search flag-swallowing bug (#3908). Once stable catches up (or a
# fixed release lands), drop the atuin overlay and just use pkgs.atuin.
{
  config,
  pkgs,
  unstable,
  nixos-unstable,
  zed-nixpkgs,
  ...
}: {
  nixpkgs.overlays = [
    # ── openmp: strip empty run-lit-directly.patch ─────────────────────
    # 2026-08-24: upstream 26.05's llvm openmp patch run-lit-directly.patch
    # is an empty file (blob e69de29), patch(1) errors with "Only garbage
    # was found", taking out openmp -> fftw -> vid.stab -> ffmpeg ->
    # imagemagick. An empty patch is a no-op anyway, so filter it out.
    (final: prev: {
      openmp = prev.openmp.overrideAttrs (old: {
        patches = builtins.filter (p: builtins.match ".*run-lit-directly.patch" (toString p) == null) (
          old.patches or []
        );
      });
    })

    # ── opencode: skip broken runtime checks + adhoc re-sign ───────────
    # opencode (bun build artifact) fails signature verification on
    # macOS 27 — adhoc signature produced by bun 1.3.13 is invalid
    # (codesign --verify: "code or signature have been modified"), the
    # binary is SIGKILL'd at launch ("Killed: 9").
    # Fix: skip all build-time steps that execute the binary (smoke test /
    # version check / completion), then adhoc re-sign in fixup.
    # Verified output:
    # /nix/store/g5rkdxik56x2p8fg3g5flw31dmi72z0k-opencode-1.15.10
    (final: prev: {
      opencode = prev.opencode.overrideAttrs (old: {
        dontStrip = true;
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace packages/opencode/script/build.ts \
              --replace-fail "if (item.os === process.platform" \
                            "if (false && item.os === process.platform"
          '';
        doInstallCheck = false;
        postInstall = "";
        postFixup =
          (old.postFixup or "")
          + ''
            /usr/bin/codesign --force --sign - "$out/bin/.opencode-wrapped"
          '';
      });
    })

    # ── atuin: unstable 18.17.1 + search-hyphen patch ──────────────────
    # atuin 18.17+ search bug (#3908): `allow_hyphen_values` on the
    # variadic query swallows flags written AFTER the query (e.g.
    # `atuin search git --cmd-only` treats `--cmd-only` as a search term).
    # The patch removes it; hyphen-prefixed queries now need an explicit
    # `--` separator.
    (final: prev: {
      atuin = (unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.atuin).overrideAttrs (old: {
        patches = (old.patches or []) ++ [../../atuin-fix-search-hyphen.patch];
      });
    })

    # ── pi-coding-agent: prebuilt 1.1.0 release binary (2026-10-08) ──────
    # 26.05 stable, the atuin-pinned `unstable` input (rev 6f6fca05, 2026-08)
    # and even nixos-unstable's branch still ship pi 0.82.1 / 0.87.1, so the
    # old `unstable.legacyPackages...pi-coding-agent` override is gone. Fetch
    # the official standalone release tarball (aarch64-darwin) instead. Hash =
    # sha256 of pi-darwin-arm64.tar.gz, re-verified 2026-10-08 against the
    # downloaded tarball
    # (3455b13de35c15a5893cdebc922678199e90a7ce99b06cbc23f37860e90d63c7).
    #
    # 升级 0.99.2 → 1.1.0 (2026-10-08, 历史: 2026-10-04 曾因 1.0 起「TUI 默认
    # 全屏」回退到 0.99.2): 打包布局与 0.99.2 完全一致 → installPhase/postFixup
    # 不动: 仍是 `pi/` 根, 兄弟文件 (package.json / photon_rs_bg.wasm /
    # native/darwin/prebuilds/darwin-arm64/darwin-platform.node) 齐在,
    # PI_SKIP_VERSION_CHECK / PI_TELEMETRY 也仍被二进制读取。
    # 本次配套: ~/.pi/agent/settings.json 已设 tuiMode: "regular" 保住终端滚动
    # 历史 (否则 1.0+ 默认全屏)。另 1.0.3 把 azure provider 由
    # azure-openai-responses 更名 azure (本机未用, 无需改)。
    #
    # 布局: tarball 根是 `pi/`, 里面不只是 `pi` 二进制, 还有 package.json、
    # photon_rs_bg.wasm 和 native/darwin/prebuilds/.../darwin-platform.node,
    # 二进制运行时会按自身路径找这些兄弟文件 → 整棵树原样留在 libexec/pi/,
    # 只在 bin/ 暴露一个 wrapper(路径不变, execPath 仍在 libexec/pi/)。
    # wrapper 与 nixpkgs 那版对齐: PATH 补 ripgrep/fd, 关掉自更新检查与遥测。
    (final: prev: {
      pi-coding-agent = prev.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "pi-coding-agent";
        version = "1.1.0";

        src = prev.fetchurl {
          url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-darwin-arm64.tar.gz";
          hash = "sha256-NFWxPeNcFaWJPN68kiZ4GZ6Qp86ZsGy8I/N4YOkNY8c=";
        };

        dontUnpack = true;
        nativeBuildInputs = [prev.makeWrapper];

        installPhase = ''
          runHook preInstall
          mkdir -p $out/libexec $out/bin
          tar -xzf $src -C $out/libexec
          chmod 0755 $out/libexec/pi/pi
          runHook postInstall
        '';

        # macOS 27: adhoc re-sign after nix fixup (same pattern as the herdr
        # and opencode overlays — a broken/absent signature is SIGKILL'd).
        # The native prebuild (.node) is dlopen'd at runtime and needs its own
        # signature; makeWrapper last so the wrapper stays a plain script.
        postFixup = ''
          /usr/bin/codesign --force --sign - $out/libexec/pi/pi
          find $out/libexec/pi -name '*.node' -type f \
            -exec /usr/bin/codesign --force --sign - {} \;
          makeWrapper $out/libexec/pi/pi $out/bin/pi \
            --prefix PATH : ${prev.lib.makeBinPath [prev.ripgrep prev.fd]} \
            --set-default PI_SKIP_VERSION_CHECK 1 \
            --set-default PI_TELEMETRY 0
        '';

        meta = {
          description = "Coding agent CLI with read, bash, edit, write tools and session management";
          homepage = "https://pi.dev/";
          changelog = "https://github.com/earendil-works/pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
          license = prev.lib.licenses.mit;
          mainProgram = "pi";
        };
      });
    })

    # ── herdr: prebuilt 0.9.3 release binary (2026-10-01) ──────────────
    # nixpkgs (26.05 stable, atuin-pinned `unstable`, and rolling
    # nixos-unstable) all still ship herdr 0.8.2; upstream is now 0.9.3.
    # 0.9.2 adds multiple prefix keys, `herdr machine status`/`reconnect` and
    # an interactive `machine add`, faster image rendering (the Herdr-specific
    # pane graphics API is gone — apps write standard Kitty graphics now), a
    # resumed-agent startup delay, and agent self-reported resume commands;
    # 0.9.3 is a hotfix restoring Escape-prefixed terminal shortcuts
    # (Option+Left/Right, Option+Backspace in Ghostty/iTerm2, Shift+Enter).
    # Fetch the official prebuilt release binary (aarch64-darwin only) instead
    # of the nixpkgs source build. Hash = sha256 of the v0.9.3 release asset,
    # verified 2026-10-01. Once nixpkgs catches up, drop this override and
    # restore `nixos-unstable.legacyPackages...herdr`.
    #
    # ── 为什么包成隐藏的 .app (LSUIElement): 防"幽灵" Dock 图标 ──────────
    # herdr 内嵌 libghostty 且会注册 NSApplication, 于是它会被 LaunchServices
    # 登记成一个 app。它从终端 pane 里启动时, macOS 把该进程归属到"责任进程"
    # (= 宿主终端本体 Ghostty/Kaku), 登记出来就是终端本体的 bundle 身份 →
    # Dock 多画一个 Ghostty/Kaku 的"幽灵"图标 (2026-09-29 实测: lsappinfo 里
    # 名为 Ghostty、executable path 却是 .../sw/bin/herdr 的条目); 客户端退出
    # 后该登记不回收, 图标于是累积 (2026-10-01: Dock 里曾同时 3 个 Ghostty)。
    # 注意: 身份来自父进程归属, **不是**继承的 __CFBundleIdentifier —— 实测把
    # 该变量删掉后再从 Kaku pane 启动裸二进制, 依然被登记成 Kaku, 所以单靠
    # --unset 拦不住(旧注释的假设是错的)。
    # 对策: 真二进制放进一个最小 .app 并标 LSUIElement=true。实测同样从 Kaku
    # pane 启动, LS 会按这个 bundle 登记 (type=UIElement) → Dock 不加图标, 不再
    # 冒充终端。副作用: store 路径只读, `herdr update` 无法自更新, 版本一律走
    # nix —— 不要跑 herdr update。.app 放 libexec 而非 $out/Applications, 免得
    # nix-darwin 把它当 GUI app 链进 /Applications/Nix Apps。
    (final: prev: {
      herdr = let
        unwrapped = prev.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "herdr";
          version = "0.9.3";

          src = prev.fetchurl {
            url = "https://github.com/herdrdev/herdr/releases/download/v${finalAttrs.version}/herdr-macos-aarch64";
            hash = "sha256-UXOj4K5C1dGrfr+l1eYyn3w9I/jho2d8fOMjHaKIQVc=";
          };

          dontUnpack = true;
          strictDeps = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/herdr
            runHook postInstall
          '';

          # macOS 27: adhoc re-sign after nix fixup (same pattern as opencode
          # overlay — a broken/absent signature gets the binary SIGKILL'd).
          postFixup = ''
            /usr/bin/codesign --force --sign - $out/bin/herdr
          '';

          meta = {
            description = "Agent-aware terminal workspace manager for AI coding agents";
            homepage = "https://herdr.dev";
            license = prev.lib.licenses.mit;
            mainProgram = "herdr";
          };
        });
      in
        prev.stdenvNoCC.mkDerivation {
          pname = "herdr";
          version = unwrapped.version;

          dontUnpack = true;
          strictDeps = true;

          installPhase = ''
            runHook preInstall
            appdir=$out/libexec/Herdr.app
            mkdir -p $appdir/Contents/MacOS $out/bin
            install -m755 ${unwrapped}/bin/herdr $appdir/Contents/MacOS/herdr

            # 最小 Info.plist: 自己的 bundle id + LSUIElement(不进 Dock/Launchpad)
            cat > $appdir/Contents/Info.plist <<'PLIST'
            <plist version="1.0">
            <dict>
              <key>CFBundleExecutable</key><string>herdr</string>
              <key>CFBundleIdentifier</key><string>dev.herdr.cli</string>
              <key>CFBundleName</key><string>herdr</string>
              <key>CFBundleDisplayName</key><string>herdr</string>
              <key>CFBundlePackageType</key><string>APPL</string>
              <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
              <key>CFBundleShortVersionString</key><string>${unwrapped.version}</string>
              <key>CFBundleVersion</key><string>${unwrapped.version}</string>
              <key>LSMinimumSystemVersion</key><string>11.0</string>
              <key>NSHighResolutionCapable</key><true/>
              <key>LSUIElement</key><true/>
            </dict>
            </plist>
            PLIST

            # PATH 上的 herdr 只是入口(其余环境变量 TERM/PATH… 原样透传); 真二进制
            # 在 .app 里, 于是 LaunchServices 按这个 bundle 登记, 而不是按宿主终端。
            cat > $out/bin/herdr <<SH
            #!/bin/sh
            unset __CFBundleIdentifier
            exec "$out/libexec/Herdr.app/Contents/MacOS/herdr" "\$@"
            SH
            chmod +x $out/bin/herdr
            runHook postInstall
          '';

          # macOS 27: adhoc re-sign after nix fixup (same pattern as opencode
          # overlay — a broken/absent signature gets the binary SIGKILL'd).
          postFixup = ''
            /usr/bin/codesign --force --sign - $out/libexec/Herdr.app/Contents/MacOS/herdr
            /usr/bin/codesign --force --sign - $out/libexec/Herdr.app
          '';

          meta = unwrapped.meta;
        };
    })

    # codex : use unstable version
    (final: prev: {
      codex = nixos-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.codex;
    })

    # ── nitter: use nixos-unstable version (2026-07-11) ───────────────
    # Stable 26.05 only ships nitter 0-unstable-2026-01-29. Both crash with
    # SIGSEGV in Nim's async SSL (SSL_CTX_new) on macOS 27, but the newer
    # build + DYLD_LIBRARY_PATH pin to the 26.05 openssl (see
    # modules/system/nitter.nix) makes it stable. Track the rolling
    # nixos-unstable channel for the newest build.
    (final: prev: {
      nitter = nixos-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.nitter;
    })

    # Opencode: Unstable version
    (final: prev: {
      opencode = nixos-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.opencode;
    })

    # ── zed-editor: nixpkgs-unstable 1.22.0 (2026-10-06) ───────────────
    # 26.05 stable 的 zed-editor 是 1.3.6, nixos-unstable 也只到 1.21.0,
    # 上游当前 stable 是 1.22.0 → 用专用的 zed-nixpkgs input 覆盖。
    # 该 input 的 zed-editor 1.22.0 在 cache.nixos.org 有预编译包, rebuild
    # 只下载不编译。nixpkgs(26.05 或 nixos-unstable) 追上来后连同 flake.nix
    # 里的 zed-nixpkgs input 一起删掉。
    (final: prev: {
      zed-editor = zed-nixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system}.zed-editor;
    })

    # ── ccs (ccfullsearch): prebuilt 0.16.0 release binary (2026-10-11) ──
    # `ccs` 是 Claude Code 插件 ccs@ccfullsearch (github:materkey/ccfullsearch)
    # 的 CLI: 全文检索本机 Claude Code / Codex / Opencode 的历史会话。
    # 插件的 skill 要求 `ccs` 在 PATH 上 ("Binary ccs must be in PATH"),
    # 而插件本体不带二进制 —— 故这里把它装进系统 profile。
    #
    # 不在 nixpkgs: 已实测 `nix eval nixpkgs#ccfullsearch.version` → does not
    # provide attribute。走 pi-coding-agent / herdr 同款做法: pin 上游
    # aarch64-darwin release 资产, 不从源码编 Rust TUI (省 cargoHash、数分钟
    # 编译和数百 MB store; 且沙箱里拉 crates.io 更易受代理抖动影响)。
    # 升级: 改 version 后重算 hash —— `nix store prefetch-file --json <url>`。
    # Hash = sha256 of ccfullsearch-aarch64-apple-darwin.tar.gz
    # (release v0.16.0, 2026-06-12), 2026-10-11 双向核对:
    #   nix store prefetch-file → sha256-UGn2uLqBbenaaoBQpoCtOtAAekGb5uhaMj/6kk490jM=
    #   nix32                    → 0cyj7m795yiz69dfirlv85x01l1smn0acl40dbdfjvc1pawgcsah
    #   shasum -a 256            → 5069f6b8ba816de9da6a8050a680ad3ad0007a419be6e85a323ffa924e3dd233
    (final: prev: {
      ccfullsearch = prev.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "ccs";
        version = "0.16.0";

        src = prev.fetchurl {
          url = "https://github.com/materkey/ccfullsearch/releases/download/v${finalAttrs.version}/ccfullsearch-aarch64-apple-darwin.tar.gz";
          hash = "sha256-UGn2uLqBbenaaoBQpoCtOtAAekGb5uhaMj/6kk490jM=";
        };

        # tarball 里只有 ccs 二进制 + README/CHANGELOG/LICENSE, 没有构建脚本。
        dontBuild = true;
        strictDeps = true;

        installPhase = ''
          runHook preInstall
          install -Dm755 ccs $out/bin/ccs
          runHook postInstall
        '';

        # macOS 27: nix fixup 改写过的 Mach-O 签名失效会被 SIGKILL (Killed: 9),
        # 故 fixup 后重新 adhoc 签名 —— 与 opencode / herdr / pi-coding-agent
        # 的 postFixup 同款。(实测: 未签的 release 二进制直跑正常, 签名是给
        # nix store 里的改写副本补的。)
        postFixup = ''
          /usr/bin/codesign --force --sign - $out/bin/ccs
        '';

        meta = {
          description = "Search and browse Claude Code, Codex and Opencode session history (CLI/TUI)";
          homepage = "https://github.com/materkey/ccfullsearch";
          changelog = "https://github.com/materkey/ccfullsearch/blob/v${finalAttrs.version}/CHANGELOG.md";
          license = prev.lib.licenses.mit;
          mainProgram = "ccs";
          platforms = ["aarch64-darwin"];
        };
      });
    })
  ];
}
