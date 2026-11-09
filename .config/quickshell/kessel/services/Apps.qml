// SPDX-License-Identifier: GPL-3.0-or-later
// Desktop applications: fuzzy search ranked by match quality and launch frequency.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property var all: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .slice().sort((a, b) => a.name.localeCompare(b.name))

    property var usage: ({})

    FileView {
        id: store
        path: Quickshell.statePath("app-usage.json")
        onLoaded: { try { root.usage = JSON.parse(text()) } catch (e) { root.usage = {} } }
        onLoadFailed: root.usage = {}
    }

    function score(a, q) {
        if (q === "") return 1
        const name = a.name.toLowerCase()
        if (name.startsWith(q)) return 100
        if (name.indexOf(q) >= 0) return 60
        const hay = [a.genericName, a.comment, (a.keywords || []).join(" "), a.id].join(" ").toLowerCase()
        if (hay.indexOf(q) >= 0) return 30
        // subsequence match on the name
        let i = 0
        for (const ch of name) if (ch === q[i]) i++
        return i === q.length ? 10 : 0
    }

    function query(q) {
        q = (q || "").trim().toLowerCase()
        return all.map(a => ({ app: a, s: score(a, q) }))
            .filter(x => x.s > 0)
            .sort((x, y) => ((y.s + Math.min(20, (root.usage[y.app.id] || 0))) - (x.s + Math.min(20, (root.usage[x.app.id] || 0)))) || x.app.name.localeCompare(y.app.name))
            .map(x => x.app)
    }

    // Best-effort: find a desktop entry for an app (by desktop entry id / icon /
    // app name), for a "focus failed, launch it instead" fallback. Same
    // normalized-substring matching as Hypr.focusApp.
    function findByNames(names) {
        const want = names.filter(n => n).map(Hypr.normalize).filter(n => n !== "")
        if (want.length === 0) return undefined
        return all.find(a => {
            const id = Hypr.normalize(a.id), name = Hypr.normalize(a.name)
            return want.some(w => id === w || id.indexOf(w) >= 0 || w.indexOf(id) >= 0 ||
                                   name === w || name.indexOf(w) >= 0 || w.indexOf(name) >= 0)
        })
    }

    function launch(a) {
        const u = Object.assign({}, usage)
        u[a.id] = (u[a.id] || 0) + 1
        usage = u
        store.setText(JSON.stringify(u))
        a.execute()
    }
}
