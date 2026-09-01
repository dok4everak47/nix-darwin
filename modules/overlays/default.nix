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
  mcseekeri-nur,
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
        patches =
          builtins.filter
          (p: builtins.match ".*run-lit-directly.patch" (toString p) == null)
          (old.patches or []);
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
      atuin = (unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.atuin)
        .overrideAttrs (old: {
        patches = (old.patches or []) ++ [../../atuin-fix-search-hyphen.patch];
      });
    })

    # ── pi-coding-agent: use unstable version instead of 26.05 stable ───
    (final: prev: {
      pi-coding-agent = unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.pi-coding-agent;
    })

    # ── herdr: use nixos-unstable version instead of 26.05 stable ─────
    # 0.8.2 ("Agent multiplexer that lives in your terminal"); not in 26.05
    # stable. The atuin-pinned `unstable` input only has 0.7.5, so track the
    # rolling nixos-unstable channel (locked in flake.lock) for 0.8.2.
    (final: prev: {
      herdr = nixos-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.herdr;
    })

    # codex : use unstable version
    (final: prev: {
      codex = nixos-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.codex;
    })

    # ── cc-switch: MCSeekeri NUR (3.20.0, Tauri desktop app) ──────────
    # AI coding assistant config switcher (Claude Code, Codex, OpenCode...).
    # From MCSeekeri/NUR flake (own nixpkgs-unstable; binary cache
    # nix.mcseekeri.com). Exposed as packages.<system>.cc-switch.
    (final: prev: {
      cc-switch = mcseekeri-nur.packages.${prev.stdenv.hostPlatform.system}.cc-switch;
    })
  ];}
