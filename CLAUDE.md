# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TrustTunnel-Keenetic is a shell-script-based TrustTunnel client installer and service manager for Keenetic routers running Entware. It integrates with the TrustTunnel service and supports two operation modes: SOCKS5 proxy and TUN tunnel interface.

All user-facing text (prompts, README) is in **Russian**. Code comments are in English.

## Architecture

The system has three main components that run on the router:

1. **install.sh** — Bootstrap installer. Detects the latest GitHub release (or accepts `--dev`/`--version` flags), downloads configure.sh, and executes it.

2. **configure.sh** — Interactive configuration script. Checks prerequisites (curl, Entware, ndmc), prompts for mode selection (SOCKS5 vs TUN), auto-detects free Keenetic interface indices via `ndmc`, installs init scripts and WAN hooks, generates `mode.conf`, and optionally downloads the TrustTunnel client binary.

3. **S99trusttunnel** — Entware init script (`/opt/etc/init.d/`). Manages the client process lifecycle with a watchdog that implements exponential backoff (10s→300s, max 10 retries). In TUN mode, handles renaming `tun0` → `opkgtunN` for Keenetic recognition. Runs periodic health checks (HTTP connectivity via curl) and auto-restarts on failure.

4. **010-trusttunnel.sh** — WAN hook (`/opt/etc/ndm/wan.d/`). Triggers service reload when the WAN interface comes up, ensuring client reconnects after network changes.

### Data Flow

```
install.sh → downloads → configure.sh → installs → S99trusttunnel + 010-trusttunnel.sh
                                       → generates → mode.conf
                                       → downloads → trusttunnel_client binary
```

### Key Runtime Paths on Router

- Client binary: `/opt/trusttunnel_client/trusttunnel_client`
- Client config: `/opt/trusttunnel_client/trusttunnel_client.toml`
- Mode config: `/opt/trusttunnel_client/mode.conf`
- Log file: `/opt/var/log/trusttunnel.log` (512KB rotation)
- PID files: `/opt/var/run/trusttunnel.pid`, `trusttunnel_watchdog.pid`

## Shell Scripting Conventions

- All scripts must be **POSIX sh compatible** — no bashisms
- Use `#!/opt/bin/sh` shebang for router scripts (Entware path)
- Process management uses PID files with SIGTERM/SIGKILL fallback pattern
- Error cleanup via `trap` handlers
- Interface index detection parses `ndmc -c 'show interface'` output

## Release Process

Push a tag matching `v*` (e.g., `v1.0.0`) to trigger the GitHub Actions workflow (`.github/workflows/release.yml`) which creates a GitHub Release with auto-generated notes via `softprops/action-gh-release@v2`.

## Service Control (on router)

```sh
/opt/etc/init.d/S99trusttunnel start|stop|restart|reload|status|check
```

- `reload` — soft restart: stops client, watchdog respawns it
- `check` — alias for `status`
