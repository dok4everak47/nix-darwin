{ config, lib, pkgs, ... }:

{
  # nix-darwin 26.05 (rev c3e90c8) bug: environment.etc."ssh/ssh_config.d/
  # 100-nix-darwin.conf".source 默认被错放成 PAM sudo_local 内容
  # (auth sufficient pam_tid.so) -> 命令行 ssh 报
  # "Bad configuration option: auth"。该文件本应是 ssh 客户端配置片段；
  # mkForce 覆盖为空占位（无副作用）。
  # 实测 2026-08-20：覆盖前 source 指向 /nix/store/...-etc-100-nix-darwin.conf
  # (内容为 PAM)；/etc/pam.d/sudo_local 本身正确，Touch ID sudo 不受影响。
  environment.etc."ssh/ssh_config.d/100-nix-darwin.conf".source = lib.mkForce
    (pkgs.writeText "100-nix-darwin-ssh-config.conf"
      "# nix-darwin ssh_config.d placeholder (PAM-misplace fix, 2026-08-20)\n");
}
