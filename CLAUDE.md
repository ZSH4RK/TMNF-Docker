# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Build the base image (VirtualGL/OpenGL rendering):
```bash
docker build -t tmnf-base:latest -f Dockerfile.base .
```

Build the Vulkan image (must have base image first):
```bash
docker build --build-arg BASE_IMAGE=tmnf-base:latest -t tmnf-vulkan:latest -f Dockerfile.vulkan .
```

Run either image:
```bash
docker run --gpus all -it tmnf-base:latest /bin/bash
docker run --gpus all -e NOVNC_ENABLE=true -p 6080:6080 -it tmnf-base:latest /bin/bash   # with noVNC
```

When `NOVNC_ENABLE=true`, open `http://localhost:6080/vnc.html` in a browser. Password is `mypasswd` (or the `PASSWD` build arg value). Raw VNC on port 5900 is also available if needed:
```bash
docker run --gpus all -e NOVNC_ENABLE=true -p 5900:5900 -p 6080:6080 -it tmnf-base:latest /bin/bash
```

## Architecture

### Two Images, Two Rendering Backends

**`Dockerfile.base`** — uses VirtualGL (OpenGL/EGL hardware acceleration via `vglrun`). The entrypoint starts **Xvfb** as the virtual display.

**`Dockerfile.vulkan`** — extends the base image and adds Vulkan + DXVK (DirectX→Vulkan translation). The entrypoint starts real **Xorg** with the `dummy` driver (`configs/xorg.conf`) instead of Xvfb, because NVIDIA's Vulkan ICD requires a proper Xorg server.

The `BASE_IMAGE` build arg in `Dockerfile.vulkan` must point to a previously built base image.

### Entrypoints

- `scripts/base-entrypoint.sh` — starts Xvfb on `:0`, then Fluxbox, then runs `"$@"` (the CMD)
- `scripts/vulkan-entrypoint.sh` — starts Xorg (dummy driver) on `:0`, then Fluxbox, then runs `"$@"`
- `scripts/start-vnc.sh` — attaches x11vnc to `:0`; must be run after the container starts, not during entrypoint

Both entrypoints export `DISPLAY=:0` and wait for the X socket before proceeding.

### TMNF Runtime

The game runs as `wineuser` (non-root), Wine 32-bit mode (`WINEARCH=win32`), prefix at `/home/wineuser/.wine`. Game data pre-loaded into the container from `game-data/`:
- `game-data/TMInterface/` → TMInterface config and plugins
- `game-data/TmForever/` → TmForever profile and settings
- `game-data/TMLoader/` → TMLoader profile database (controls which mods load)

### Multi-Stage Build in Dockerfile.base

The base Dockerfile uses five stages to improve layer caching:
1. `base` — CUDA/GL base image + locale
2. `updated-ubuntu` — system packages (desktop tools, X11, Wine deps)
3. `with-packages` — VirtualGL installation
4. `with-packages-and-gl` — Wine + TMNF install (runs as `wineuser`)
5. `tmnf-base` — VNC password setup + entrypoint scripts

Stages 1–3 rarely change; stage 4 re-runs if game data or Wine config changes.

### noVNC (Virtual Display)

Controlled by the `NOVNC_ENABLE` env var (default `false`). When `true`, both entrypoints start:
1. `x11vnc` — attaches to `:0`, serves raw VNC on port 5900
2. `websockify` — bridges WebSocket→VNC, serves the noVNC web UI on port 6080

The packages `novnc` and `python3-websockify` are installed in the `updated-ubuntu` stage of `Dockerfile.base`. The conditional startup block lives at the end of both `scripts/base-entrypoint.sh` and `scripts/vulkan-entrypoint.sh`, after the X socket is confirmed ready. VNC password comes from `/home/wineuser/.vnc/passwd` (set at build time from the `PASSWD` env var).

To add noVNC to a new entrypoint, insert this block after the X socket wait:
```bash
if [ "${NOVNC_ENABLE}" = "true" ]; then
    x11vnc -display "${DISPLAY}" -rfbauth /home/wineuser/.vnc/passwd \
        -forever -shared -bg -quiet -o /home/wineuser/logs/x11vnc.log
    websockify --web /usr/share/novnc/ --log-file /home/wineuser/logs/websockify.log \
        6080 localhost:5900 &
    echo "noVNC available at http://localhost:6080"
fi
```
