# procps-ng for Windows-x86_64 via cosmocc: the same watch/uptime/tload subset
# portable.nix builds for darwin.
{ unpins-lib, winTable }:
pkgs:
let
  lib = pkgs.lib // unpins-lib.lib;
  cosmoPkgs = lib.cosmoStaticCross pkgs;
in
import ./portable.nix { inherit lib winTable; } cosmoPkgs
