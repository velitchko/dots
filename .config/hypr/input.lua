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
-- only — confirmed it won't create a new one past the last, even though
-- gestures.workspace_swipe_create_new is on (hl.dsp.focus with "r+1"/"r-1"
-- does create new ones fine, same as SUPER+Page_Down/Up below). Two directional
-- gestures routed through that same relative dispatch instead.
hl.gesture({ fingers = 3, direction = "left",  action = function() return hl.dsp.focus({ workspace = "r+1" }) end })
hl.gesture({ fingers = 3, direction = "right", action = function() return hl.dsp.focus({ workspace = "r-1" }) end })
