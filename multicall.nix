# Upstream procps-ng ships 17 separate binaries (ps, top, free, kill,
# pgrep/pkill/pidwait, pidof, pmap, pwdx, slabtop, hugetop, sysctl,
# tload, uptime, vmstat, watch). All share `local/strutils.c`,
# `local/fileutils.c`, `local/signals.c`, `local/units.c`, and the
# generated per-tool helpers; automake compiles each .c with a
# per-program prefix (`src_kill-strutils.o` vs `src_pgrep-strutils.o`)
# so the .o files don't collide on disk, but the SYMBOL names inside
# (`set_program_name`, `strutils_…`, …) are identical → can't link
# them all into one binary without privatising the per-tool globals.
#
# Same post-link recipe as e2fsprogs / util-linux (see
# `[[feedback-post-link-multicall-recipe]]`):
#
#   1. `make` runs upstream normally — every tool's .o set lands in
#      `src/`, `src/ps/`, `src/top/`, `local/`.
#   2. Scan the post-configure `Makefile` for `am_<san>_OBJECTS = …`.
#      Per-tool helpers and `am__objects_N` indirections resolved the
#      same way as util-linux.nix. `_la_OBJECTS` (libproc2.la, libtool
#      convenience archive) skipped.
#   3. For each program: `ld -r` → partial-link object; `objcopy
#      --redefine-sym` renames `main` → `<san>_main` and every other
#      defined global `foo` → `<san>__foo` (privately scoped across
#      the final link). COMDAT thunks (`__x86.get_pc_thunk.*`) skipped.
#   4. Generate `dispatcher.c` (basename(argv[0]) → `<san>_main` plus
#      `procps-ng <applet>` form). The build-rule name maps to the
#      installed name via two transforms: (a) basename strip
#      (`src/top/top` → `top`, `src/ps/pscommand` → `pscommand`);
#      (b) `pscommand` → `ps` (procps's `transform` rule). Both applied
#      before emitting dispatcher entries.
#   5. Final link delegated to upstream's Makefile via injected
#      `unpin-multicall.mk` — reuses `$(LDADD)` resolution including
#      `library/libproc2.la` (libtool archive) and any system-lib
#      variables configure detected.
#   6. Strip upstream binaries and replace with one `procps-ng` plus
#      argv[0]-dispatch symlinks; `lib.withAliases` harvests them.
#
# Linux-only: procps reads `/proc` exhaustively; `meta.platforms` is
# `*-linux` and several deeper headers (`<sys/sysinfo.h>`) are Linux-
# specific.
{ lib }:
pkgs:
let
  multicall = pkgs.pkgsStatic.procps.overrideAttrs (old: {
    pname = "procps-ng-multi";

    # procps's `unsigned personality` global in src/ps/global.c collides
    # with musl's `int personality(unsigned long)` syscall wrapper at LTO
    # type-merge time ("variable 'personality' redeclared as function").
    # Surfaces when chain-LTO whole-archives musl into the same LTO unit
    # as procps's bitcode. Rename procps's global to `ps_personality_setting`
    # — procps never calls musl's personality(2) syscall, so this is a
    # one-way collision fix.
    patches = (old.patches or [ ]) ++ [ ./personality-rename.patch ];

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p multicall

      echo "=== procps-ng multicall postBuild (cwd=$PWD) ==="

      # 1. Scan post-configure Makefile for `am_<san>_OBJECTS = …` and
      #    `<orig>$(EXEEXT): $(<san>_OBJECTS)` build rules. Strip out
      #    conditional-false @COND_FALSE@ markers, expand $(OBJEXT) and
      #    $(EXEEXT), resolve $(am__objects_N) indirections. Skip
      #    `_la_OBJECTS` (libtool .lo, linked at final stage as .a).
      awk '
        function clean(s,   r) {
          r = s
          gsub(/@[A-Z_]+_TRUE@/, "", r)
          gsub(/@[A-Z_]+_FALSE@/, "", r)
          gsub(/\$\(OBJEXT\)/, "o", r)
          gsub(/\$\(EXEEXT\)/, "", r)
          return r
        }
        function read_block(start_line,   block, next_line) {
          block = start_line
          while (match(block, /\\$/)) {
            sub(/\\$/, "", block)
            if ((getline next_line) <= 0) break
            block = block " " next_line
          }
          return block
        }
        function expand_refs(s,   key, parts, n, i, out) {
          n = split(s, parts, /[[:space:]]+/)
          out = ""
          for (i = 1; i <= n; i++) {
            if (parts[i] == "") continue
            if (match(parts[i], /^\$\(am__objects_[0-9]+\)$/)) {
              key = parts[i]; sub(/^\$\(/, "", key); sub(/\)$/, "", key)
              if (key in objMap) out = out " " objMap[key]
            } else {
              out = out " " parts[i]
            }
          }
          return out
        }
        /^am__objects_[0-9]+[[:space:]]*=/ {
          name = $1
          block = clean(read_block($0))
          sub(/^[^=]*=[[:space:]]*/, "", block)
          objMap[name] = block
          next
        }
        /^am_[A-Za-z0-9_.-]+_OBJECTS[[:space:]]*=/ {
          if ($1 ~ /_la_OBJECTS$/) next
          san = $1
          sub(/^am_/, "", san)
          sub(/_OBJECTS$/, "", san)
          block = clean(read_block($0))
          sub(/^[^=]*=[[:space:]]*/, "", block)
          block = expand_refs(block)
          n = split(block, parts, /[[:space:]]+/)
          filtered = ""
          for (i = 1; i <= n; i++) {
            if (parts[i] ~ /\.o$/) filtered = filtered " " parts[i]
          }
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", filtered)
          if (filtered != "") sanObjs[san] = filtered
          next
        }
        /^[A-Za-z0-9_./-]+\$\(EXEEXT\):[[:space:]]+\$\([A-Za-z0-9_-]+_OBJECTS\)/ {
          orig = $1
          sub(/\$\(EXEEXT\):.*/, "", orig)
          rest = $0
          if (match(rest, /\$\([A-Za-z0-9_-]+_OBJECTS\)/)) {
            ref = substr(rest, RSTART, RLENGTH)
            san = ref
            sub(/^\$\(/, "", san); sub(/_OBJECTS\)$/, "", san)
            origMap[san] = orig
          }
          next
        }
        END {
          for (san in sanObjs) {
            orig = (san in origMap) ? origMap[san] : san
            print orig "\t" san "\t" sanObjs[san]
          }
        }
      ' Makefile > multicall/tools.tsv

      # 2. Filter:
      #    - drop tests/test_* (built only with --enable-tests);
      #    - drop sample_* if any;
      #    - skip tools whose .o set has missing files (conditional
      #      builds upstream didn't actually compile);
      #    - apply procps installed-name transform:
      #        src/top/top         → top
      #        src/ps/pscommand    → ps
      #        src/<name>          → <name>
      awk -F'\t' '
        $1 !~ /^src\/tests\// && $1 !~ /^sample_/ {
          n = split($3, parts, /[[:space:]]+/)
          ok = 1
          for (i = 1; i <= n; i++) {
            if (parts[i] != "") {
              cmd = "test -f \"" parts[i] "\""
              if (system(cmd) != 0) { ok = 0; break }
            }
          }
          if (!ok) {
            print "SKIP " $1 " (missing .o files)" > "/dev/stderr"
            next
          }
          orig = $1
          # Strip dirname → basename
          n = split(orig, p, "/")
          installed = p[n]
          # procps `transform = s/pscommand/ps/`
          if (installed == "pscommand") installed = "ps"
          print installed "\t" $2 "\t" $3
        }
      ' multicall/tools.tsv > multicall/tools.filtered.tsv

      echo "=== procps-ng multicall: $(wc -l < multicall/tools.filtered.tsv) tools to bundle ==="
      cat multicall/tools.filtered.tsv | awk -F'\t' '{ print "  " $1 " ← " $2 }' >&2
      if [ ! -s multicall/tools.filtered.tsv ]; then
        echo "ERROR: no tools to bundle. Makefile parsing mismatch?" >&2
        exit 1
      fi

      # 3. X+Z: rebuild every tool with renames at preprocessor time.
      #
      #    Many procps tools share .c source files (`local/fileutils.c`,
      #    `local/strutils.c`, …) but only top/watch/slabtop/ps have
      #    per-program CFLAGS in Makefile.am — automake emits prefixed
      #    object names (`local/src_top_top-fileutils.o`) only for those.
      #    The rest (pidof/free/kill/…) compile shared .c sources to a
      #    single shared `local/fileutils.o` path. So our rebuild has to
      #    avoid clobbering between tool iterations.
      #
      #    Two phases:
      #    A. Discovery: for every tool, NM its currently-present .o
      #       set (the first-pass output of upstream's buildPhase, with
      #       canonical un-renamed symbols) and emit
      #       `multicall/<san>.rename.h` with `#define <sym> <san>__<sym>`
      #       lines for every defined global, plus `#define main
      #       <san>_main`. Skip COMDAT thunks (`__x86.get_pc_thunk.*`).
      #    B. Per-tool rebuild + isolate: rm the tool's .o files,
      #       re-run `make $objs` with `NIX_CFLAGS_COMPILE` augmented
      #       to `-include` the per-tool rename header. The
      #       gcc-wrapper prepends those flags to every gcc call.
      #       Immediately copy the freshly-recompiled .o files into
      #       `multicall/<san>/` so the NEXT iteration's rebuild
      #       can clobber the shared path without losing this tool's
      #       bits. Final link consumes the copies.
      #
      #    Output is bitcode all the way down — no `ld -r`, no
      #    `-flinker-output=nolto-rel`, no `objcopy --redefine-sym`.
      _orig_NIX_CFLAGS_COMPILE=''${NIX_CFLAGS_COMPILE:-}

      # Phase A: discovery
      while IFS=$'\t' read -r tool san objs; do
        {
          echo "/* multicall rename header: $san */"
          echo "#define main ''${san}_main"
          # Only valid C identifiers: gcc LTO sometimes emits global
          # symbols with dot-disambiguation suffixes that aren't legal
          # cpp macro names.
          $NM --defined-only -g $objs 2>/dev/null \
            | awk -v s="$san" '
                $2 ~ /^[TBDRWVC]$/ \
                  && $3 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ \
                  && $3 != "main" {
                  if (!seen[$3]++) print "#define " $3 " " s "__" $3
                }'
        } > multicall/$san.rename.h
      done < multicall/tools.filtered.tsv

      # Phase B: per-tool rebuild and isolate
      : > multicall/all_objs.list
      : > multicall/applets.list
      while IFS=$'\t' read -r tool san objs; do
        rm -f $objs
        NIX_CFLAGS_COMPILE="$_orig_NIX_CFLAGS_COMPILE -include $PWD/multicall/$san.rename.h" \
          make -j''${NIX_BUILD_CORES:-1} $objs

        mkdir -p multicall/$san
        for obj in $objs; do
          # Flatten path so multicall/<san>/<flat>.o is unique
          # (e.g. `local/fileutils.o` → `local_fileutils.o`)
          flat=$(echo "$obj" | tr '/' '_')
          cp "$obj" "multicall/$san/$flat"
          echo "multicall/$san/$flat" >> multicall/all_objs.list
        done
        printf '%s\t%s\n' "$tool" "$san" >> multicall/applets.list
      done < multicall/tools.filtered.tsv

      # 4. dispatcher.c from multicall/applets.list (TSV name\tfn) via the
      #    shared Recipe-A generator. defaultApplet=src_ps_pscommand routes
      #    --version/--help and a renamed binary into ps (see nix-lib
      #    lib.multicallTableDispatcherC).
${lib.multicallTableDispatcherC { name = "procps-ng"; defaultApplet = "src_ps_pscommand"; }}

      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # 5. Final link via injected Makefile fragment.
      install -m644 ${multicallMk} unpin-multicall.mk

      make -f Makefile -f unpin-multicall.mk \
        MULTI_TOOL_OBJS="$(tr '\n' ' ' < multicall/all_objs.list)" \
        MULTI_GROUP_OPEN="-Wl,--start-group" \
        MULTI_GROUP_CLOSE="-Wl,--end-group" \
        MULTI_LIBGCC="-lgcc" \
        multicall-link
    '';

    # Skip upstream's `make install`: after X+Z's per-tool recompile
    # (which renamed `main` to `<san>_main` in every tool's .o files),
    # automake's install rule would relink each src/<tool> binary
    # standalone — those links can't resolve `main` because we renamed
    # it. We don't need the per-tool binaries anyway; only the
    # multicall and its applet symlinks ship.
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 multicall/procps-ng "$out/bin/procps-ng"
      while IFS=$'\t' read -r tool san; do
        ln -s procps-ng "$out/bin/$tool"
      done < multicall/applets.list

      # Embed each bundled applet's man page (withMan harvests
      # $out/share/man into the unified unpin/ ZIP). The pages are
      # committed roff under the source `man/` dir; pkill/pidwait are
      # `.so man1/pgrep.1` redirects the unpin reader resolves. hugetop
      # has no upstream man page, so its glob simply finds nothing.
      while IFS=$'\t' read -r tool san; do
        for s in 1 5 8; do
          [ -f "man/$tool.$s" ] && install -Dm644 "man/$tool.$s" "$out/share/man/man$s/$tool.$s"
        done
      done < multicall/applets.list
      # sysctl's config-file page rides along (not an applet name).
      [ -f man/sysctl.conf.5 ] && install -Dm644 man/sysctl.conf.5 "$out/share/man/man5/sysctl.conf.5"

      runHook postInstall
    '';
  });

  # libtool emits `library/.libs/libproc2.a` for the convenience archive.
  # slabtop/top/watch/tload/hugetop pull ncurses + tinfo for the live UI;
  # those come via `propagatedBuildInputs` (ncurses-static-dev) so
  # configure detects them via pkg-config and sets $(NCURSES_LIBS) +
  # $(TINFO_LIBS). $(MATH_LIBS) is wanted by top. The rest of the
  # configure-detected lib slots stay empty under pkgsStatic (no
  # systemd / selinux / namespace headers).
  # X+Z final link: feed dispatcher.o + every tool's renamed .o files
  # directly into gcc. All .o are bitcode (no per-tool materialization),
  # so lto-plugin runs the full LTO across tools + libproc2 + musl.
  multicallMk = pkgs.writeText "unpin-procps-multicall.mk" ''
    MULTI_OUT ?= multicall/procps-ng

    .PHONY: multicall-link
    multicall-link: $(MULTI_OUT)

    $(MULTI_OUT): multicall/dispatcher.o $(MULTI_TOOL_OBJS)
    	$(CC) $(AM_LDFLAGS) $(LDFLAGS) -o $@ \
    		multicall/dispatcher.o $(MULTI_TOOL_OBJS) \
    		$(MULTI_GROUP_OPEN) \
    		library/.libs/libproc2.a \
    		$(NCURSES_LIBS) $(TINFO_LIBS) $(MATH_LIBS) \
    		$(SYSTEMD_LIBS) $(SELINUX_LIBS) $(NAMESPACE_LIBS) \
    		$(LIBS) \
    		$(MULTI_LIBGCC) \
    		$(MULTI_GROUP_CLOSE)
  '';
in
lib.withAliases pkgs
  {
    primary = "procps-ng";
    aliasesFromSymlinksIn = "bin";
  }
  multicall
