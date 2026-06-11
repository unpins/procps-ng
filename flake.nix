{
  description = "procps-ng as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Linux: full 16-applet multicall from `pkgsStatic.procps` (post-link
  # rename recipe in ./multicall.nix — same shape as e2fsprogs /
  # util-linux / findutils).
  #
  # darwin + Windows (cosmo): 3-applet subset (watch, uptime, tload)
  # via ./portable.nix. watch is pure POSIX; uptime + tload route
  # through ./portable-libproc.c which provides per-OS shims for
  # procps_uptime / procps_loadavg / procps_users (sysctl + utmpx on
  # darwin; clock_gettime(CLOCK_BOOTTIME) + getloadavg via cosmo on
  # Windows). The rest of the procps tooling reads /proc directly and
  # has no portable analogue.
  outputs = { self, unpins-lib }:
    let
      # Windows/cosmo + darwin ship only watch/uptime/tload (portable.nix),
      # whose installPhase installs exactly those 3 man pages (from its own
      # 4.0.6 tarball) into $out/share/man. The cosmo cross runs that same
      # installPhase, so the .exe harvests its OWN man — the same 3 pages
      # darwin embeds, version-matched, no winManRoot graft (which would have
      # pulled nixpkgs procps' FULL set, or needed a separate 4.0.6 fetch to
      # dodge the 4.0.4 skew).
    in
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "procps-ng";
      pkgsAttr = "procps";
      # `watch --version` exits 0 + prints "watch from procps-ng 4.0.6"
      # on every target. `--unpin-program=watch` selects the applet
      # explicitly through the unified multicall selector, independent of
      # argv[0] — so it works whether the binary is named procps-ng or was
      # renamed by CI smoke. smokePattern is the PACKAGE_STRING from c.h's
      # PROCPS_NG_VERSION macro.
      smoke = [ "--unpin-program=watch" "--version" ];
      smokePattern = "procps-ng";
      build = pkgs:
        if pkgs.stdenv.hostPlatform.isLinux then
          import ./multicall.nix {
            lib = pkgs.lib // unpins-lib.lib;
          } pkgs
        else
          import ./portable.nix {
            lib = pkgs.lib // unpins-lib.lib;
          } pkgs.pkgsStatic;
      windowsBuild = pkgs:
        let
          lib = pkgs.lib // unpins-lib.lib;
          cosmoPkgs = lib.cosmoStaticCross pkgs;
        in
        import ./portable.nix { inherit lib; } cosmoPkgs;
    };
}
