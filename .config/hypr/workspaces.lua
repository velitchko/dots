-- SPDX-License-Identifier: GPL-3.0-or-later
-- Workspace, window and layer rules.

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Small utility windows float.
for _, class in ipairs({
    "^(org.pulseaudio.pavucontrol|pavucontrol)$",
    "^(polkit-gnome-authentication-agent-1)$",
    "^(xdg-desktop-portal-gtk)$",
}) do
    hl.window_rule({ name = "float-" .. class, match = { class = class }, float = true, center = true })
end

-- OmniGlyph picker: floating overlay.
hl.window_rule({
    name  = "omniglyph-float",
    match = { class = "(?i).*omniglyph.*" },
    float = true, center = true, pin = true,
    opacity = "1.0 override 1.0 override",   -- fully opaque, even when unfocused
})

-- Blur behind fuzzel. Not behind the island: it is fully opaque, and blurring its
-- (mostly transparent) surface only smeared a gradient around open panels.
hl.layer_rule({ name = "blur-fuzzel", match = { namespace = "^launcher$" }, blur = true, ignore_alpha = 0.3 })

-- AI chat window: floats and centers instead of tiling, like the other
-- utility windows above. Matched by title, not class -- Quickshell windows
-- from the same process don't reliably get distinct app_ids.
--
-- Earlier this drew its own corners/border in QML and set rounding/
-- border_size to 0 here to stop them doubling with Hyprland's own
-- general.rounding/border_size -- but border_size = 0 also removes the
-- hitbox resize_on_border (general.lua) needs to detect "near the edge",
-- so the window stopped being drag-resizable, and a borderless frameless
-- window with only a faint inner QML line just reads as a flat square.
-- Reverted: Hyprland draws its normal accent border/rounding like any
-- other floating window (AiChatWindow.qml's own radius now matches
-- general.rounding exactly instead of fighting it, and no longer draws
-- a competing border at all).
hl.window_rule({
    name  = "ai-chat-float",
    match = { title = "^Kessel AI Chat$" },
    float = true, center = true,
})

-- Launcher opened while the island is in focus mode (DetachedLauncher.qml):
-- same floating treatment as the AI chat window, so it lands on whichever
-- monitor is focused without per-screen layer-shell wiring.
hl.window_rule({
    name  = "detached-launcher-float",
    match = { title = "^Kessel Launcher$" },
    float = true, center = true,
})
