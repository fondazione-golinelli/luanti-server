# Luanti Server for Pelican Panel

A custom [Luanti](https://www.luanti.org/) (formerly Minetest) server Docker image built for use with the [Pelican](https://pelican.dev/) game server panel.

## Why does this exist?

The [official Luanti Docker image](https://github.com/luanti-org/luanti/pkgs/container/luanti) has two issues that make it incompatible with Pelican:

1. **Hardcoded entrypoint** — The official image uses `ENTRYPOINT ["/usr/local/bin/luantiserver"]` with `CMD ["--config", "/etc/minetest/minetest.conf"]`. Pelican (via Wings) passes the startup command through a `STARTUP` environment variable, not as Docker `CMD` arguments. This means the startup command configured in the egg (including `--gameid`, `--port`, `--terminal`, `--config`, etc.) is completely ignored.

2. **No ncurses support** — The official image is compiled without ncurses (`--terminal` is silently ignored), so the server never reads stdin. This makes the Pelican web console non-functional — you can't send commands to the server.

This image solves both problems by:
- Using a [Pelican-compatible entrypoint](entrypoint.sh) that reads the `STARTUP` env var and executes it (the same pattern used by [pelican-eggs/yolks](https://github.com/pelican-eggs/yolks) images)
- Compiling Luanti from source with `ENABLE_CURSES=TRUE` so `--terminal` works and the Pelican console can send commands to the server
- Applying a small source patch during build that adds a plain (non-ncurses) terminal path for panel PTYs, enabled by default with `LUANTI_TERMINAL_PLAIN=1` in this container
- Translating Luanti terminal escape markup to ANSI colors in plain mode, so panel logs stay readable and colored without raw `@...` markers
- Fixing ownership for Luanti data directories at startup (`chown -R`) so worlds uploaded through SFTP don't fail due to UID/GID mismatches

## Image

```
ghcr.io/fondazione-golinelli/luanti-server:latest
```

Tags follow Luanti releases:
- `latest` — most recent Luanti release
- `5.15.1` — specific version
- `5.15` — minor version (latest patch)

## Pelican Egg

An egg configuration file is included in this repo: [egg-luanti.json](egg-luanti.json)

Import it into your Pelican panel to get a ready-to-use Luanti server egg with support for community game downloads, server configuration, and more.

## Automatic builds

A GitHub Action checks daily for new [Luanti releases](https://github.com/luanti-org/luanti/releases). When a new version is detected, the image is automatically built and published to GHCR. Builds can also be triggered manually via workflow dispatch.

## Terminal behavior in Pelican

By default, this image sets:

```
LUANTI_TERMINAL_PLAIN=1
```

This keeps `--terminal` command input support but bypasses ncurses screen redraw logic, which avoids the common one-line-delayed output issue in panel PTYs.

In plain mode, Luanti terminal markup is converted to ANSI colors before printing, so logs stay readable in Pelican without raw `@...` formatting artifacts.

If you want to test the upstream ncurses terminal behavior, set:

```
LUANTI_TERMINAL_PLAIN=0
```

## File ownership for SFTP uploads

By default, this image sets:

```
LUANTI_FIX_PERMS=1
```

When enabled, the entrypoint starts as root, runs a recursive `chown` on:

- `/home/container/.luanti`
- `/home/container/.cache/luanti`
- `/home/container/server.log` (if present)

Then it drops privileges and starts Luanti as the `container` user.

If you do not want this behavior, set:

```
LUANTI_FIX_PERMS=0
```

## Known limitations

- This image defaults to Luanti plain terminal mode for panel compatibility. If you force `LUANTI_TERMINAL_PLAIN=0`, ncurses behavior depends on your host PTY implementation and may reintroduce delayed redraw issues.
- Startup permission fixing (`LUANTI_FIX_PERMS=1`) can take noticeable time on very large worlds because it runs a recursive `chown`.
- Upstream Luanti terminal internals can change between releases; the patch may occasionally need updates when new Luanti versions are published.
