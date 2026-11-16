// SPDX-License-Identifier: GPL-3.0-or-later
// Top-5 processes by CPU and by memory, via `ps`. Polls only while `wanted`
// is true -- confirmed live, ~20ms per call, cheap enough for a 3s interval.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property bool wanted: false
    property var topCpu: []
    property var topMem: []

    // `ps`'s own %cpu is itself ~ (its own brief lifetime's CPU time) / (its own
    // brief lifetime) -- close to 100%, an artifact of this command measuring
    // itself, not a real hog. Filtered out so it doesn't crowd out real entries.
    // Note: %cpu/%mem here are still lifetime averages (ps's own definition),
    // not instantaneous -- same characteristic `ps --sort=-%cpu`/`top`'s default
    // view has always had. A real delta-sampled "right now" metric was
    // investigated and set aside: it needs either a longer-lived sampling
    // process or more robust /proc-read error handling than three attempts
    // produced a verified-correct version of, for what is a cosmetic feature.
    // Columns are fixed-width (pct:6, comm:16, then args) because comm can
    // contain spaces ("Web Content"). comm is what we show, except for Wine/
    // Proton programs: Wine renames their main thread to "Main", so a game
    // would read as "Main" -- for those the .exe name from args is used.
    function parse(text) {
        const out = []
        for (const line of text.split("\n")) {
            if (line.length < 8) continue
            const pct = parseFloat(line.slice(0, 6))
            let name = line.slice(7, 23).trim()
            const args = line.slice(24)
            if (!isFinite(pct) || name === "ps") continue
            const exe = args.match(/^"?(?:[A-Za-z]:\\|\/)[^"]*?([^\\\/"]+)\.exe\b/i)
            if (exe) name = exe[1]
            out.push({ name, pct })
            if (out.length >= 5) break
        }
        return out
    }
    function refresh() { cpuProc.running = true; memProc.running = true }
    Timer { interval: 3000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: cpuProc
        command: ["ps", "-e", "-o", "%cpu:6=,comm:16=,args=", "--sort=-%cpu", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topCpu = root.parse(text) }
    }
    Process {
        id: memProc
        command: ["ps", "-e", "-o", "%mem:6=,comm:16=,args=", "--sort=-%mem", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topMem = root.parse(text) }
    }
}
