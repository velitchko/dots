// SPDX-License-Identifier: GPL-3.0-or-later
// Shared look: Kessel palette + JetBrainsMono Nerd Font (UI 10 / mono 11, see docs/THEME.md).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // Colours come from ~/.local/state/kessel/theme/colors.json, written by
    // ~/.config/hypr/scripts/theme.sh (dark = pitch black, light = eggshell,
    // accents from the wallpaper). Watched live; defaults = dark.
    property var c: ({})
    // Colour changes (light/dark, new wallpaper) glide instead of snapping.
    readonly property int themeMs: 550
    readonly property bool dark: (c.mode ?? "dark") !== "light"

    property color base:    c.bg ?? "#000000"
    Behavior on base { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color surface: c.surface ?? "#0b0b0b"
    Behavior on surface { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color overlay: c.overlay ?? "#262626"
    Behavior on overlay { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color muted:   c.muted ?? "#5a5a5a"
    Behavior on muted { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color text:    c.text ?? "#e8e8e8"
    Behavior on text { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color subtext: c.subtext ?? "#9a9a9a"
    Behavior on subtext { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color accent:  c.accent ?? "#8aadf4"
    Behavior on accent { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color accent2: c.accent2 ?? "#a6da95"
    Behavior on accent2 { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color accent3: c.accent3 ?? "#c6a0f6"
    Behavior on accent3 { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color green:   c.green ?? "#a6da95"
    Behavior on green { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color red:     c.red ?? "#e06c75"
    Behavior on red { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color yellow:  c.yellow ?? "#eed49f"
    Behavior on yellow { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }
    property color purple:  c.purple ?? "#c6a0f6"
    Behavior on purple { ColorAnimation { duration: root.themeMs; easing.type: Easing.InOutCubic } }

    // The island is the mode's base colour (pitch black / eggshell), opaque.
    readonly property color island:  base     // fully opaque: even 3% lets bright text behind ghost through
    readonly property color card:    a(text, dark ? 0.06 : 0.06)
    readonly property color cardHi:  a(text, dark ? 0.11 : 0.10)

    function reload() { colorsFile.reload() }

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/kessel/theme/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.c = JSON.parse(text()) } catch (e) { console.warn("theme: bad colors.json") } }
    }

    readonly property string font: "JetBrainsMono Nerd Font"
    // Icons: the "Propo" build gives each icon its real width. In the regular build
    // every icon has a 0.6em advance but many draw up to ~1em wide, spilling right,
    // so anything centred by its box sat up to 18% of the icon size off (Wi-Fi).
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"
    // Two small nudges (10/11/9.5/22 -> 10.5/11.5/10/23, islandHeight 36 -> 39)
    // weren't visible at all -- too small a step. This is the decisive version:
    // every value here times 1.25, the exact factor monitor scale dropped by
    // (1.25 -> 1, see monitors.lua) when switching to integer scale for
    // sharpness. Restores the pre-scale-change physical size exactly, rather
    // than guessing at another small increment.
    // 1.5pt down from the 1.25x pass above (12.5/13.75/11.9/27.5) -- island
    // size (pill height/padding/radius) stays as-is, just the text.
    readonly property real fontUi: 11
    readonly property real fontMono: 12.25
    readonly property real fontSmall: 10.4
    readonly property real fontBig: 26

    // The one border width used everywhere in the shell -- cards, buttons,
    // inputs, the island pill and its side pills, the music progress ring.
    // Matches Hyprland's actual window border (general.lua: border_size = 2)
    // so the island's chrome reads the same weight as real app windows.
    // Emphasis states (selected, alarm) double it rather than picking their
    // own number, so they stay a multiple of whatever this is.
    readonly property int borderWidth: 2
    readonly property int islandHeight: 45
    readonly property int screenCornerRadius: 14      // 0 disables the rounded screen corners
    // With exclusiveZone = islandHeight alone (Island.qml), the gap from the
    // island to a window is a fixed gaps_out + border = 12px, confirmed
    // empirically and unaffected by this value (Hyprland adds the layer's own
    // margin to exclusiveZone at the protocol level regardless of how the QML
    // arithmetic is split). Setting this to that same 12 makes the screen-top
    // gap match the island-to-window gap exactly, as asked.
    readonly property int islandMargin: 12
    readonly property int radius: 23
    readonly property int radiusPanel: 33
    readonly property int radiusCard: 18
    readonly property int pad: 18

    readonly property int animMs: 320

    // Physics-based morphing (Qt SpringAnimation). Slightly under-damped like
    // macOS/iOS: a hint of overshoot, then it settles. Velocity is preserved when
    // the target changes mid-flight, so interrupted morphs stay smooth.
    readonly property real springStiffness: 3.6     // higher = snappier
    readonly property real springDamping: 0.32      // lower = more bounce (0.2…0.5 sensible)
    readonly property real springMass: 1.0
    readonly property int fadeMs: 160

    function a(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha) }
}
