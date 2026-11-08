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

-- The built-in "workspace" action swipes between already-existing workspaces
-- only, confirmed via hyprctl: dispatching workspace="r+1" directly DOES
-- create new ones fine (same as SUPER+Page_Down below), but this preset
-- doesn't. Tried routing it through a custom function action twice (see git
-- log) -- both passed --verify-config but didn't actually fire on a real
-- swipe, and there's no way to test the gesture callback signature here
-- without real touchpad hardware. Reverted to the built-in preset: existing-
-- workspaces-only, but at least it works.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
