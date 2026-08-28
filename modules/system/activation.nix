{
  config,
  pkgs,
  ...
}: {
  # Add route to FreeBSD VM (UTM bridged mode).
  # Idempotent: only add if the route isn't already present.
  system.activationScripts.postActivation.text = ''
    /sbin/route get 192.168.1.31 2>/dev/null | grep -q 'gateway: 192.168.64.1' \
      || /sbin/route add -host 192.168.1.31 192.168.64.1 2>/dev/null || true

    # Ghostty Studio (io.github.steinshead.ghostty-studio) resolves the
    # Ghostty binary ONLY at the hardcoded path
    #   /Applications/Ghostty.app/Contents/MacOS/ghostty
    # (no PATH / Spotlight / Nix-Apps fallback). nix-darwin installs the
    # bundle under /Applications/Nix Apps/, so Studio reports Ghostty
    # unavailable. Bridge with a stable symlink at /Applications/Ghostty.app.
    # Only manage a symlink (or absent path); never clobber a real .app the
    # user may have placed there.
    if [ -e "/Applications/Nix Apps/Ghostty.app" ]; then
      if [ -L /Applications/Ghostty.app ] || [ ! -e /Applications/Ghostty.app ]; then
        /bin/ln -sfn "/Applications/Nix Apps/Ghostty.app" /Applications/Ghostty.app
      fi
    fi
  '';
}
