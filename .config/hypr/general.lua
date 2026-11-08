-- SPDX-License-Identifier: GPL-3.0-or-later
-- UI / general aesthetic. Border colours come from the current theme
-- (~/.local/state/kessel/theme/hyprland.lua, written by scripts/theme.sh).

local theme = { active = { "rgba(8aadf4ee)", "rgba(c6a0f6ee)" }, inactive = "rgba(262626aa)" }
do
    local path = os.getenv("HOME") .. "/.local/state/kessel/theme/hyprland.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, t = pcall(dofile, path)
        if ok and type(t) == "table" then theme = t end
    end
end

-- Without a GPU render node (e.g. most VMs) everything is drawn in
-- software: skip blur and use cheap shadows there. Real hardware keeps the full look.
local function has_render_node()
    for i = 128, 135 do
        local f = io.open("/dev/dri/renderD" .. i, "r")
        if f then f:close(); return true end
    end
    return false
end
local SOFTWARE = not has_render_node()

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = theme.active, angle = 45 },
            inactive_border = theme.inactive,
        },
        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,
        -- Focused windows keep their own look (kitty is slightly translucent by
        -- itself); unfocused ones fade a little so the frosted blur shows through.
        active_opacity   = 1.0,
        inactive_opacity = 0.90,
        shadow = {
            enabled      = not SOFTWARE,
            range        = 8,
            render_power = 3,
            color        = 0x99000000,
        },
        -- Frosted glass behind every translucent window, popup and layer. Off in
        -- software rendering (no GPU), where it costs a whole CPU core.
        blur = {
            enabled           = not SOFTWARE,
            size              = 7,
            passes            = 3,      -- smooth, no visible boxes
            noise             = 0.02,   -- a little grain reads as "frosted", hides banding
            contrast          = 0.95,
            brightness        = 0.85,   -- keep text on top readable
            vibrancy          = 0.20,
            vibrancy_darkness = 0.25,
            new_optimizations = true,
            xray              = false,  -- blur the real windows behind, not only the wallpaper
            popups            = true,   -- menus and tooltips too
            special           = true,   -- scratchpad
        },
    },

    animations = { enabled = true },

    dwindle   = { preserve_split = true },
    master    = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },

    misc = {
        force_default_wallpaper = 0,     -- awww (or hyprpaper) draws the wallpaper
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        allow_session_lock_restore = true, -- a new locker (hyprlock) may take over a crashed one
        -- Fullscreen must not change the display's mode: on many laptop panels a
        -- mode change is a ~1 s black screen. VRR "only for fullscreen" (2) and
        -- auto-HDR switch modes the moment a window goes fullscreen.
        vrr = 0,
    },

    render = {
        direct_scanout    = 0,      -- handing a fullscreen window straight to the display can re-program it (black flash)
        cm_auto_hdr       = 0,      -- no automatic HDR switch for fullscreen apps
        send_content_type = false,  -- some panels blank while switching to "game"/"video" picture modes
    },

    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },
})

-- Animations: short, calm, no bounce.
hl.curve("easeOutQuint",  { type = "bezier", points = { { 0.23, 1 },   { 0.32, 1 } } })
hl.curve("linear",        { type = "bezier", points = { { 0, 0 },      { 1, 1 } } })
hl.curve("almostLinear",  { type = "bezier", points = { { 0.5, 0.5 },  { 0.75, 1 } } })
hl.curve("quick",         { type = "bezier", points = { { 0.15, 0 },   { 0.1, 1 } } })
hl.curve("calm",          { type = "spring", mass = 1, stiffness = 238.1191, damping = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "calm" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "calm",  style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear", style = "popin 90%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
-- Workspaces slide sideways (direction follows the workspace number); the
-- scratchpad (special workspace) slides in vertically so it reads as an overlay.
hl.animation({ leaf = "workspaces",       enabled = true, speed = 3.5,  bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.5,  bezier = "easeOutQuint", style = "slidevert" })
