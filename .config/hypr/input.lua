-- SPDX-License-Identifier: GPL-3.0-or-later
-- Input and devices.

hl.config({
    input = {
        kb_layout    = "us",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = false,
            -- Right click by finger count, not by where you press: two fingers
            -- pressed anywhere = right, three = middle. libinput can't combine this
            -- with the bottom-corner areas; it's one or the other.
            clickfinger_behavior = true,
            -- Tapping works the same way: 1 finger left, 2 right, 3 middle.
            tap_to_click   = true,
            tap_button_map = "lrm",
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
