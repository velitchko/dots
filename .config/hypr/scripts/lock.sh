#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# lock.sh — lock the session with the Kessel lock screen (Quickshell).
# Safety: if Quickshell is missing or the compositor does not confirm a secure
# lock within 3 s, hyprlock is used instead. Never leaves the session unlocked
# by accident, never stacks two lockers.
#
# Recovery from SSH if a locker ever wedges (tested):
#   for p in $(pgrep -x quickshell); do tr '\0' ' ' </proc/$p/cmdline | grep -q kessel-lock && kill -9 $p; done
#   hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'
# (kill -9 matters: a crashing locker is restarted by Quickshell and would lock again;
#  Hyprland refuses to clear the lock while a live locker holds it.)
set -u
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"; export HYPRLAND_INSTANCE_SIGNATURE
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" && ls wayland-[0-9] 2>/dev/null | head -1)"; export WAYLAND_DISPLAY
fi

cfg="$HOME/.config/quickshell/kessel-lock/shell.qml"
qs_lock_running() { qs list --all 2>/dev/null | grep -q "/quickshell/kessel-lock/shell.qml"; }

# Already locked (by us or hyprlock)? Nothing to do.
qs_lock_running && exit 0
pidof hyprlock >/dev/null && exit 0

fallback() { exec hyprlock; }

command -v qs >/dev/null 2>&1 && [[ -f $cfg ]] || fallback

# The island must not hold a keyboard grab / open panel under the lock.
# Screenshot each output for the lock's "frost over" entrance (the lock starts on
# the sharp desktop and blurs it, instead of a black frame). Raw PPM: no encode
# or decode time. In the private runtime dir, and deleted once the lock has
# loaded them; the lock works without them too.
shots="$XDG_RUNTIME_DIR/kessel-lock"
rm -rf "$shots"; mkdir -m 700 -p "$shots"
if command -v grim >/dev/null && command -v hyprctl >/dev/null; then
    for out in $(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null); do
        timeout 2 grim -t ppm -o "$out" "$shots/$out.ppm" 2>/dev/null &
    done
    wait
fi
# close any open island panel meanwhile (no waiting: an open panel just blurs away)
qs -c kessel ipc call island close >/dev/null 2>&1 &
cleanup_shots() { ( sleep 4; rm -rf "$shots" ) >/dev/null 2>&1 & disown; }

qs -n -c kessel-lock -d >/dev/null 2>&1 || { rm -rf "$shots"; fallback; }
for _ in $(seq 1 30); do
    [[ "$(qs -c kessel-lock ipc call lockstate secure 2>/dev/null)" == yes ]] && { cleanup_shots; exit 0; }
    sleep 0.1
done
rm -rf "$shots"
# Not confirmed: get rid of the half-started locker and use hyprlock.
qs kill -c kessel-lock >/dev/null 2>&1 || true
fallback
