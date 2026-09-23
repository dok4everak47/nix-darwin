{
  description = "Rust project";

  # For a per-project toolchain (nightly / pinned version), swap to rust-overlay:
  # https://github.com/oxalica/rust-overlay
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {self, nixpkgs}: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forEach = nixpkgs.lib.genAttrs systems;

    # 代理单一来源 (本模板是独立 flake, 被 `nix flake init` 原样复制, 无法 import
    # /etc/nix-darwin/modules/lib.nix → 每个模板各留一份; 改端口时两处一起改)。
    proxyHost = "127.0.0.1";
    proxyPort = 7890;
    proxyUrl = "http://${proxyHost}:${toString proxyPort}";
    proxyNoProxy = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com,ark.cn-beijing.volces.com,.volces.com,.moonshot.cn";
  in {
    devShells = forEach (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [rustc cargo rustfmt clippy rust-analyzer];
        shellHook = ''
          # 代理 = NinjaDesktop (mihomo 内核) 的 mixed-port, 地址/端口见本文件
          # 上面的 proxyUrl/proxyNoProxy。只在端口活着时才导出, 所以代理挂了
          # 也不会把 shell 的网络弄断; 刻意不导出 socks5 (git 会优先用它 →
          # github 443 SSL_ERROR_SYSCALL, 见 /etc/nix-darwin/modules/lib.nix)。
          # 注意 /dev/tcp 是 bash 特性(纯 zsh 没有), 这里能跑是因为 direnv 与
          # `nix develop` 都用 bash 执行 shellHook; 别把这段挪进 .zshrc。
          if (echo > /dev/tcp/${proxyHost}/${toString proxyPort}) 2>/dev/null; then
            export http_proxy=${proxyUrl} https_proxy=${proxyUrl}
            export HTTP_PROXY=${proxyUrl} HTTPS_PROXY=${proxyUrl}
            export no_proxy=${proxyNoProxy} NO_PROXY=${proxyNoProxy}
          fi
          # NOTE: shellHook 的输出会在**每次** direnv 加载时打印到终端,
          # 不要在这里 echo 版本号之类的提示 (2026-09-17 已清除).
        '';
      };
    });
  };
}
