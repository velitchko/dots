-- SPDX-License-Identifier: GPL-3.0-or-later
-- Displays. Arranged left→right automatically, re-applied on hot-plug:
--
--   1 display   it is the origin
--   2 displays  [external] [laptop]          external always to the LEFT
--   3 displays  [left]   [MAIN]   [right]    the main display in the MIDDLE
--               (laptop, if present, goes left; MAIN_MONITOR picks the middle one,
--                otherwise the first external is used)
--
-- Find a display's description with:  hyprctl monitors | grep description

local MAIN_MONITOR = ""      -- e.g. "Dell Inc. DELL U2723QE" (substring match)

-- Per-output mode overrides (output name → mode). Everything not listed uses its
-- preferred mode. Virtual displays often default to an odd mode, so pin one here.
local MODES = { ["Virtual-1"] = "1920x1080" }
-- Per-output scale overrides. "auto" (DPI-based) rounded eDP-1 up to 1.5.
-- Tried 1.25 first, but any fractional scale renders visibly soft here
-- (confirmed A/B, live) even with QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough
-- set (env.lua) -- this Qt6/Quickshell stack doesn't cleanly support
-- fractional buffer scaling. Pinned to the nearest integer instead; size is
-- tuned via font points (see docs/THEME.md), not surface scale.
local SCALES = { ["eDP-1"] = "1" }
for name, mode in pairs(MODES) do
    hl.monitor({ output = name, mode = mode, position = "0x0", scale = SCALES[name] or "auto" })
end
for name, scale in pairs(SCALES) do
    if not MODES[name] then
        hl.monitor({ output = name, mode = "preferred", position = "auto-right", scale = scale })
    end
end
-- Everything else: preferred mode, auto scale; position set by arrange() below.
hl.monitor({ output = "", mode = "preferred", position = "auto-right", scale = "auto" })

local function is_internal(m)
    local n = m.name or ""
    return n:match("^eDP") or n:match("^LVDS") or n:match("^DSI") or n:match("^Virtual")
end

local function logical_width(m)
    local w, h, s = m.width or 0, m.height or 0, (m.scale and m.scale > 0) and m.scale or 1
    if m.transform == 1 or m.transform == 3 or m.transform == 5 or m.transform == 7 then w = h end
    return math.floor(w / s + 0.5)
end

-- hyprmoncfg (optional, AUR: hyprmoncfg-bin) arranges displays from saved
-- profiles. Once it has written its file, it owns the layout: arrange() steps
-- aside so the two don't fight on every hot-plug (the defaults above still
-- give new displays a mode and scale).
local HYPRMONCFG = (function()
    local f = io.open(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua", "r")
    if f then f:close(); return true end
    return false
end)()

local function arrange()
    if HYPRMONCFG then return end
    local ok, mons = pcall(hl.get_monitors)
    if not ok or type(mons) ~= "table" then return end

    local internal, externals = nil, {}
    for _, m in ipairs(mons) do
        if m.enabled ~= false and not m.is_mirror then
            if is_internal(m) and not internal then internal = m else table.insert(externals, m) end
        end
    end
    table.sort(externals, function(a, b) return (a.name or "") < (b.name or "") end)
    if #externals == 0 then return end   -- single display: rules above are enough

    local order
    if internal and #externals == 1 then
        order = { externals[1], internal }
    else
        local main = externals[1]
        if MAIN_MONITOR ~= "" then
            for _, m in ipairs(externals) do
                if (m.description or ""):find(MAIN_MONITOR, 1, true) then main = m end
            end
        end
        local rest = {}
        for _, m in ipairs(externals) do if m ~= main then table.insert(rest, m) end end
        local left = internal or table.remove(rest, 1)
        order = { left, main }
        for _, m in ipairs(rest) do table.insert(order, m) end
    end

    local x = 0
    for _, m in ipairs(order) do
        hl.monitor({ output = m.name, mode = MODES[m.name] or "preferred", position = x .. "x0", scale = SCALES[m.name] or "auto" })
        x = x + logical_width(m)
    end
end

arrange()
hl.on("monitor.added", function()
    arrange()
    -- the new display's auto scale is known only after it is configured; settle once more
    hl.timer(arrange, { timeout = 600, type = "oneshot" })
end)
hl.on("monitor.removed", arrange)
