# procps-ng

Standalone build of [procps-ng](https://gitlab.com/procps-ng/procps) — `ps`, `top`, `kill`, `pgrep`, `pkill`, `pidwait`, `pidof`, `pmap`, `pwdx`, `free`, `slabtop`, `hugetop`, `sysctl`, `tload`, `uptime`, `vmstat`, `watch`.

[![CI](https://github.com/unpins/procps-ng/actions/workflows/procps-ng.yml/badge.svg)](https://github.com/unpins/procps-ng/actions)
![Linux](https://img.shields.io/badge/Linux-%E2%9C%93-success?logo=linux&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

Linux-only: procps reads `/proc` exhaustively.

## Usage

The package ships one multicall executable, `procps-ng`. `unpin install` materializes the applet shims next to it; dispatch is by `argv[0]`.

```bash
ps aux
top
kill -9 $(pgrep firefox)
free -h
watch -n 1 'cat /proc/loadavg'
```

## License

GPL-2.0-or-later (upstream procps-ng).
