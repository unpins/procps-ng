{
  description = "Standalone build of procps-ng";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Linux-only multicall (ps, top, free, kill, pgrep/pkill/pidwait,
  # pidof, pmap, pwdx, slabtop, hugetop, sysctl, tload, uptime, vmstat,
  # watch) built from `pkgsStatic.procps` via the post-link recipe in
  # ./multicall.nix — same ld -r + objcopy --redefine-sym pattern as
  # e2fsprogs / util-linux / findutils. `linuxOnly = true` suppresses
  # the darwin row of the matrix (procps reads /proc).
  outputs = { self, unpins-lib }:
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "procps-ng";
      pkgsAttr = "procps";
      linuxOnly = true;
      # procps-ng is a pure multicall holder — there's no
      # "procps-ng --version" upstream tool. Smoke routes through the
      # `procps-ng <applet>` dispatch form (the dispatcher accepts
      # `<applet>` as argv[1] when the primary is invoked by its real
      # name), so this runs `procps-ng ps --version` → ps's natural
      # --version handler.
      smoke = [ "ps" "--version" ];
      smokePattern = "procps-ng";
      build = pkgs:
        import ./multicall.nix {
          lib = pkgs.lib // unpins-lib.lib;
        } pkgs;
    };
}
