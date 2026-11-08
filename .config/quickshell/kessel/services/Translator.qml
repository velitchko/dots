// SPDX-License-Identifier: GPL-3.0-or-later
// Offline translation for the launcher (scripts/translate.sh → Bergamot).
//   ">de hello"        English → German         ">bg hello"  English → Bulgarian
//   ">en Здравей"      → English (Cyrillic = Bulgarian, otherwise German)
//   ">de-bg Hallo" / ">de>bg Hallo"   explicit pair (pivots through English)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/translate.sh"
    property string state: "unknown"           // ready / no-runtime / no-models
    property string query: ""
    property string result: ""
    property string from: ""
    property string to: ""
    property bool busy: false
    property string error: ""

    function parse(q) {
        const m = (q || "").match(/^>\s*([a-z]{2})(?:\s*[->]\s*([a-z]{2}))?\s+([\s\S]+)$/i)
        if (!m) return null
        let f, t
        if (m[2]) { f = m[1].toLowerCase(); t = m[2].toLowerCase() }
        else {
            t = m[1].toLowerCase()
            f = t !== "en" ? "en" : (/[Ѐ-ӿ]/.test(m[3]) ? "bg" : Config.translateFrom)
        }
        return { from: f, to: t, text: m[3].trim() }
    }
    function looksLikeTranslate(q) { return /^>\s*[a-z]{2}/i.test(q || "") }

    function request(q) {
        query = q
        const p = parse(q)
        if (!p) { result = ""; error = ""; return }
        from = p.from; to = p.to
        debounce.restart()
    }
    Timer {
        id: debounce
        interval: 550
        onTriggered: root.start()
    }
    // Typing while a translation runs used to drop the new request: setting
    // running = true on a process that is still running does nothing. Now the
    // old one is stopped, its output ignored, and the latest query runs next.
    property bool rerun: false
    function start() {
        const p = parse(query)
        if (!p) return
        busy = true; error = ""
        if (proc.running) { rerun = true; proc.signal(15); return }
        proc.command = ["sh", "-c", 'printf "%s" "$3" | "$0" run "$1" "$2"', script, p.from, p.to, p.text]
        proc.running = true
    }
    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: if (!root.rerun) root.result = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (!root.rerun && text.trim() !== "") root.error = text.trim().split("\n").pop().replace(/^translate: /, "") }
        onExited: {
            if (root.rerun) { root.rerun = false; root.start() }
            else root.busy = false
        }
    }

    function refresh() { if (!probe.running) probe.running = true }
    Process {
        id: probe
        running: true
        command: [root.script, "status"]
        stdout: StdioCollector { onStreamFinished: root.state = text.trim() || "no-runtime" }
    }
    function copy() { if (result !== "") Quickshell.execDetached(["wl-copy", "--", result]) }
}
