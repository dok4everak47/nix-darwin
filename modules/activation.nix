{ config, pkgs, ... }:

{
  # Add route to FreeBSD VM (UTM bridged mode).
  # Idempotent: only add if the route isn't already present.
  system.activationScripts.postActivation.text = ''
    /sbin/route get 192.168.1.31 2>/dev/null | grep -q 'gateway: 192.168.64.1' \
      || /sbin/route add -host 192.168.1.31 192.168.64.1 2>/dev/null || true
  '';
}