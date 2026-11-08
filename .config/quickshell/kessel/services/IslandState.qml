// SPDX-License-Identifier: GPL-3.0-or-later
// Island arbitration + IPC. The island shows the highest layer that wants it:
//
//   panel         opened by the user (launcher, clipboard, control, power, timer)
//   notification  something arrived              until it expires / is closed
//   osd           volume changed                 briefly
//   summary       pointer resting on the island  until it leaves
//   rest          clock, workspaces and live activities
//
// IPC (used by Hyprland binds via scripts/island-or.sh):
//   qs -c kessel ipc call island open <launcher|clipboard|control|power|timer>
//   qs -c kessel ipc call island close | toggle | show | hide | dnd | record | status
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Singleton {
    id: root

    property bool shown: true
    property string panel: ""
    property bool hovered: false
    property bool summary: false
    property string launcherText: ""   // prefill for the launcher (IPC 'search')
    property bool quitting: false    // graceful shutdown in progress (see shell.qml)
    property real restWidth: 0       // reported by RestView (for status / tests)
    property real pillWidth: 0       // live, animated width of the pill (tests)

    property bool osdActive: false
    property string osdIcon: ""
    property string osdLabel: ""
    property real osdValue: 0

    readonly property var panels: ["launcher", "clipboard", "control", "notifications", "notes", "overview", "power", "timer", "wallpaper", "board", "media", "mixer", "shortcuts"]

    readonly property string layer: Polkit.active ? "polkit"
        : Alarm.ringing ? "alarm"
        : panel !== "" ? "panel"
        : Notifs.popup !== null ? "notification"
        : osdActive ? "osd"
        : summary ? "summary"
        : "rest"

    // Panels opened from inside another panel remember where they came from,
    // so back() (← button, Alt+Left, mouse back button) returns there.
    property var history: []
    readonly property bool canGoBack: panel !== "" && history.length > 0

    function openPanel(name) {
        if (panels.indexOf(name) < 0) return false
        shown = true
        if (panel === name) { closePanel(); return true }
        if (panel !== "") history = history.concat([panel])
        panel = name
        return true
    }
    function closePanel() { history = []; panel = "" }
    function back() {
        if (history.length === 0) { closePanel(); return }
        const prev = history[history.length - 1]
        history = history.slice(0, -1)
        panel = prev
    }

    // Scrolling the island rotates perspectives. It also hides the hover glance
    // until the pointer leaves, so you can see what you scrolled to.
    // Theme crossfade: theme.sh calls freeze() before switching and thaw() after.
    // While frozen, ThemeFade shows a still snapshot of each screen over everything;
    // thaw() fades it out, so every app appears to glide to the new colours.
    property bool frozen: false
    property bool thawing: false
    function freeze() { thawing = false; frozen = true; freezeGuard.restart() }
    function thaw() { if (frozen) thawing = true }
    function fadeDone() { frozen = false; thawing = false }
    Timer { id: freezeGuard; interval: 6000; onTriggered: root.thaw() }   // never stay frozen

    property bool glanceSuppressed: false
    // True while the pointer is over something clickable in the resting view
    // (workspace dots): the glance must not replace it under the cursor.
    property bool holdRest: false
    onHoldRestChanged: {
        if (holdRest) { hoverTimer.stop(); summary = false }
        else if (hovered) hoverTimer.restart()
    }
    function scrollPerspective(step) {
        Perspectives.rotate(step)
        glanceSuppressed = true
        hoverTimer.stop()
        summary = false
    }

    function showOsd(icon, label, value) {
        osdIcon = icon; osdLabel = label; osdValue = value
        osdActive = true
        osdTimer.restart()
    }

    Timer { id: osdTimer; interval: Config.osdMs; onTriggered: root.osdActive = false }
    // Hysteresis: open after the pointer rests, close only after it has been
    // gone for a moment (the pill changes size under the cursor while morphing).
    Timer { id: hoverTimer; interval: Config.hoverDelayMs; onTriggered: root.summary = root.hovered && !root.glanceSuppressed && !root.holdRest }
    Timer { id: leaveTimer; interval: 350; onTriggered: if (!root.hovered) root.summary = false }
    onHoveredChanged: {
        if (!hovered) glanceSuppressed = false
        if (hovered) { leaveTimer.stop(); hoverTimer.restart() }
        else { hoverTimer.stop(); leaveTimer.restart() }
    }

    IpcHandler {
        target: "island"

        function open(name: string): string {
            if (!root.shown) return "hidden"
            return root.openPanel(name) ? "ok" : "unknown panel"
        }
        function close(): string { root.closePanel(); return "ok" }
        function workspace(id: int): string { Hypr.focus(id); return "ok" }
        function freeze(): string { root.freeze(); return "ok" }
        function thaw(): string { root.thaw(); return "ok" }
        function back(): string { root.back(); return root.panel === "" ? "closed" : root.panel }
        function toggle(): string { root.shown = !root.shown; if (!root.shown) root.closePanel(); return root.shown ? "shown" : "hidden" }
        function show(): string { root.shown = true; return "ok" }
        function hide(): string { root.shown = false; root.closePanel(); return "ok" }
        function dnd(): string { Notifs.dnd = !Notifs.dnd; return Notifs.dnd ? "dnd on" : "dnd off" }
        function record(): string { Recorder.toggle(false); return "ok" }
        function recordRegion(): string { Recorder.toggle(true); return "ok" }
        function layoutMode(mode: string): string {
            Session.floatMode = mode === "floating"
            root.showOsd(Session.floatMode ? Icons.floating : Icons.tiling, Session.floatMode ? "Floating" : "Tiling", 1)
            return "ok"
        }
        // Show/hide the hover glance without a pointer (also handy for testing).
        // Rotate perspectives without a scroll wheel: step = 1 / -1
        // open the launcher pre-filled, e.g.  search ">de good morning"
        function search(text: string): string { root.launcherText = text; root.panel = ""; root.openPanel("launcher"); return "ok" }
        function perspectiveSet(name: string): string { Perspectives.set(name); return Perspectives.current }
        function perspective(step: int): string { Perspectives.rotate(step); return Perspectives.current }
        function perspectiveNext(): string { Perspectives.rotate(1); return Perspectives.current }
        function perspectivePrev(): string { Perspectives.rotate(-1); return Perspectives.current }
        function pill(): string { return String(Math.round(root.pillWidth * 10) / 10) }
        // Graceful exit: drop keyboard focus from every text field first —
        // Qt 6.12 crashes tearing down a focused text input (QInputMethod::commit).
        function quit(): string { root.panel = ""; root.quitting = true; return "ok" }
        function updatesCheck(): string { Updates.check(); return "ok" }
        function polkitStatus(): string { return Polkit.registered ? "registered" : "not-registered" }
        function polkitCancel(): string { Polkit.cancel(); return "ok" }
        function timer(seconds: int): string { Timers.startSeconds(seconds); return "ok" }
        function dismissAlarm(): string { Alarm.dismiss(); return "ok" }
        function glance(on: bool): string { root.summary = on; return "ok" }
        function stayAwake(on: bool): string { Session.inhibitIdle = on; return "ok" }
        function reloadTheme(): string { Theme.reload(); return "ok" }
        function toggleTheme(): string { Themes.toggleMode(); return "ok" }
        function status(): string {
            return JSON.stringify({
                shown: root.shown, layer: root.layer, panel: root.panel, restWidth: root.restWidth, perspective: Perspectives.current, hyprLua: Hyprland.usingLua,
                dnd: Notifs.dnd, notifications: Notifs.count, updates: Updates.count, polkit: Polkit.registered,
                media: Media.active ? Media.title : null,
                recording: Recorder.recording, weather: Weather.ok ? Weather.temp : null
            })
        }
    }
}
