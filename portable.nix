# Portable 3-applet build of procps-ng for targets that aren't Linux:
#   watch  — fork+exec+termios+ncurses, no /proc usage at all
#   uptime — needs procps_uptime/loadavg/users; ./portable-libproc.c
#            provides per-OS shims (sysctl on darwin, clock_gettime on
#            cosmo, getloadavg(3) and utmpx on darwin)
#   tload  — needs procps_loadavg only; same shim
#
# Used by flake.nix's `build` on darwin and by `windowsBuild` on cosmo.
# Linux keeps the 17-applet multicall.nix path; this file is not touched
# on Linux.
#
# TWO FOLD PATHS, one source layer. The portability layer (config.h, the
# <wctype.h>/__fpending fixups, and portable-libproc.c's sysctl/utmpx shims)
# is shared. The FOLD differs by target:
#
#   darwin (engine) — build watch/uptime/tload as three SEPARATE normal
#     executables (each its own `main`). The unpin-llvm engine compiles them
#     to bitcode and the capture shim records each link's inputs; nix-lib's
#     multicallModuleHookLTO + selfFold then merge them into one binary with
#     the SAME dispatcher the Linux/mega path uses (understands
#     `--unpin-program=`). So darwin no longer hand-rolls a dispatcher — it
#     rides the engine self-fold like every other native target. flake.nix
#     sets `multicall.darwinPrograms = [watch uptime tload]` (the darwin
#     subset) so the module folds exactly these three.
#
#   cosmo/windows — the engine doesn't run on cosmocc, so this file keeps its
#     hand-rolled dispatcher.c fold (`-Dmain=<app>_main` + argv[0] dispatch)
#     and ships the single binary directly via withAliases.
#
# We skip upstream's `make all` because it pulls in /proc-only readers
# (library/sysinfo.c, library/uptime.c with their /proc/uptime,
# /proc/loadavg fopen calls) that we'd otherwise have to either build
# and ignore or sed out per applet. Hand-rolling the build keeps the
# compile list minimal and the link line readable.
{ lib }:
pkgs:
let
  version = "4.0.6";

  isCosmo = pkgs.stdenv.hostPlatform.isCosmo or false;

  # Cosmo binary runs anywhere — no host terminfo lookup possible, so
  # the baked fallback array is the only source of truth (`-only`
  # variant drops `--enable-database`). Native darwin still has
  # /usr/share/terminfo on the user's machine; the embedded fallbacks
  # cover scratch containers and other terminfo-less environments.
  ncurses =
    if isCosmo
    then lib.embedFallbackTerminfoOnly pkgs.ncurses
    else lib.embedFallbackTerminfo pkgs.ncurses;

  # cosmo ncurses is built with `unicodeSupport = false` (cosmo libc's
  # wint_t/wcwidth declarations live in non-standard headers — see
  # nix-lib/cosmo/ncurses.nix). Without widec, the cchar_t/wadd_wch/
  # setcchar API watch.c's WITH_WATCH8BIT path needs is absent from
  # `<curses.h>` regardless of any -DNCURSES_WIDECHAR override.
  # Detect at eval time and gate the 8-bit-clean watch feature on it.
  hasWidec = ncurses.unicodeSupport or true;

  # Hand-rolled config.h. autoconf would generate this; we know our
  # narrow source surface (3 src/, 2 local/) and which HAVE_* macros
  # they each consult, so a 20-line file beats running ./configure.
  #
  # WITH_WATCH8BIT + WITH_COLORWATCH — opt-in features that configure
  # would have hidden behind --enable-* flags. Forced on for parity
  # with the Linux multicall (which gets them from upstream defaults).
  #
  # HAVE_PROGRAM_INVOCATION_NAME deliberately left undef — that path
  # is glibc-only. local/c.h's `#ifndef HAVE_PROGRAM_INVOCATION_SHORT_NAME`
  # block picks up argv[0]-derived fallback (HAVE___PROGNAME route on
  # cosmo via BSD-ish libc; the basename-from-__FILE__ route on darwin).
  configH = pkgs.writeText "config.h" ''
    #define PACKAGE "procps-ng"
    #define PACKAGE_NAME "procps-ng"
    #define PACKAGE_STRING "procps-ng ${version}"
    #define PACKAGE_VERSION "${version}"
    #define VERSION "${version}"
    #define HAVE_ERR_H 1
    #define HAVE_LOCALE_H 1
    ${if hasWidec then "#define WITH_WATCH8BIT 1" else "/* WITH_WATCH8BIT off: ncurses built --disable-widec on this target. */"}
    #define WITH_COLORWATCH 1
    /* HAVE_NCURSESW_NCURSES_H undef: nixpkgs cosmo + darwin ncurses
       put `curses.h` directly under `include/`, no `ncursesw/` subdir;
       wide-char functions, if available, live in the same header
       gated by NCURSES_WIDECHAR which we set via -D in the build. */
    /* HAVE_PROGRAM_INVOCATION_NAME undef: glibc-only. */
    /* HAVE_ERROR undef: local/c.h inlines a fallback. */
    /* HAVE_ERROR_H undef: avoids <error.h> include (glibc-only). */
    /* ENABLE_NLS undef: gettext disabled. */
  '';

  applets = [ "watch" "uptime" "tload" ];

  multicall = pkgs.stdenv.mkDerivation {
    pname = "procps-ng";
    inherit version;

    src = pkgs.fetchurl {
      url = "mirror://sourceforge/procps-ng/procps-ng-${version}.tar.xz";
      sha256 = "sha256-Z76m+8OkKlNaAjDJ6JHl3ftNnTlCLUZWWimQ0azhUhY=";
    };

    # No pkg-config: the cosmo cross stdenv has a setup-hook ordering
    # quirk that errors out before buildPhase even starts. cc-wrapper
    # already injects -I${ncurses.dev}/include + -L${ncurses}/lib via
    # NIX_CFLAGS_COMPILE / NIX_LDFLAGS from buildInputs, so we only need
    # to name the libraries on the link line.
    buildInputs = [ ncurses ];

    dontConfigure = true;

    postPatch = ''
      # __fpending: glibc-only; the upstream fallback uses BSD FILE
      # struct internals (_p / _bf._base) that hold on darwin but not on
      # cosmo. Returning 0 forgoes precise pending-data detection in
      # close_stream — acceptable: the only consumer is the atexit
      # close_stdout handler, which sees a clean exit path anyway.
      substituteInPlace local/fileutils.c \
        --replace-fail \
          '# define __fpending(fp) ((fp)->_p - (fp)->_bf._base)' \
          '# define __fpending(fp) 0'

      # watch.c calls iswprint() but never #includes <wctype.h>; glibc
      # leaks it via another transitive include but cosmo and darwin
      # don't. Inject the include right after the #include block.
      substituteInPlace src/watch.c \
        --replace-fail \
          '#include "config.h"' \
          '#include "config.h"
      #include <wctype.h>'

      # Stage our config.h + shim next to the source.
      install -m644 ${configH} config.h
      install -m644 ${./portable-libproc.c} portable-libproc.c
    '';

    buildPhase = ''
      runHook preBuild

      mkdir -p multicall

      # ncurses lib name varies: widec builds expose libncursesw.a +
      # libtinfow.a; --disable-widec builds expose libncurses.a only.
      # Pick by which file actually exists in the lib dir.
      if [ -f "${ncurses}/lib/libncursesw.a" ] || [ -f "${ncurses.out}/lib/libncursesw.a" ]; then
        NCLIBS="-lncursesw"
        if [ -f "${ncurses}/lib/libtinfow.a" ] || [ -f "${ncurses.out}/lib/libtinfow.a" ]; then
          NCLIBS="$NCLIBS -ltinfow"
        fi
      else
        NCLIBS="-lncurses"
        if [ -f "${ncurses}/lib/libtinfo.a" ] || [ -f "${ncurses.out}/lib/libtinfo.a" ]; then
          NCLIBS="$NCLIBS -ltinfo"
        fi
      fi
      NCLIBS="$NCLIBS -lm"

      # NCURSES_WIDECHAR activates cchar_t / wadd_wch / setcchar / etc
      # exposed by ncurses.h. Only useful when the ncurses build did
      # include widec at configure time (cosmo's is `--disable-widec`,
      # see hasWidec gate above).
      # -Ilibrary/include: uptime.c includes <misc.h> which lives there
      # (libproc2's public API). Our shim implements the 5 functions
      # uptime/tload actually call; the rest of the prototypes in misc.h
      # are just unused declarations.
      CFLAGS_BASE="-I. -Ilocal -Ilibrary/include -DHAVE_CONFIG_H ${if hasWidec then "-DNCURSES_WIDECHAR=1" else ""} -O2"

      # Local helpers (shared across applets, no per-applet renaming
      # needed — none of these define a non-static `main`).
      $CC $CFLAGS_BASE -c -o multicall/strutils.o  local/strutils.c
      $CC $CFLAGS_BASE -c -o multicall/fileutils.o local/fileutils.c

      # libproc2 shim providing procps_{uptime,loadavg,users,uptime_snprint,
      # container_uptime}. No config.h dependency.
      $CC -O2 -c -o multicall/portable-libproc.o portable-libproc.c

    '' + (if isCosmo then ''
      # cosmo/windows fold: the engine doesn't run on cosmocc, so hand-roll
      # the dispatcher. Each applet compiled with -Dmain=<applet>_main so the
      # final link gets three distinct entry points (mirrors the Linux
      # multicall recipe's rename-header step, trivially — only 3 sources).
      for app in ${lib.concatStringsSep " " applets}; do
        $CC $NIX_CFLAGS_COMPILE $CFLAGS_BASE -Dmain=''${app}_main \
          -c -o multicall/$app.o src/$app.c
      done

      # Dispatcher: basename(argv[0]) → applet, with `procps-ng <applet>`
      # form for the smoke test. Fallback (e.g. binary renamed by CI smoke)
      # routes to watch — the only applet that exits 0 on --version
      # regardless of the caller's name.
      cat > multicall/dispatcher.c <<'EOF'
      #include <string.h>
      #include <stdio.h>

      int watch_main(int, char **);
      int uptime_main(int, char **);
      int tload_main(int, char **);

      struct applet { const char *name; int (*fn)(int, char **); };
      static const struct applet applets[] = {
          {"watch",  watch_main},
          {"uptime", uptime_main},
          {"tload",  tload_main},
          {NULL, NULL}
      };

      int main(int argc, char *argv[]) {
          static char name_buf[64];
          char *name = argv[0];
          char *slash = strrchr(name, '/');
          if (slash) name = slash + 1;
          char *bs = strrchr(name, '\\');
          if (bs) name = bs + 1;
          if (strncmp(name, "lt-", 3) == 0) name += 3;
          /* Strip the cosmocc-emitted `.exe` so dispatch sees the
             canonical applet name on both ELF and PE32+ targets. */
          {
              size_t l = strlen(name);
              if (l > 4 && strcmp(name + l - 4, ".exe") == 0) {
                  if (l - 4 < sizeof(name_buf)) {
                      memcpy(name_buf, name, l - 4);
                      name_buf[l - 4] = '\0';
                      name = name_buf;
                  }
              }
          }
          if ((strcmp(name, "procps-ng") == 0 || strcmp(name, "procps") == 0)
              && argc >= 2 && argv[1][0] != '-') {
              name = argv[1]; argv++; argc--;
          }
          for (const struct applet *a = applets; a->name; a++)
              if (strcmp(name, a->name) == 0) return a->fn(argc, argv);
          return watch_main(argc, argv);
      }
      EOF
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link. cc-wrapper auto-injects -L paths for ncurses from
      # buildInputs; NCLIBS adds -lncursesw / -lncurses (+ -ltinfo when
      # split). -lm for tload's load-avg math. We deliberately avoid
      # passing $NIX_LDFLAGS verbatim because cosmocc rejects -rpath.
      $CC -o multicall/procps-ng \
        multicall/dispatcher.o \
        multicall/watch.o multicall/uptime.o multicall/tload.o \
        multicall/strutils.o multicall/fileutils.o \
        multicall/portable-libproc.o \
        $NCLIBS
    '' else ''
      # darwin (engine) fold: build each applet as its own normal executable
      # (real `main`, NO -Dmain rename). The unpin-llvm cc-wrapper compiles to
      # bitcode and the capture shim records each link's objects into a
      # $UNPIN_LINK_DIR/<app>.link sidecar; nix-lib's multicallModuleHookLTO
      # reads those, builds one bitcode module per applet, and selfFold merges
      # the three with the engine dispatcher. No hand-rolled dispatcher here.
      #
      # Every applet links ALL shared objects + NCLIBS uniformly: the module
      # hook internalizes each program's module independently (unused code is
      # made local, not eliminated) and llvm-link auto-renames the resulting
      # internal duplicates, so sharing strutils/fileutils/portable-libproc
      # across the three costs a little dead code, never a symbol clash. The
      # output basename IS the applet name so the sidecar is <app>.link, which
      # is what darwinPrograms lists.
      for app in ${lib.concatStringsSep " " applets}; do
        $CC $NIX_CFLAGS_COMPILE $CFLAGS_BASE -c -o multicall/$app.o src/$app.c
        $CC -o multicall/$app \
          multicall/$app.o \
          multicall/strutils.o multicall/fileutils.o \
          multicall/portable-libproc.o \
          $NCLIBS
      done
    '') + ''

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
    '' + (if isCosmo then ''
      install -m755 multicall/procps-ng "$out/bin/procps-ng"
      for app in ${lib.concatStringsSep " " applets}; do
        ln -s procps-ng "$out/bin/$app"
      done
    '' else ''
      # Install the three programs as separate binaries — the base drv the
      # engine self-fold consumes (via its `module` output), same shape as a
      # plain multi-binary package (coreutils' ls/cat/…). The shipped binary
      # is the self-folded one; these are just the fold's inputs.
      for app in ${lib.concatStringsSep " " applets}; do
        install -m755 "multicall/$app" "$out/bin/$app"
      done
    '') + ''

      # Embed the 3 portable applets' man pages (committed roff under the
      # source `man/` dir). The darwin self-fold merges $out/share/man via the
      # manifest's manRoot; the Windows/cosmo build ignores this $out and uses
      # flake.nix's winManRoot (same 3 pages) so it doesn't over-embed the
      # full Linux nixpkgs procps man set.
      for app in ${lib.concatStringsSep " " applets}; do
        install -Dm644 "man/$app.1" "$out/share/man/man1/$app.1"
      done

      runHook postInstall
    '';
  };
in
# cosmo/windows ships this drv directly (the engine self-fold doesn't run on
# cosmocc), so it self-embeds its aliases here: cosmoApelinkBins renames every
# ELF to `<name>.exe` and rewires same-dir symlinks, so the primary is
# `procps-ng.exe`.
#
# Native darwin returns the raw 3-binary drv instead: nix-lib's engine module
# hook + selfFold (driven by flake.nix's `multicall.darwinPrograms`) consume its
# `module` output and produce the single folded binary — no aliases/dispatcher
# to add here.
if isCosmo then
  lib.withAliases pkgs
    {
      primary = "procps-ng.exe";
      aliasesFromSymlinksIn = "bin";
    }
    multicall
else
  multicall
