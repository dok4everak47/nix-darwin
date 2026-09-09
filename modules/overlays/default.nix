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

    # ── pi-coding-agent: use unstable version instead of 26.05 stable ───
    (final: prev: {
      pi-coding-agent = unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.pi-coding-agent;
    })

    # ── herdr: prebuilt 0.9.0 release binary (2026-09-09) ──────────────
    # nixpkgs (26.05 stable, atuin-pinned `unstable`, and rolling
    # nixos-unstable as of rev d6524aa/2026-09-08) all still ship herdr 0.8.2;
    # upstream 0.9.0 (2026-09-07) adds multi-machine SSH management
    # (`herdr machine`), independent client views, Muse agent detection.
    # Fetch the official prebuilt release binary (aarch64-darwin only) instead
    # of the nixpkgs source build. Hash = sha256 of the v0.9.0 release asset,
    # verified 2026-09-09. Once nixpkgs catches up, drop this override and
    # restore `nixos-unstable.legacyPackages...herdr`.
    (final: prev: {
      herdr = prev.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "herdr";
        version = "0.9.0";

        src = prev.fetchurl {
          url = "https://github.com/herdrdev/herdr/releases/download/v${finalAttrs.version}/herdr-macos-aarch64";
          hash = "sha256-MrU98JhyYoBZx4mmnwKmuOKeFN3yZxFCHzRj9wwa7xc=";
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
  ];
}
