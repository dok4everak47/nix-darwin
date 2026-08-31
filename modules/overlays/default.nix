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

    # ── omniwm: 0.6.4 from official release zip (bsdtar keeps signature) ─
    # DoomHammer NUR package is BROKEN (cp -r . nests OmniWM.app inside
    # itself → empty $out/Applications; spctl: "invalid API object
    # reference"). DavSanchez's package builds cleanly (bsdtar -xf preserves
    # the notarized Developer ID signature + links omniwmctl) but pins 0.6.4.
    # This overlay = DavSanchez build logic + 0.6.4 release.
    # src hash verified 2026-08-31: sha256-myv1TSDWf1NicAMuBiUXbAbG4DuIl93wJVWNlIM55ec=
    (final: prev: {
      omniwm = prev.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "omniwm";
        version = "0.6.4";

        src = prev.fetchurl {
          url = "https://github.com/BarutSRB/OmniWM/releases/download/v${finalAttrs.version}/OmniWM-v${finalAttrs.version}.zip";
          hash = "sha256-myv1TSDWf1NicAMuBiUXbAbG4DuIl93wJVWNlIM55ec=";
        };

        dontUnpack = true;
        strictDeps = true;
        nativeBuildInputs = [ prev.libarchive ];

        installPhase = ''
          runHook preInstall

          mkdir -p $out/Applications/
          bsdtar -xf $src -C $out/Applications/

          mkdir -p $out/bin
          ln -s $out/Applications/OmniWM.app/Contents/MacOS/OmniWM $out/bin/OmniWM
          ln -s $out/Applications/OmniWM.app/Contents/MacOS/omniwmctl $out/bin/omniwmctl

          runHook postInstall
        '';

        meta = {
          description = "macOS tiling window manager inspired by Niri and Hyprland";
          homepage = "https://github.com/BarutSRB/OmniWM";
          license = prev.lib.licenses.gpl2Only;
          mainProgram = "OmniWM";
          platforms = prev.lib.platforms.darwin;
          sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
        };
      });
    })
  ];
}
