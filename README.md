# Luanti Server for Pelican Panel

A custom [Luanti](https://www.luanti.org/) (formerly Minetest) server Docker image built for use with the [Pelican](https://pelican.dev/) game server panel.

## Why does this exist?

The [official Luanti Docker image](https://github.com/luanti-org/luanti/pkgs/container/luanti) has two issues that make it incompatible with Pelican:

1. **Hardcoded entrypoint** — The official image uses `ENTRYPOINT ["/usr/local/bin/luantiserver"]` with `CMD ["--config", "/etc/minetest/minetest.conf"]`. Pelican (via Wings) passes the startup command through a `STARTUP` environment variable, not as Docker `CMD` arguments. This means the startup command configured in the egg (including `--gameid`, `--port`, `--terminal`, `--config`, etc.) is completely ignored.

2. **No ncurses support** — The official image is compiled without ncurses (`--terminal` is silently ignored), so the server never reads stdin. This makes the Pelican web console non-functional — you can't send commands to the server.

This image solves both problems by:
- Using a [Pelican-compatible entrypoint](entrypoint.sh) that reads the `STARTUP` env var and executes it (the same pattern used by [pelican-eggs/yolks](https://github.com/pelican-eggs/yolks) images)
- Compiling Luanti from source with `ENABLE_CURSES=TRUE` so `--terminal` works and the Pelican console can send commands to the server

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

## Known limitations

- **Console output delay** — Due to how ncurses manages screen redraws inside a Docker container, command output in the Pelican console may appear delayed by one input. Commands still execute immediately; the display just updates on the next interaction. This is a cosmetic issue inherent to running ncurses applications in containers.
