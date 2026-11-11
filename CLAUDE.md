# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This repo contains the base Docker infrastructure for running TrackMania Nations Forever (TMNF) in a headless Linux container with GPU rendering. The AI agent lives in a separate repo embedded here as a Git submodule:

```
TMNF-Docker/
├── docker/
│   ├── Dockerfile.base      # Base TMNF image (CUDA + Wine + VirtualGL)
│   ├── Dockerfile.vulkan    # Extends base with Vulkan/DXVK
│   └── Dockerfile.combined  # Adds TMRC agent on top of tmnf-test:latest
├── docker-compose.yml       # Builds and runs the combined image (context = repo root)
├── scripts/
│   ├── base-entrypoint.sh   # Xvfb + Fluxbox + noVNC + CMD
│   ├── vulkan-entrypoint.sh # Xorg(dummy) + Fluxbox + noVNC + CMD
│   ├── start-vnc.sh         # x11vnc helper (manual use)
│   └── run-agent.sh         # CMD for combined image — starts the Python agent
├── game-data/               # Pre-configured TMNF/TMInterface/TMLoader data
├── configs/                 # Xorg config for Vulkan
└── TMRC/                    # Git submodule → https://github.com/ZSH4RK/TMRC.git
    ├── agent/agent.py       # Python agent (connects to TMInterface via socket)
    ├── plugins/
    │   ├── Python_Link.as   # AngelScript socket server (TMInterface plugin)
    │   ├── index.jsx        # TMLoader UI — auto-launches game on startup
    │   └── default.yaml     # TMLoader profile — loads mods + passes map arg
    ├── pyproject.toml
    └── uv.lock
```

The submodule points to a specific commit. To pull the latest TMRC code:
```bash
git submodule update --remote TMRC
```

To edit TMRC code and push it independently:
```bash
cd TMRC          # work in the submodule
git commit ...
git push
cd ..
git add TMRC && git commit -m "Update TMRC submodule"
```

## Build Commands

### Combined image (TMNF + TMRC agent) — primary workflow

Build and run with Docker Compose (from `TMNF-Docker/`):
```bash
docker compose up --build
```

Or build manually:
```bash
docker build -t tmrc:latest -f docker/Dockerfile.combined .
docker run --gpus all -e NOVNC_ENABLE=true -p 6080:6080 tmrc:latest
```

`docker/Dockerfile.combined` uses `tmnf-test:latest` as its base (the pre-built TMNF image). It does **not** rebuild `docker/Dockerfile.base` — that image must already exist locally. To override the base:
```bash
docker build --build-arg BASE_IMAGE=tmnf-base:latest -t tmrc:latest -f docker/Dockerfile.combined .
```

### Base images (rarely rebuilt)

Build the base image (VirtualGL/OpenGL rendering):
```bash
docker build -t tmnf-base:latest -f docker/Dockerfile.base .
```

Build the Vulkan image (must have base image first):
```bash
docker build --build-arg BASE_IMAGE=tmnf-base:latest -t tmnf-vulkan:latest -f docker/Dockerfile.vulkan .
```

> **Note:** `docker/Dockerfile.base` pulls from `nvcr.io` (NVIDIA Container Registry). This requires authentication (`docker login nvcr.io`). The combined image avoids this by layering on a locally cached base.

## Architecture

### Three Images

**`docker/Dockerfile.base`** — CUDA + VirtualGL (OpenGL/EGL via `vglrun`) + Wine + TMNF install. The entrypoint starts **Xvfb** as the virtual display.

**`docker/Dockerfile.vulkan`** — extends the base image with Vulkan + DXVK (DirectX→Vulkan). Uses real **Xorg** with the `dummy` driver (`configs/xorg.conf`) instead of Xvfb, because NVIDIA's Vulkan ICD requires a proper Xorg server.

**`docker/Dockerfile.combined`** — extends `tmnf-test:latest` (a snapshot of the base) with the TMRC Python agent, updated TMInterface plugin, and TMLoader config. This is the image used for AI racing.

