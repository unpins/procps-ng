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

      # Build via the unpin-llvm engine + emit a bitcode multicall module. On
      # Linux the engine compiles plain pkgsStatic.procps (every tool is its
      # own upstream binary) to bitcode and the standalone self-folds them into
      # one `procps-ng` binary; darwin keeps the 3-applet portable.nix subset,
      # windows via cosmo. pgrep/pkill/pidwait are byte-identical binaries that
      # self-dispatch by argv[0], so pkill/pidwait are aliases of pgrep, not
      # separate programs. The X+Z fold in ./multicall.nix can't run on the
      # engine's -flto bitcode objects, so it's dropped here. The personality
      # rename (musl/LTO `personality` global vs musl syscall) is still needed
      # under the engine's chain-LTO, so the override carries it. Pure C.
      engine = "unpin-llvm";
      multicall = {
        # darwin ships a genuine SUBSET: no /proc means ps/top/free/… have no
        # analogue, so ./portable.nix builds only watch/uptime/tload. Those three
        # go through the SAME engine self-fold as Linux (portable.nix links them
        # as separate engine-compiled binaries; the module hook + selfFold merge
        # them with the `--unpin-program=`-aware dispatcher) — `darwinPrograms`
        # tells nix-lib to fold exactly this subset on a darwin host instead of
        # the full `programs` list below. windows/cosmo bypasses the engine and
        # keeps portable.nix's own dispatcher fold.
        darwinPrograms = [
          { name = "watch"; }
          { name = "uptime"; }
          { name = "tload"; }
        ];
        programs = [
          # `ps` links as `src/ps/pscommand` (automake renames it to `ps` only
          # at install via `transform`), so the capture sidecar is named after
          # the LINKED name. List the linked name as the program and `ps` as its
          # alias (the final user-facing applet); defaultProgram routes bare
          # `procps-ng` → ps.
          { name = "pscommand"; aliases = [ "ps" ]; }
          { name = "top"; }
          { name = "free"; }
          { name = "kill"; }
          { name = "pgrep"; aliases = [ "pkill" "pidwait" ]; }
          { name = "pidof"; }
          { name = "pmap"; }
          { name = "pwdx"; }
          { name = "slabtop"; }
          { name = "hugetop"; }
          { name = "sysctl"; }
          { name = "tload"; }
          { name = "uptime"; }
          { name = "vmstat"; }
          { name = "watch"; }
        ];
        defaultProgram = "ps";
      };
      # `ps` is reached via the alias of the `pscommand` program above.

      build = pkgs:
        if pkgs.stdenv.hostPlatform.isLinux then
          # Engine path: plain pkgsStatic.procps + the personality-rename fix
          # (the only source change ./multicall.nix made that the chain-LTO
          # link still requires; everything else there was the manual fold).
          pkgs.pkgsStatic.procps.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./personality-rename.patch ];
            # procps' `make check` is a dejagnu suite that spawns processes and
            # reads /proc for exact output matches — too environment-sensitive
            # to gate a static-musl sandbox build (nixpkgs keeps it off too).
            doCheck = false;
          })
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
