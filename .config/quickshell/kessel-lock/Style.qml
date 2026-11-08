// SPDX-License-Identifier: GPL-3.0-or-later
// Lock-screen look. Accent follows the desktop theme (colors.json); the rest is
// fixed white-on-dark so it stays legible over any wallpaper.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var c: ({})
    // Theme-aware: dark = pitch black, light = eggshell (colors.json from theme.sh).
    readonly property bool dark: (c.mode ?? "dark") !== "light"
    readonly property color base: c.bg ?? (dark ? "#000000" : "#f0ead6")
    readonly property color text: c.text ?? (dark ? "#e8e8e8" : "#1d1b16")
    readonly property color accent: c.accent ?? "#8aadf4"
    readonly property color red: c.red ?? "#e06c75"
    readonly property color subtext: a(text, 0.68)
    readonly property color faint: a(text, 0.45)
    readonly property color overlay: a(base, dark ? 0.62 : 0.58)   // over the blurred wallpaper
    readonly property color card: a(base, dark ? 0.45 : 0.55)
    readonly property color cardBorder: a(text, 0.07)
    readonly property color toolbar: a(base, dark ? 0.82 : 0.86)
    readonly property color toolbarHi: a(text, 0.10)
    readonly property color pill: a(text, 0.08)
    readonly property color onAccent: dark ? "#000000" : "#ffffff"
    function a(col, alpha) { return Qt.rgba(col.r, col.g, col.b, alpha) }
    readonly property string wallpaper: c.wallpaper ?? "/usr/share/hypr/wall2.png"
    // small copy made by theme.sh (shown blurred anyway, decodes instantly)
    readonly property string lockWallpaper: c.lockWallpaper ?? wallpaper
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"   // icons centred by their real width (see kessel/Theme.qml)

    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string iLock:     g(0xF033E)
    readonly property string iKeyboard: g(0xF030C)
    readonly property string iArrow:    g(0xF0054)
    readonly property string iCoffee:   g(0xF0176)
    readonly property string iPower:    g(0xF0425)
    readonly property string iReboot:   g(0xF0709)
    readonly property string iSleep:    g(0xF0594)
    readonly property string iBolt:     g(0xF140B)
    readonly property string iBattery:  g(0xF0079)
    readonly property string iAccount:  g(0xF0009)

    // Read synchronously: the lock's first frame needs the colours and the small
    // lock wallpaper. Loaded asynchronously, `c` was still empty when the lock was
    // built, so it decoded the 8K fallback wallpaper first (~0.65 s before the
    // lock could appear).
    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/kessel/theme/colors.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { root.c = JSON.parse(text()) } catch (e) {} }
    }
    Component.onCompleted: { try { root.c = JSON.parse(colorsFile.text()) } catch (e) {} }
}