### Entrypoints

- `scripts/base-entrypoint.sh` — starts Xvfb (or Xtigervnc when `NOVNC_ENABLE=true`) on `:0`, then Fluxbox, then `exec`s `"$@"` (the CMD)
- `scripts/vulkan-entrypoint.sh` — starts Xorg (dummy driver) on `:0`, then Fluxbox, then runs `"$@"`
- `scripts/run-agent.sh` — CMD for `docker/Dockerfile.combined`; runs `uv run agent/agent.py` from `/home/wineuser/tmrc`

Both base entrypoints export `DISPLAY=:0`, wait for the X socket before proceeding, and conditionally start noVNC when `NOVNC_ENABLE=true`.

### TMNF Runtime

The game runs as `wineuser` (non-root), Wine 32-bit mode (`WINEARCH=win32`), prefix at `/home/wineuser/.wine`. Game data pre-loaded into the container from `game-data/`:
- `game-data/TMInterface/` → TMInterface config and plugins (base image version)
- `game-data/TmForever/` → TmForever profile and settings
- `game-data/TMLoader/` → TMLoader profile database (controls which mods load)

`docker/Dockerfile.combined` overlays updated versions of these files from `TMRC/plugins/`:
- `Python_Link.as` replaces the base image plugin — adds menu-state message draining so `execute_command` (e.g. `map`) is processed while the game is in the menus, not just during race callbacks
- `index.jsx` replaces the TMLoader UI to call `autoLaunch()` on startup
- `default.yaml` passes `A01-Race.Challenge.Gbx` as a launch arg so the game loads directly into a race

### Multi-Stage Build in docker/Dockerfile.base

1. `base` — CUDA/GL base image + locale
2. `updated-ubuntu` — system packages (desktop tools, X11, Wine deps)
3. `with-packages` — VirtualGL installation
4. `with-packages-and-gl` — Wine + TMNF install (runs as `wineuser`)
5. `tmnf-base` — VNC password setup + entrypoint scripts

Stages 1–3 rarely change; stage 4 re-runs if game data or Wine config changes.

### noVNC (Virtual Display)

Controlled by the `NOVNC_ENABLE` env var (default `false`). When `true`:
- `scripts/base-entrypoint.sh` starts `Xtigervnc` in place of Xvfb. It is the X server and the VNC server in one process, on port 5900.
- `scripts/vulkan-entrypoint.sh` needs real Xorg, so it attaches `x11vnc` to `:0`, on port 5900.
- Both start `websockify`, which bridges WebSocket→VNC and serves the noVNC web UI on port 6080.

Open `http://localhost:6080/` in a browser (the combined image redirects this to a scaled, auto-connecting view). Password is `mypasswd` (set at build time via the `PASSWD` build arg). VNC on port 5900 is also available; set native viewers to Tight rather than Raw encoding. Compose publishes these ports on localhost only; set `VNC_BIND=0.0.0.0` to watch from another machine.

`TM_VIEW_INSTANCES` (default 1) sets how many game instances can be watched. Instance `i` is on VNC port `5900+i` and noVNC port `6080+i`. Other instances run on a plain Xvfb with `VGL_READBACK=none`, since training reads the simulation state rather than pixels, so they can't be watched.

The packages `novnc` and `python3-websockify` are installed in the `updated-ubuntu` stage of `docker/Dockerfile.base`. The conditional startup block lives at the end of both entrypoint scripts, after the X socket is confirmed ready.

To add x11vnc-based noVNC to a new entrypoint, insert this block after the X socket wait:
```bash
if [ "${NOVNC_ENABLE}" = "true" ]; then
    x11vnc -display "${DISPLAY}" -rfbauth /home/wineuser/.vnc/passwd \
        -forever -shared -bg -quiet -o /home/wineuser/logs/x11vnc.log
    websockify --web /usr/share/novnc/ --log-file /home/wineuser/logs/websockify.log \
        6080 localhost:5900 &
    echo "noVNC available at http://localhost:6080"
fi
```
