-- SPDX-License-Identifier: GPL-3.0-or-later
-- Kessel — Hyprland entry point.
--
-- Keep this file tiny. Each module is loaded in protected mode: a broken
-- module raises an on-screen notification while the rest of the desktop
-- (and the rescue binds in lib/safety.lua) keeps working.
--
-- Validate before deploying:  KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

local safety = require("lib.safety")

safety.load("monitors")    -- displays: modes, scale, multi-monitor arrangement
safety.load("env")         -- environment / toolkit integration
safety.load("general")     -- UI / aesthetic: gaps, borders, decoration, animations, layouts
safety.load("input")       -- keyboard, pointer, devices
safety.load("workspaces")  -- workspace, window and layer rules
safety.load("exec")        -- autostart / session processes
safety.load("keybinds", function(registry)
    require("lib.binder").apply(registry)
end)
safety.load("custom", nil, { optional = true }) -- personal tweaks, loaded last

safety.finish()            -- ensure rescue binds exist, report failures

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
