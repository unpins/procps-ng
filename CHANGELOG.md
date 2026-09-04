# Changelog

## [Unreleased]

### Fixed

- `unpin install procps-ng` now creates the commands. In the v4.0.6-1 release
  it created only `procps-ng` itself: the list of program names never made it
  into the published Linux binary, so `ps`, `top`, `free` and the rest were
  installed nowhere. (The Windows `.exe` of that release did carry its list.)
  All 17 names are there now.
- `ps` was offered under the name `pscommand`, which is what the build calls the
  file before installing it and is not a command anyone can run. It is `ps`.
- `man pkill` had nothing to show. Upstream's own makefile drops that page by
  accident; it is written and embedded now, alongside the 17 others.
- The binary no longer carries a path into the machine that built it. The
  v4.0.6-1 release had the terminfo directory of that machine baked in — a
  directory that does not exist on your computer. `top` and `watch` drew the
  same either way, since the built-in fallback already covered it.

### Changed

- Running `procps-ng` with no program now lists the programs and tells you how
  to pick one, instead of guessing. There is no program called `procps-ng`.
- The three `libproc2` pages, which document the C library rather than any
  program in here, are no longer embedded. Every remaining page belongs to a
  program the binary can run.
- Built by the same compiler as the rest of the catalog. The binary grew from
  960 KB to 1.57 MB. Checked on Linux x86_64 and arm64: `ps`, `top`, `free`,
  `uptime` and `watch` all run, and `--unpin-program=` reaches every one of the
  17 names. On macOS the portable subset is `watch`, `uptime` and `tload`, and
  those run there.
