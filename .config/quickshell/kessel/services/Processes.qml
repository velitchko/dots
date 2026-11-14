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

    function parse(text) {
        const out = []
        for (const line of text.trim().split("\n")) {
            const m = line.match(/^(.*\S)\s+([\d.]+)$/)
            if (m) out.push({ name: m[1].trim(), pct: parseFloat(m[2]) })
            if (out.length >= 5) break
        }
        return out
    }
    function refresh() { cpuProc.running = true; memProc.running = true }
    Timer { interval: 3000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: cpuProc
        command: ["ps", "-e", "-o", "comm,%cpu", "--sort=-%cpu", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topCpu = root.parse(text) }
    }
    Process {
        id: memProc
        command: ["ps", "-e", "-o", "comm,%mem", "--sort=-%mem", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topMem = root.parse(text) }
    }
}
