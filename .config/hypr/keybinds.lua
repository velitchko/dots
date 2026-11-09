-- SPDX-License-Identifier: GPL-3.0-or-later
-- Kessel — THE single source of truth for keybindings.
-- Layout follows end-4/dots-hyprland muscle memory (re-implemented, not copied).
--
-- This file is data only. lib/binder.lua turns it into:
--   * real Hyprland binds (hl.bind)
--   * the shortcuts view   ($XDG_RUNTIME_DIR/kessel-shortcuts.txt, SUPER+/)
--   * docs/SHORTCUTS.md    (scripts/gen-shortcuts.sh)
--
-- Entry fields:
--   keys    "MODS + KEY"                      (required)
--   desc    human description                 (required)
--   group   section in the shortcuts view     (required)
--   exec    shell command string              (one of exec / dsp)
--   dsp     function() return hl.dsp.… end    (lazy: hl only exists inside Hyprland)
--   opts    hl.bind options (locked, repeating, mouse, …)
--   hidden  true → bound but not listed (aliases, expanded ranges)
--   doc     true → listed but not bound (summary line for a range)
--
-- Island binds go through scripts/island-or.sh: the island handles them when it
-- runs, otherwise a Quickshell-independent fallback runs (fuzzel, cliphist…).

local S = os.getenv("HOME") .. "/.config/hypr/scripts/"
local function island(fn, fallback)
    return S .. "island-or.sh " .. fn .. (fallback and (" -- " .. fallback) or "")
end

local apps = {
    terminal = "kitty",
    recovery = "kitty bash --norc",
    launcher = "fuzzel",
    browser  = S .. "browser.sh",
    editor   = S .. "editor.sh",
    mixer    = "pavucontrol",
    taskmgr  = "kitty --class htop -e htop",
    files    = "dolphin",
    obsidian = S .. "obsidian.sh",
    lock     = S .. "lock.sh",
}

