#!/bin/bash -e

rm -rf /tmp/.X*
export PATH="${PATH}:/opt/VirtualGL/bin"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"

# /etc/init.d/dbus start

export DISPLAY=":0"
VNC_SCREEN="${VNC_SCREEN:-1280x720x24}"
if [ "${NOVNC_ENABLE}" = "true" ]; then
    # TigerVNC is the X server and the VNC server in one process, so there's no
    # separate process polling the screen for changes as x11vnc would.
    mkdir -p /home/wineuser/logs
    Xtigervnc "${DISPLAY}" -ac -geometry "${VNC_SCREEN%x*}" -depth "${VNC_SCREEN##*x}" \
        -rfbport 5900 -rfbauth /home/wineuser/.vnc/passwd -SecurityTypes VncAuth -AlwaysShared \
        +extension "GLX" +iglx -nolisten "tcp" -noreset > /home/wineuser/logs/xtigervnc.log 2>&1 &
else
    Xvfb "${DISPLAY}" -ac -screen "0" "${VNC_SCREEN}" -dpi "72" +extension "RANDR" +extension "GLX" +iglx +extension "MIT-SHM" +render -nolisten "tcp" -noreset -shmem &
fi
# Wait for X11 to start
echo "Waiting for X socket"
until [ -S "/tmp/.X11-unix/X${DISPLAY/:/}" ]; do sleep 1; done
echo "X socket is ready"

# start a window manager since the code needs to grep the  window id of tmnf
nohup fluxbox >/dev/null 2>&1 < /dev/null &
echo "Fluxbox started."

export VGL_DISPLAY="egl"
export VGL_REFRESHRATE="${REFRESH:-30}"

echo "Session Running."

if [ "${NOVNC_ENABLE}" = "true" ]; then
    websockify --web /usr/share/novnc/ --log-file /home/wineuser/logs/websockify.log \
        6080 localhost:5900 &
    echo "noVNC available at http://localhost:6080"
fi

# exec so the command gets `docker stop`'s SIGTERM and can shut down cleanly.
exec "$@"
