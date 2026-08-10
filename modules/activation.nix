{ config, pkgs, ... }:

{
  # Add route to FreeBSD VM (UTM bridged mode)
  system.activationScripts.postActivation.text = ''
    /sbin/route add -host 192.168.1.31 192.168.64.1 2>/dev/null || true
  '';
}