local b = {}
local function add(e) b[#b + 1] = e end

-- Apps -----------------------------------------------------------------------
add { group = "Apps", keys = "SUPER + Return",         exec = apps.terminal, desc = "Terminal (kitty)" }
-- dwindle picks the split from the window's shape (wide → beside, tall → below).
-- This one always opens the terminal BELOW the focused window; SUPER+ALT+J flips a split afterwards.
add { group = "Apps", keys = "SUPER + ALT + Return", dsp = function() return function()
        hl.dispatch(hl.dsp.layout("preselect d"))
        hl.exec_cmd(apps.terminal)
    end end, desc = "Terminal below (horizontal split)" }
add { group = "Apps", keys = "SUPER + T",              exec = apps.terminal, desc = "Terminal (kitty)", hidden = true }
add { group = "Apps", keys = "CTRL + ALT + T",         exec = apps.terminal, desc = "Terminal (kitty)", hidden = true }
add { group = "Apps", keys = "SUPER + SHIFT + Return", exec = apps.recovery, desc = "Recovery shell (kitty + plain bash)" }
add { group = "Apps", keys = "SUPER + C",              exec = apps.editor,   desc = "Code editor (Neovim)" }
add { group = "Apps", keys = "SUPER + W",              exec = apps.browser,  desc = "Web browser" }
add { group = "Apps", keys = "SUPER + E",              exec = apps.files,    desc = "File manager (Dolphin)" }
add { group = "Apps", keys = "SUPER + O",              exec = apps.obsidian, desc = "Obsidian (notes)" }
add { group = "Apps", keys = "CTRL + SHIFT + Escape",  exec = apps.taskmgr,  desc = "Task manager (htop)" }
add { group = "Apps", keys = "SUPER + SHIFT + Space",  exec = apps.launcher, desc = "App launcher: fuzzel (always available)" }

-- Island (Quickshell) — each falls back when the island is not running --------
add { group = "Island", keys = "SUPER + R",         exec = island("open launcher", "fuzzel"), desc = "Launcher (fallback: fuzzel)" }
-- Tap SUPER alone (end-4 style): fires on release, and Hyprland skips it if another key was pressed meanwhile.
add { group = "Island", keys = "SUPER + SUPER_L",   exec = island("open launcher", "fuzzel"), desc = "Tap Super: launcher (fallback: fuzzel)", opts = { release = true } }
add { group = "Island", keys = "SUPER + ALT + right", exec = "qs -c kessel ipc call island perspectiveNext", desc = "Island: next perspective" }
add { group = "Island", keys = "SUPER + ALT + left",  exec = "qs -c kessel ipc call island perspectivePrev", desc = "Island: previous perspective" }
add { group = "Island", keys = "SUPER + Space",     exec = "qs -c kessel ipc call island toggle", desc = "Focus mode: hide / show the island (frees its screen space)" }
add { group = "Island", keys = "SUPER + V",         exec = island("open clipboard", S .. "clipboard.sh"), desc = "Clipboard history (fallback: fuzzel)" }
add { group = "Island", keys = "SUPER + Tab",       exec = island("open overview"), desc = "Overview: workspaces + window previews" }
add { group = "Island", keys = "SUPER + A",         exec = island("open control"), desc = "Quick settings (Wi-Fi, BT, audio, brightness, power)" }
add { group = "Island", keys = "SUPER + ALT + N",   exec = island("open notifications"), desc = "Notifications + calendar + weather" }
add { group = "Island", keys = "SUPER + G",         exec = island("open notes"), desc = "Workspace: Markdown notes (~/Notes)" }
add { group = "Island", keys = "SUPER + SHIFT + G", exec = island("open board"), desc = "Workspace: kanban board" }
add { group = "Island", keys = "SUPER + M",         exec = island("open media"), desc = "Media player" }
add { group = "Island", keys = "SUPER + SHIFT + V", exec = island("open mixer", "pavucontrol"), desc = "Volume mixer: devices + per-app (fallback: pavucontrol)" }
add { group = "Island", keys = "SUPER + ALT + T",   exec = island("open timer"), desc = "Timer / stopwatch" }
-- No fallback: AI chat is a standalone floating window with its own markdown/math
-- rendering, nothing else on the system can stand in for it when Quickshell isn't running.
add { group = "Island", keys = "SUPER + I",         exec = island("aiChatToggle"), desc = "AI chat" }
add { group = "Island", keys = "CTRL + ALT + Delete", exec = island("open power"), desc = "Session menu (lock, standby, logout, restart, shutdown)" }
add { group = "Island", keys = "SUPER + Escape",    exec = island("open power"), desc = "Session menu", hidden = true }
add { group = "Island", keys = "CTRL + SUPER + T",  exec = island("open wallpaper"), desc = "Wallpaper & theme picker" }
add { group = "Island", keys = "CTRL + SUPER + SHIFT + D", exec = S .. "theme.sh mode toggle", desc = "Toggle light / dark theme" }
add { group = "Island", keys = "SUPER + J",         exec = "qs -c kessel ipc call island toggle", desc = "Show / hide the island", hidden = true }
add { group = "Island", keys = "CTRL + SUPER + R",  exec = "hyprctl reload; " .. S .. "island.sh restart", desc = "Refresh: reload Hyprland + restart the island" }
add { group = "Island", keys = "SUPER + slash",     exec = island("open shortcuts", S .. "shortcuts.sh"), desc = "Shortcuts (this list; fallback: fuzzel)" }

-- Utilities --------------------------------------------------------------------
add { group = "Utilities", keys = "SUPER + SHIFT + S", exec = S .. "screenshot.sh region", desc = "Screenshot region → clipboard + file" }
add { group = "Utilities", keys = "Print",             exec = S .. "screenshot.sh full",   desc = "Screenshot screen → clipboard + file", opts = { locked = true } }
add { group = "Utilities", keys = "SHIFT + Print",     exec = S .. "screenshot.sh region", desc = "Screenshot region", hidden = true }
add { group = "Utilities", keys = "SUPER + SHIFT + C", exec = S .. "colorpicker.sh",       desc = "Color picker → clipboard" }
add { group = "Utilities", keys = "SUPER + SHIFT + R", exec = island("recordRegion"),       desc = "Record region (again to stop)" }
add { group = "Utilities", keys = "SUPER + ALT + R",   exec = island("recordRegion"),       desc = "Record region", hidden = true }
add { group = "Utilities", keys = "CTRL + ALT + R",    exec = island("record"),             desc = "Record screen (again to stop)" }
add { group = "Utilities", keys = "SUPER + period",    exec = S .. "omniglyph.sh",          desc = "Emoji / symbol picker (OmniGlyph)" }
add { group = "Utilities", keys = "SUPER + SHIFT + D", exec = island("dnd"),                desc = "Do not disturb on/off" }

-- Windows ----------------------------------------------------------------------
add { group = "Windows", keys = "SUPER + Q",               dsp = function() return hl.dsp.window.close() end, desc = "Close window" }
add { group = "Windows", keys = "SUPER + SHIFT + ALT + Q", dsp = function() return hl.dsp.window.kill() end, desc = "Force-kill window" }
add { group = "Windows", keys = "SUPER + F",         dsp = function() return hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }) end, desc = "Fullscreen (again to exit)" }
-- Detach: float just this window, centred; pressing again tiles it back.
local function detach()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    local w = hl.get_active_window()
    if w and w.floating then hl.dispatch(hl.dsp.window.center()) end
