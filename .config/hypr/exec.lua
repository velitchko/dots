-- SPDX-License-Identifier: GPL-3.0-or-later
-- Autostart / session processes. Run once per Hyprland start (not on reload).
-- Nothing here enables systemd services.

local HOME = os.getenv("HOME")

-- Feature toggles ----------------------------------------------------------------
-- Manual lock/unlock with hyprlock verified working on this machine (SUPER+L).
local ENABLE_IDLE   = true
local ENABLE_ISLAND = true

hl.on("hyprland.start", function()
    -- Remote access: WayVNC strictly on loopback (use an SSH tunnel). Never change the address.
    hl.exec_cmd("wayvnc 127.0.0.1 5900")

    -- Desktop plumbing
    -- Polkit agent: the island registers itself; island.sh starts polkit-gnome
    -- whenever the island isn't running (exactly one agent per session).
    if not ENABLE_ISLAND then hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1") end
    -- Wallpaper daemon: awww (remembers the last image per display, animated
    -- transitions); hyprpaper only if awww isn't installed.
    hl.exec_cmd("if command -v awww-daemon >/dev/null; then exec awww-daemon; else exec hyprpaper; fi")
    -- wallpaper + light/dark theme from the last session (theme.sh waits for the daemon)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/theme.sh restore")
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")      -- cursor (no-op if not installed)
    hl.exec_cmd("kbuildsycoca6 --noincremental >/dev/null 2>&1")   -- Dolphin's "Open with" database
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- Notifications: dunst is D-Bus activated on first notification; nothing to start.

    if ENABLE_IDLE then hl.exec_cmd("hypridle") end
    if ENABLE_ISLAND then hl.exec_cmd(HOME .. "/.config/hypr/scripts/island.sh start") end
end)
