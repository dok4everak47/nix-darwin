# 字体: nix 管理的字体包 (fonts.packages 会装进 /Library/Fonts)
# DotGothic16: Google Fonts 点阵日文字体 (16px dot) — dashboard Lain CRT 风专用
# nixpkgs 无此包, fetchurl 直取 google/fonts 仓库 (pin commit 防上游漂移:
# 上游 .ttf 变更会 hash 校验失败而 build 报错, 属预期保护, 到时更新 hash 即可)
{ pkgs, ... }:

let
  googleFontsRev = "f2bd09badbc763d8757951d52deec29da27e85fb";
  dotgothic16 = pkgs.stdenvNoCC.mkDerivation {
    pname = "dotgothic16";
    version = "1.002";
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/google/fonts/${googleFontsRev}/ofl/dotgothic16/DotGothic16-Regular.ttf";
      hash = "sha256-OtmviHJtQrQPfzZfDcrHha9zzyDqbx1bROV8whFQuPE=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/truetype
      cp $src $out/share/fonts/truetype/DotGothic16-Regular.ttf
    '';
    meta = with pkgs.lib; {
      description = "DotGothic16 - Google Fonts dot-matrix Japanese font (OFL)";
      platforms = platforms.all;
    };
  };
in
{
  fonts.packages = [ dotgothic16 ];
}
