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
hl.window_rule({
    name  = "ai-chat-float",
    match = { title = "^Kessel AI Chat$" },
    float = true, center = true,
})
