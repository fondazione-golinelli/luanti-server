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
- Normalizing Luanti file permissions at startup (`chmod -R u+rwX`, plus `chown -R` when running as root) so uploaded worlds don't fail due to ownership/mode mismatches
- Converting Pelican's allocation-less `SERVER_PORT=0` case into a stable internal port (`30000` by default) so internal-only servers can run behind `mt-multiserver-proxy` without needing a public allocation

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

When enabled, the entrypoint always runs a recursive:

- `chmod -R u+rwX` on Luanti data paths (fixes missing directory execute bits from broken uploads)

If the container is running as root, it also runs:

- `chown -R container:container` on those same paths

Affected paths:

- `/home/container/.luanti`
- `/home/container/.cache/luanti`
- `/home/container/.minetest` (if present)
- `/home/container/server.log` (if present)

If you do not want this behavior, set:

```
LUANTI_FIX_PERMS=0
```

## Internal-only servers

When a server is created through the Pelican application API without an allocation, Pelican injects `SERVER_PORT=0` into the container environment.

This image treats that as:

```text
SERVER_PORT=${LUANTI_INTERNAL_PORT:-30000}
```

That gives you a stable internal port for servers that should only be reachable over the shared Docker network, which is a good fit for `mt-multiserver-proxy`-managed minigame instances.

## Known limitations

- This image defaults to Luanti plain terminal mode for panel compatibility. If you force `LUANTI_TERMINAL_PLAIN=0`, ncurses behavior depends on your host PTY implementation and may reintroduce delayed redraw issues.
- Startup permission fixing (`LUANTI_FIX_PERMS=1`) can take noticeable time on very large worlds because it runs recursive `chmod` (and `chown` when root).
- Upstream Luanti terminal internals can change between releases; the patch may occasionally need updates when new Luanti versions are published.
