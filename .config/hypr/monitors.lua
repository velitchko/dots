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

-- Workspaces 1-10, assigned to specific monitors by position (not name), so
-- SUPER+Tab and the scratch workspace (special:scratch) land on the monitor
-- you'd expect instead of whichever one last had focus:
--   1 monitor   1-10 on it
--   2 monitors  1-5 on the leftmost, 6-10 on the rightmost (arrange() above
--               always puts the external display left of the laptop, so in
--               practice this is "external" / "laptop")
--   3 monitors  1-3 on the middle, 4-6 on the left, 7-9 on the right
--               (workspace 10 is left with Hyprland's default dynamic
--               behavior, same as the original ask -- it only covers 1-9)
-- Reads live positions via hl.get_monitors() rather than arrange()'s own
-- `order`, so it still works under hyprmoncfg (which arrange() steps aside
-- for, but which has nothing to do with workspace assignment).
-- Known gap: going from 3 monitors straight to 2 re-binds 1-10 and
-- overwrites everything, but going from 2 to 3 only re-declares 1-9 --
-- workspace 10 keeps whatever monitor the 2-monitor scheme last gave it
-- instead of reverting to unbound. Not fixed: this user's machines are
-- either a laptop (1-2 monitors) or a desktop (always 3), never both, so
-- the 2-to-3 transition doesn't actually happen in practice.
local function bind_workspaces()
    local ok, mons = pcall(hl.get_monitors)
    if not ok or type(mons) ~= "table" then return end

    local live = {}
    for _, m in ipairs(mons) do
        if m.enabled ~= false and not m.is_mirror then table.insert(live, m) end
    end
    table.sort(live, function(a, b) return (a.x or 0) < (b.x or 0) end)

    local ranges
    if #live == 1 then
        ranges = { { 1, 10, live[1] } }
    elseif #live == 2 then
        ranges = { { 1, 5, live[1] }, { 6, 10, live[2] } }
    elseif #live == 3 then
        ranges = { { 1, 3, live[2] }, { 4, 6, live[1] }, { 7, 9, live[3] } }
    else
        return   -- not a layout this binds; workspaces keep the default dynamic behavior
    end

    for _, r in ipairs(ranges) do
        local lo, hi, mon = r[1], r[2], r[3]
        for ws = lo, hi do
            hl.workspace_rule({ workspace = tostring(ws), monitor = mon.name })
        end
    end
end

arrange()
bind_workspaces()
hl.on("monitor.added", function()
    arrange()
    bind_workspaces()
    -- the new display's auto scale is known only after it is configured; settle once more
    hl.timer(function() arrange(); bind_workspaces() end, { timeout = 600, type = "oneshot" })
end)
hl.on("monitor.removed", function()
    arrange()
    bind_workspaces()
end)
