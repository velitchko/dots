// SPDX-License-Identifier: GPL-3.0-or-later
// Screen recording with wf-recorder (full screen or a slurp region).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Singleton {
    id: root
    property bool available: false
    readonly property bool recording: rec.running
    property real startedAt: 0
    readonly property int elapsed: recording ? Math.floor((Time.now.getTime() - startedAt) / 1000) : 0
    property string file: ""

    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder >/dev/null && command -v slurp >/dev/null"]
        onExited: code => root.available = code === 0
    }

    function toggle(region) {
        if (recording) stop()
        else start(region)
    }
    function start(region) {
        if (!available) {
            Quickshell.execDetached(["notify-send", "-a", "Recorder", "wf-recorder is not installed", "sudo pacman -S wf-recorder"])
            return
        }
        file = Config.recordDir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4"
        if (region) {
            pick.running = true
        } else {
            // Name the output: with several outputs wf-recorder otherwise asks on
            // stdin which one to record, and waits forever (nothing gets recorded).
            const mon = Hyprland.focusedMonitor
            launch(mon ? ["-o", mon.name] : [])
        }
    }
    function launch(extra) {
        rec.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && exec wf-recorder -f "$1" "${@:2}"', "sh", file].concat(extra)
        startedAt = Date.now()
        rec.running = true
    }
    function stop() { if (recording) rec.signal(2) }   // SIGINT lets wf-recorder finalise the file

    Process {
        id: pick
        command: ["slurp", "-d"]
        stdout: StdioCollector { onStreamFinished: { const g = text.trim(); if (g !== "") root.launch(["-g", g]) } }
    }
    // Report failures instead of claiming "saved": wf-recorder's errors used to
    // be thrown away, so a recorder that died at once looked like nothing happened.
    property string lastError: ""
    Process {
        id: rec
        stderr: SplitParser { onRead: line => { if (/error|fail|cannot|unable|invalid|not supported/i.test(line)) root.lastError = line } }
        onStarted: root.lastError = ""
        onExited: code => {
            check.command = ["sh", "-c", 'test -s "$1"', "sh", root.file]
            check.failed = code !== 0 ? (root.lastError || ("wf-recorder exited with code " + code)) : ""
            check.running = true
        }
    }
    Process {
        id: check
        property string failed: ""
        onExited: code => {
            if (code === 0 && failed === "")
                Quickshell.execDetached(["notify-send", "-a", "Recorder", "Recording saved", root.file.replace(Quickshell.env("HOME"), "~")])
            else
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Recorder", "Recording failed",
                                         failed || root.lastError || "No video was written"])
        }
    }
}
