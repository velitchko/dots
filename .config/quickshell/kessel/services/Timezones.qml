// SPDX-License-Identifier: GPL-3.0-or-later
// Europe/Vienna and Europe/Sofia clocks, via `TZ=<zone> date` (no Intl in
// this QML engine -- confirmed). Polls only while `wanted` is true.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property bool wanted: false
    property string vienna: ""
    property string sofia: ""

    function refresh() { viennaProc.running = true; sofiaProc.running = true }
    onWantedChanged: if (wanted) refresh()
    Connections { target: Time; function onTimeChanged() { if (root.wanted) root.refresh() } }

    Process {
        id: viennaProc
        command: ["env", "TZ=Europe/Vienna", "date", "+%H:%M"]
        stdout: StdioCollector { onStreamFinished: root.vienna = text.trim() }
    }
    Process {
        id: sofiaProc
        command: ["env", "TZ=Europe/Sofia", "date", "+%H:%M"]
        stdout: StdioCollector { onStreamFinished: root.sofia = text.trim() }
    }
}
