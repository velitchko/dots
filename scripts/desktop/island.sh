#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# island.sh start|stop|restart|status — manage the Quickshell island.
# Purely optional: the desktop works without it.
#
# Notifications: the island owns org.freedesktop.Notifications while it runs.
# dunst stays installed and D-Bus activatable, so if the island is stopped or
# crashes, the next notification starts dunst automatically. We only *stop*
# dunst here (never disable it) so the island can claim the name.
set -u
cfg=kessel
# Allow starting from SSH / a TTY: find the session the island belongs to.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"; export HYPRLAND_INSTANCE_SIGNATURE
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" && ls wayland-[0-9] 2>/dev/null | head -1)"; export WAYLAND_DISPLAY
fi
# Polkit: exactly one agent per session. The island is the agent while it runs;
# polkit-gnome takes over whenever it doesn't (stopped, failed, or disabled).
GNOME_AGENT=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
gnome_agent_on()  { pgrep -x polkit-gnome-au >/dev/null || { [[ -x $GNOME_AGENT ]] && setsid -f "$GNOME_AGENT" >/dev/null 2>&1; }; }
gnome_agent_off() { for p in $(pgrep -x polkit-gnome-au); do kill "$p" 2>/dev/null; done; sleep 0.2; }

have() { command -v qs >/dev/null 2>&1 && [[ -f "$HOME/.config/quickshell/$cfg/shell.qml" ]]; }
running() { qs list --all 2>/dev/null | grep -q "/quickshell/$cfg/shell.qml"; }
case "${1:-start}" in
    start)
        have || exit 0
        running && exit 0
        systemctl --user stop dunst.service 2>/dev/null || true
        gnome_agent_off
        export QS_ICON_THEME="${QS_ICON_THEME:-Papirus-Dark}"
        qs -n -c "$cfg" -d >/dev/null 2>&1
        # A config error makes Quickshell exit right away — say so instead of failing silently.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 0.3
            if running; then
                # make sure someone is the polkit agent
                sleep 0.5
                [[ "$(qs -c "$cfg" ipc call island polkitStatus 2>/dev/null)" == registered ]] || gnome_agent_on
                exit 0
            fi
        done
        gnome_agent_on
        err="$(qs log -c "$cfg" 2>/dev/null | grep -E 'caused by' | tail -1 | sed 's/.*caused by //')"
        notify-send -u critical -a Island "Island failed to start" "${err:-see: qs log -c $cfg}" 2>/dev/null || true
        echo "island: failed to start: ${err:-unknown}" >&2
        exit 1 ;;
    stop)
        # Close any open panel first: tearing down a focused text field crashes
        # Qt 6.12 at shutdown (QInputMethod::commit in ~QQuickItem).
        # Graceful: the island drops focus from text fields, then quits itself.
        if qs -c "$cfg" ipc call island quit >/dev/null 2>&1; then
            for _ in $(seq 1 20); do running || break; sleep 0.1; done
        fi
        running && { qs kill -c "$cfg" >/dev/null 2>&1 || true; }   # fallback; never pkill -f: too broad
        [[ ${1:-} == stop ]] && gnome_agent_on
        true ;;
    restart) "$0" stop; sleep 0.4; "$0" start ;;
    status)  qs list --all 2>/dev/null ;;
    *)       echo "usage: $0 start|stop|restart|status" >&2; exit 2 ;;
esac
