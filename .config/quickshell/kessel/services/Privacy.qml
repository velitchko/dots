// SPDX-License-Identifier: GPL-3.0-or-later
// Privacy indicators: microphone, camera and screen sharing in use.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

Singleton {
    id: root
    readonly property bool mic: Audio.recorders.length > 0
    readonly property string micApps: Audio.recorders.map(n => Audio.appName(n)).join(", ")
    property bool v4l2Open: false
    readonly property bool camera: Audio.cameras.length > 0 || v4l2Open
    property int screencasts: 0
    readonly property bool screen: screencasts > 0
    readonly property bool any: mic || camera || screen

    // Cameras opened directly (not via PipeWire): our processes holding /dev/video*.
    // For each camera user (those, plus PipeWire camera clients passed as args)
    // the probe prints the process and its ancestors, so the pill can jump to the
    // app's window: browsers open the camera in a helper process, not the one
    // that owns the window.
    property var camChains: []        // [[pid, ppid, …], …]
    PwObjectTracker { objects: Audio.cameras }   // fills their application.process.id
    readonly property var pwCamPids: Audio.cameras.map(n => (n.properties ?? {})["application.process.id"] ?? "").filter(p => p !== "")
    Process {
        id: camProbe
        command: ["sh", "-c", 'chain() { p=$1; while [ "${p:-0}" -gt 1 ] 2>/dev/null; do printf "%s " "$p"; p=$(awk "{print \\$4}" /proc/$p/stat 2>/dev/null); done; echo; }; '
            + 'v=""; for f in /proc/[0-9]*/fd/*; do case "$(readlink "$f" 2>/dev/null)" in /dev/video*) d=${f#/proc/}; v="$v ${d%%/*}";; esac; done; '
            + 'echo "v4l2:${v:+yes}"; for p in $(printf "%s\n" $v "$@" | sort -u); do chain "$p"; done', "sh"].concat(root.pwCamPids)
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                root.v4l2Open = (lines.shift() ?? "") === "v4l2:yes"
                root.camChains = lines.filter(l => l.trim() !== "").map(l => l.trim().split(/\s+/).map(Number))
            }
        }
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!camProbe.running) camProbe.running = true }

    // Click on the camera icon: there's no general way to "mute" a webcam (only
    // killing the app stops it), so jump to the window of the app using it.
    function focusCamera() {
        if (!camProbe.running) camProbe.running = true
        for (const chain of camChains)
            for (const pid of chain) {
                const t = Hypr.toplevels.find(w => w.lastIpcObject?.pid === pid)
                if (t) { IslandState.closePanel(); Hypr.focusWindow(t); return true }
            }
        return false
    }

    // Hyprland: "screencast>>STATE,OWNER" (1 = started, 0 = stopped)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "screencast") return
            const started = (event.data || "").split(",")[0] === "1"
            root.screencasts = Math.max(0, root.screencasts + (started ? 1 : -1))
        }
    }
}