end
add { group = "Windows", keys = "SUPER + D",         dsp = function() return detach end, desc = "Detach window: float ↔ tile (again to re-tile)" }
add { group = "Windows", keys = "SUPER + ALT + Space", dsp = function() return detach end, desc = "Detach window", hidden = true }
add { group = "Windows", keys = "SUPER + ALT + D",   dsp = function() return hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }) end, desc = "Maximize (again to restore)" }
add { group = "Windows", keys = "SUPER + SHIFT + F", dsp = function() return require("lib.floatmode").toggle end, desc = "Layout mode: all windows tiling ↔ floating" }
add { group = "Windows", keys = "SUPER + ALT + P",   dsp = function() return hl.dsp.window.pin() end, desc = "Pin (show on all workspaces)" }
add { group = "Windows", keys = "SUPER + semicolon", dsp = function() return hl.dsp.layout("splitratio -0.1") end, opts = { repeating = true }, desc = "Narrower (split ratio −)" }
add { group = "Windows", keys = "SUPER + apostrophe", dsp = function() return hl.dsp.layout("splitratio +0.1") end, opts = { repeating = true }, desc = "Wider (split ratio +)" }
add { group = "Windows", keys = "SUPER + ALT + J",   dsp = function() return hl.dsp.layout("togglesplit") end, desc = "Toggle split direction" }

for _, d in ipairs({ "left", "right", "up", "down" }) do
    add { group = "Windows", hidden = true, keys = "SUPER + " .. d,
          dsp = function() return hl.dsp.focus({ direction = d }) end, desc = "Focus " .. d }
    add { group = "Windows", hidden = true, keys = "SUPER + SHIFT + " .. d,
          dsp = function() return hl.dsp.window.move({ direction = d }) end, desc = "Move window " .. d }
end
add { group = "Windows", doc = true, keys = "SUPER + ←↑→↓",         desc = "Focus window in direction" }
add { group = "Windows", doc = true, keys = "SUPER + SHIFT + ←↑→↓", desc = "Move window in direction" }
add { group = "Windows", keys = "SUPER + mouse:272", dsp = function() return hl.dsp.window.drag() end,   opts = { mouse = true }, desc = "Drag window (LMB)" }
add { group = "Windows", keys = "SUPER + mouse:274", dsp = function() return hl.dsp.window.drag() end,   opts = { mouse = true }, desc = "Drag window (MMB)", hidden = true }
add { group = "Windows", keys = "SUPER + mouse:273", dsp = function() return hl.dsp.window.resize() end, opts = { mouse = true }, desc = "Resize window (RMB)" }

-- Workspaces -------------------------------------------------------------------
for i = 1, 10 do
    local key = tostring(i % 10)
    add { group = "Workspaces", hidden = true, keys = "SUPER + " .. key,
          dsp = function() return hl.dsp.focus({ workspace = i }) end, desc = "Workspace " .. i }
    add { group = "Workspaces", hidden = true, keys = "CTRL + SUPER + " .. key,
          dsp = function() return hl.dsp.focus({ workspace = i }) end, desc = "Workspace " .. i }
    add { group = "Workspaces", hidden = true, keys = "SUPER + ALT + " .. key,
          dsp = function() return hl.dsp.window.move({ workspace = i, follow = false }) end, desc = "Send window to workspace " .. i }
    add { group = "Workspaces", hidden = true, keys = "SUPER + SHIFT + " .. key,
          dsp = function() return hl.dsp.window.move({ workspace = i }) end, desc = "Move window + follow to workspace " .. i }
