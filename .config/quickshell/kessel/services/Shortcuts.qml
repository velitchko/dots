// SPDX-License-Identifier: GPL-3.0-or-later
// Keybinds for the Shortcuts panel (SUPER+/). Hyprland's lib/binder.lua writes
// them to $XDG_RUNTIME_DIR/kessel-shortcuts.json on every config load, straight
// from keybinds.lua (the single source of truth).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property var entries: []          // [{ group, keys, desc }]

    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/kessel-shortcuts.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.entries = JSON.parse(text()) } catch (e) {} }
    }

    // Key name → keycap content: an icon (g) or a short label (t). Codepoints were
    // checked by name against Nerd Fonts' glyphnames.json.
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property var caps: ({
        "SUPER":   { g: g(0xF303) },              // linux-archlinux
        "SHIFT":   { g: g(0xF0636) },             // md-apple_keyboard_shift
        "CTRL":    { g: g(0xF0634) },             // md-apple_keyboard_control
        "ALT":     { g: g(0xF0635) },             // md-apple_keyboard_option
        "Return":  { g: g(0xF0311) },             // md-keyboard_return
        "Tab":     { g: g(0xF0312) },             // md-keyboard_tab
        "Space":   { g: g(0xF1050) },             // md-keyboard_space
        "Escape":  { g: g(0xF12B7) },             // md-keyboard_esc
        "Print":   { g: g(0xF0E51) },             // md-monitor_screenshot
        "mouse:272": { g: g(0xF037D), t: "L" },   // md-mouse
        "mouse:273": { g: g(0xF037D), t: "R" },
        "mouse:274": { g: g(0xF037D), t: "M" },
        "mouse_down": { g: g(0xF1550) },          // md-mouse_move_down
        "mouse_up":   { g: g(0xF1551) },          // md-mouse_move_up
        "XF86AudioRaiseVolume":  { g: g(0xF057E) },
        "XF86AudioLowerVolume":  { g: g(0xF057F) },
        "XF86AudioMute":         { g: g(0xF075F) },
        "XF86AudioMicMute":      { g: g(0xF036D) },
        "XF86AudioPlay":         { g: g(0xF040E) },
        "XF86AudioPause":        { g: g(0xF040E) },
        "XF86AudioNext":         { g: g(0xF04AD) },
        "XF86AudioPrev":         { g: g(0xF04AE) },
        "XF86MonBrightnessUp":   { g: g(0xF00E0) },
        "XF86MonBrightnessDown": { g: g(0xF00DE) },
        "slash": { t: "/" }, "period": { t: "." }, "equal": { t: "=" }, "minus": { t: "−" },
        "semicolon": { t: ";" }, "apostrophe": { t: "'" },
        "left": { t: "←" }, "right": { t: "→" },
        "Page_Up": { t: "PgUp" }, "Page_Down": { t: "PgDn" }, "Delete": { t: "Del" }
    })

    // "SUPER + SHIFT + Return" → [{ g?, t?, optional }]
    function keycaps(keys) {
        if (keys === "SUPER + SUPER_L") return [{ t: "tap" }, caps["SUPER"]]
        return keys.replace(" (+ CTRL)", " + (CTRL)").split(" + ").map(k => {
            const opt = /^\(.*\)$/.test(k)
            const name = opt ? k.slice(1, -1) : k
            const c = caps[name] ?? { t: name }
            return { g: c.g, t: c.t, optional: opt }
        })
    }
    function matches(e, q) {
        q = q.toLowerCase()
        return q === "" || e.desc.toLowerCase().includes(q) || e.group.toLowerCase().includes(q) || e.keys.toLowerCase().includes(q)
    }
}
