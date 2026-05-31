{
  description = "Standalone build of procps-ng";

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
      # Windows/cosmo ships only watch/uptime/tload (portable.nix). Without
      # an explicit winManRoot, mkStandaloneFlake's Windows man graft falls
      # back to nixpkgs procps' FULL man set (ps/top/free/vmstat/…) and
      # over-embeds pages for applets the .exe doesn't have. Pin it to the
      # same 3 pages portable.nix installs, rendered from the SAME 4.0.6
      # tarball portable.nix fetches (nixpkgs procps is 4.0.4 — a version
      # skew that would make the bytes diverge), on x86_64-linux (the
      # Windows runner). Result: cosmo .exe man == darwin man, byte-identical.
      pkgsX = unpins-lib.inputs.nixpkgs.legacyPackages.x86_64-linux;
      procpsWinMan = pkgsX.runCommand "procps-win-man" { } ''
        src=${pkgsX.fetchurl {
          url = "mirror://sourceforge/procps-ng/procps-ng-4.0.6.tar.xz";
          sha256 = "sha256-Z76m+8OkKlNaAjDJ6JHl3ftNnTlCLUZWWimQ0azhUhY=";
        }}
        tar xf "$src"
        cd procps-ng-*/
        for app in watch uptime tload; do
          install -Dm644 "man/$app.1" "$out/share/man/man1/$app.1"
        done
      '';
    in
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "procps-ng";
      pkgsAttr = "procps";
      winManRoot = procpsWinMan;
      # `watch --version` exits 0 + prints "watch from procps-ng 4.0.6"
      # on every target. Linux dispatcher accepts `procps-ng watch …`
      # → watch_main; darwin/cosmo dispatchers fall through to watch
      # when the binary is renamed by CI smoke. smokePattern is the
      # PACKAGE_STRING from c.h's PROCPS_NG_VERSION macro.
      smoke = [ "watch" "--version" ];
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