end
add { group = "Workspaces", doc = true, keys = "SUPER (+ CTRL) + 1…0",  desc = "Go to workspace 1–10" }
add { group = "Workspaces", doc = true, keys = "SUPER + ALT + 1…0",     desc = "Send window to workspace 1–10" }
add { group = "Workspaces", doc = true, keys = "SUPER + SHIFT + 1…0",   desc = "Move window to workspace 1–10 and follow" }
add { group = "Workspaces", keys = "CTRL + SUPER + left",  dsp = function() return hl.dsp.focus({ workspace = "r-1" }) end, desc = "Previous workspace" }
add { group = "Workspaces", keys = "CTRL + SUPER + right", dsp = function() return hl.dsp.focus({ workspace = "r+1" }) end, desc = "Next workspace" }
add { group = "Workspaces", keys = "SUPER + Page_Up",      dsp = function() return hl.dsp.focus({ workspace = "r-1" }) end, desc = "Previous workspace", hidden = true }
add { group = "Workspaces", keys = "SUPER + Page_Down",    dsp = function() return hl.dsp.focus({ workspace = "r+1" }) end, desc = "Next workspace", hidden = true }
add { group = "Workspaces", keys = "SUPER + SHIFT + Page_Up",   dsp = function() return hl.dsp.window.move({ workspace = "r-1" }) end, desc = "Move window to previous workspace" }
add { group = "Workspaces", keys = "SUPER + SHIFT + Page_Down", dsp = function() return hl.dsp.window.move({ workspace = "r+1" }) end, desc = "Move window to next workspace" }
add { group = "Workspaces", keys = "SUPER + mouse_down", dsp = function() return hl.dsp.focus({ workspace = "e+1" }) end, desc = "Next workspace (scroll)" }
add { group = "Workspaces", keys = "SUPER + mouse_up",   dsp = function() return hl.dsp.focus({ workspace = "e-1" }) end, desc = "Previous workspace (scroll)" }
add { group = "Workspaces", keys = "SUPER + S",        dsp = function() return hl.dsp.workspace.toggle_special("scratch") end, desc = "Toggle scratchpad" }
add { group = "Workspaces", keys = "CTRL + SUPER + S", dsp = function() return hl.dsp.workspace.toggle_special("scratch") end, desc = "Toggle scratchpad", hidden = true }
add { group = "Workspaces", keys = "SUPER + ALT + S",  dsp = function() return hl.dsp.window.move({ workspace = "special:scratch", follow = false }) end, desc = "Send window to scratchpad" }

-- Zoom (like end-4): magnifies around the cursor; repeats while held -----------
local function zoom(f)
    return function()
        local z = hl.get_config("cursor.zoom_factor") or 1
        z = math.max(1, math.min(8, z * f))
        if z < 1.05 then z = 1 end
        hl.config({ cursor = { zoom_factor = z } })
    end
end
add { group = "Utilities", keys = "SUPER + equal", dsp = function() return zoom(1.25) end, opts = { repeating = true }, desc = "Zoom in" }
add { group = "Utilities", keys = "SUPER + minus", dsp = function() return zoom(0.8) end,  opts = { repeating = true }, desc = "Zoom out (back to normal)" }

-- Session ----------------------------------------------------------------------
add { group = "Session", keys = "SUPER + L",          exec = apps.lock, desc = "Lock" }
add { group = "Session", keys = "SUPER + SHIFT + L",  exec = S .. "lock.sh; sleep 1; systemctl suspend", opts = { locked = true }, desc = "Standby (suspend)" }
add { group = "Session", keys = "CTRL + SHIFT + SUPER + R", dsp = function() return hl.dsp.reload_config() end, desc = "Reload Hyprland config" }

-- Media / hardware keys (work while locked) ------------------------------------
local L, LR = { locked = true }, { locked = true, repeating = true }
add { group = "Media", keys = "SUPER + P",         exec = "playerctl play-pause", opts = L, desc = "Play / pause" }
add { group = "Media", keys = "SUPER + N",         exec = "playerctl next",       opts = L, desc = "Next track" }
add { group = "Media", keys = "SUPER + SHIFT + N", exec = "playerctl previous",   opts = L, desc = "Previous track" }
add { group = "Media", keys = "CTRL + SUPER + V",  exec = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", opts = L, desc = "Mute / unmute output" }
add { group = "Media", keys = "SUPER + ALT + M",   exec = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", opts = L, desc = "Mute / unmute microphone" }
add { group = "Media", keys = "XF86AudioRaiseVolume", exec = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", opts = LR, desc = "Volume up" }
add { group = "Media", keys = "XF86AudioLowerVolume", exec = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",      opts = LR, desc = "Volume down" }
add { group = "Media", keys = "XF86AudioMute",        exec = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",     opts = L,  desc = "Mute output", hidden = true }
add { group = "Media", keys = "XF86AudioMicMute",     exec = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",   opts = L,  desc = "Mute microphone", hidden = true }
add { group = "Media", keys = "XF86AudioPlay",        exec = "playerctl play-pause", opts = L, desc = "Play / pause", hidden = true }
add { group = "Media", keys = "XF86AudioPause",       exec = "playerctl play-pause", opts = L, desc = "Play / pause", hidden = true }
add { group = "Media", keys = "XF86AudioNext",        exec = "playerctl next",       opts = L, desc = "Next track", hidden = true }
add { group = "Media", keys = "XF86AudioPrev",        exec = "playerctl previous",   opts = L, desc = "Previous track", hidden = true }
add { group = "Media", keys = "XF86MonBrightnessUp",   exec = "brightnessctl -q set 5%+", opts = LR, desc = "Brightness up" }
add { group = "Media", keys = "XF86MonBrightnessDown", exec = "brightnessctl -q set 5%-", opts = LR, desc = "Brightness down" }

return { apps = apps, binds = b }
