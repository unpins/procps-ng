# procps-ng

Standalone build of [procps-ng](https://gitlab.com/procps-ng/procps).

[![CI](https://github.com/unpins/procps-ng/actions/workflows/procps-ng.yml/badge.svg)](https://github.com/unpins/procps-ng/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Applets

| Applet | Linux | macOS | Windows |
| :--- | :---: | :---: | :---: |
| `ps`, `top`, `free`, `kill`, `pgrep`, `pkill`, `pidwait`, `pidof`, `pmap`, `pwdx`, `slabtop`, `hugetop`, `sysctl`, `vmstat` | ✓ | — | — |
| `watch` | ✓ | ✓ | ✓ |
| `uptime` | ✓ | ✓ | ✓ |
| `tload` | ✓ | ✓ | ✓ |

The Linux-only applets read `/proc` directly; their macOS/Windows analogues are different tools entirely (e.g. macOS already ships its own `ps`/`top`/`sysctl`). The three portable applets share a single multicall executable on each OS; dispatch is by `argv[0]`.

## Usage

```bash
watch -n 1 date
uptime
tload
```

## License

GPL-2.0-or-later (upstream procps-ng).
