# procps-ng

[procps-ng](https://gitlab.com/procps-ng/procps) — `ps`, `top`, `free`, `uptime`, `vmstat` and friends, as a single self-contained binary built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/procps-ng/actions/workflows/procps-ng.yml/badge.svg)](https://github.com/unpins/procps-ng/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install procps-ng`.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin procps-ng watch -n 1 date
unpin procps-ng uptime
```

To install the programs onto your PATH:

```bash
unpin install procps-ng
```

`unpin install procps-ng` creates the `ps`, `top`, `free`, `watch`, `uptime`, and other commands — the Linux-only set is wider than macOS/Windows (full list: `unpin info procps-ng`, or the table below).

## Programs

| programs | Linux | macOS | Windows |
| :--- | :---: | :---: | :---: |
| `ps`, `top`, `free`, `kill`, `pgrep`, `pkill`, `pidwait`, `pidof`, `pmap`, `pwdx`, `slabtop`, `hugetop`, `sysctl`, `vmstat` | ✓ | — | — |
| `watch`, `uptime`, `tload` | ✓ | ✓ | ✓ |

The Linux-only programs read `/proc` directly; their macOS/Windows analogues are different programs entirely (e.g. macOS already ships its own `ps`/`top`/`sysctl`). The three portable programs share a single executable on each OS.

## Man pages

Each binary embeds the man pages for the programs it actually ships — read with `unpin man procps-ng`. Linux carries the full set (`ps`, `top`, `free`, `kill`, `pgrep`/`pkill`/`pidwait`, `pidof`, `pmap`, `pwdx`, `slabtop`, `sysctl` + `sysctl.conf`, `vmstat`, `watch`, `uptime`, `tload`); macOS and Windows carry just `watch`, `uptime`, and `tload`.

