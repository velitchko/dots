// SPDX-License-Identifier: GPL-3.0-or-later
// Live audio spectrum from cava (raw ASCII output), for the Music perspective.
// Runs only while something asks for it (`wanted`), so it costs nothing idle.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool wanted: false
    readonly property int bars: 28
    property var values: []                 // 0..1 per bar
    property bool available: false
    readonly property bool running: proc.running

    readonly property string conf: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kessel-cava.conf"

    Process {
        running: true
        command: ["sh", "-c", "command -v cava >/dev/null"]
        onExited: code => root.available = code === 0
    }

    // write the cava config once, then run cava while wanted
    Process {
        id: writer
        running: root.available
        // framerate 20, not 30: each line triggers a full `values` array
        // reassignment, retriggering all `bars` height Behaviors at once --
        // on the same QML thread the Music perspective's marquee scroll
        // animates on. 20Hz is still smooth for 4-28 small bars and cuts
        // that contention by a third (reported: marquee stutters "at times"
        // while music plays, i.e. intermittently -- consistent with GUI-
        // thread contention, not a constant rendering defect).
        command: ["sh", "-c", 'cat > "$1" <<EOF\n[general]\nbars = ' + root.bars + '\nframerate = 20\nautosens = 1\n[input]\nmethod = pipewire\nsource = auto\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 100\nbar_delimiter = 59\nframe_delimiter = 10\n[smoothing]\nnoise_reduction = 60\nEOF', "sh", root.conf]
    }
    Process {
        id: proc
        running: root.wanted && root.available && !writer.running
        command: ["cava", "-p", root.conf]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";")
                const out = []
                for (let i = 0; i < root.bars; i++) out.push(Math.min(1, (parseInt(v[i]) || 0) / 100))
                root.values = out
            }
        }
        onRunningChanged: if (!running) root.values = []
    }
}
