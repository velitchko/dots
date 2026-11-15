// SPDX-License-Identifier: GPL-3.0-or-later
// Session actions + idle inhibit. The session is started directly by
// SDDM's wayland-session script via Hyprland's own start-hyprland, not
// uwsm -- there is no uwsm-managed unit to stop, so logout goes through
// hyprctl like the other Hyprland-owned actions in this file.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool inhibitIdle: false
    // Global tiling/floating layout mode (owned by Hyprland: lib/floatmode.lua)
    property bool floatMode: false
    function toggleFloatMode() { Quickshell.execDetached(["hyprctl", "dispatch", "KesselToggleFloat"]) }

    function lock()     { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"]) }
    function suspend()  { Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/lock.sh\"; sleep 1; systemctl suspend"]) }
    // This Hyprland build's `hyprctl dispatch` takes a Lua expression, not the
    // classic bare dispatcher name -- plain "exit" silently fails to parse.
    // hl.dsp.exit() is upstream's own default binding for this (see
    // /usr/share/hypr/hyprland.lua's mainMod+M), used here since hyprshutdown
    // isn't installed on this machine.
    function logout()   { Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]) }
    function reboot()   { Quickshell.execDetached(["systemctl", "reboot"]) }
    function poweroff() { Quickshell.execDetached(["systemctl", "poweroff"]) }
}
