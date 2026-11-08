// SPDX-License-Identifier: GPL-3.0-or-later
// Hyprland state for the island (workspaces), via Quickshell's Hyprland IPC.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property int focusedId: Hyprland.focusedWorkspace?.id ?? 1
    // Workspaces the island shows (dots, SUPER+Tab grid): at least 5, growing with
    // the highest one in use. Keys reach 1–10; CTRL+SUPER+→ goes beyond, so the
    // cap is 20 (the overview grid then just gets more rows).
    readonly property int maxId: {
        let m = 5
        for (let i = 0; i < workspaces.length; i++) m = Math.max(m, workspaces[i].id)
        return Math.min(m, 20)
    }
    function occupied(id) {
        for (let i = 0; i < workspaces.length; i++)
            if (workspaces[i].id === id) return (workspaces[i].toplevels?.values?.length ?? 1) > 0
        return false
    }
    readonly property var toplevels: Hyprland.toplevels.values
    function windowsOn(id) { return toplevels.filter(t => t.workspace?.id === id) }
    function addr(t) { const a = String(t.address); return a.startsWith("0x") ? a : "0x" + a }
    function focusWindow(t) {
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ window = "address:${addr(t)}" })` : `focuswindow address:${addr(t)}`)
    }
    function moveWindowTo(t, id) {
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.window.move({ workspace = ${id}, window = "address:${addr(t)}" })` : `movetoworkspacesilent ${id},address:${addr(t)}`)
    }
    // Best-effort: focus a window belonging to an app (by desktop entry / app name).
    function focusApp(names) {
        const want = names.filter(n => n).map(n => n.toLowerCase())
        const t = toplevels.find(t => {
            const c = (t.lastIpcObject?.class || "").toLowerCase()
            return c !== "" && want.some(w => c === w || c.endsWith("." + w) || w.endsWith("." + c) || c.indexOf(w) >= 0)
        })
        if (t) focusWindow(t)
        return t !== undefined
    }
    // From inside an open panel: close it first, then act. While the panel's
    // focus grab is active Hyprland drops the workspace switch, so wait until
    // the grab has been released.
    property var pending: null
    function afterPanel(fn) { pending = fn; IslandState.closePanel(); pendingTimer.restart() }
    Timer { id: pendingTimer; interval: 120; onTriggered: { const f = root.pending; root.pending = null; if (f) f() } }

    function focus(id) {
        // Hyprland 0.57 uses Lua dispatchers.
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = ${id} })` : `workspace ${id}`)
    }
}
