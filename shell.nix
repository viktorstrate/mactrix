{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
  lib ? pkgs.lib,
}:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    # nix
    nixfmt-tree
    nixd
    npins

    # matrix test server + python sdk
    matrix-continuwuity
    (python314.withPackages (ps: [
      ps.matrix-nio
      ps.aiohttp
    ]))

    # python tooling
    basedpyright
    mypy

    (pkgs.writeShellScriptBin "element-web-client" ''
      ${lib.getExe pkgs.python3} -m http.server --directory ${pkgs.element-web}
    '')
  ];
}
